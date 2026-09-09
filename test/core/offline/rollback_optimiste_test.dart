import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/synchronisation_service.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

import 'detecteur_simule.dart';

/// Ce qui se passe quand le serveur REFUSE définitivement une action mise en
/// file hors ligne.
///
/// Le défaut d'origine, en quatre temps :
///
///   1. le mobile écrit le nouveau statut en base locale avec `en_attente = 1`,
///      avant toute confirmation ;
///   2. au retour du réseau, le serveur répond 4xx (transition illégale,
///      preuves manquantes, droits retirés, réserve figée) ;
///   3. l'ACTION était marquée en échec définitif — et la ligne de cache,
///      jamais touchée ;
///   4. `CacheReserves.enregistrerTous` ÉPARGNE les lignes « en attente » :
///      plus aucune réponse du serveur ne pouvait corriger la valeur.
///
/// L'écran affichait donc indéfiniment un état que le serveur avait rejeté —
/// y compris après rafraîchissement, redémarrage et rechargement de la liste.
Future<void> _attendre(
  bool Function() condition, {
  Duration limite = const Duration(seconds: 5),
}) async {
  final fin = DateTime.now().add(limite);
  while (!condition()) {
    if (DateTime.now().isAfter(fin)) {
      throw StateError('Condition non remplie dans le délai imparti');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

DioException _erreurHttp(int code) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: code),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_rollback_optimiste.db';
  });

  late BaseLocale base;
  late FileAttente file;
  late CacheReserves cache;

  setUp(() async {
    base = BaseLocale.instance;
    await base.fermer();
    await base.viderTout();
    file = FileAttente(base);
    cache = CacheReserves(base);
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  Reserve reserve(ReserveStatut statut) => Reserve(
        id: 'r1',
        numero: 'R-0001',
        chantierId: 'c1',
        titre: 'Fissure au plafond',
        statut: statut,
      );

  /// La version « serveur » de la réserve, telle qu'un rafraîchissement la
  /// rapporterait.
  final duServeur = [reserve(ReserveStatut.corrigee)];

  test('une écriture optimiste refusée est DÉFAITE', () async {
    // 1. L'utilisateur passe la réserve à « validée » sans réseau.
    await cache.enregistrer(reserve(ReserveStatut.validee), enAttente: true);
    await file.deposer(
      type: TypeAction.changerStatutReserve,
      charge: {'reserveId': 'r1', 'statut': 'validee'},
    );

    // 2. Le réseau revient, le serveur refuse (preuves de correction absentes).
    final detecteur = DetecteurSimule(EtatReseau.horsLigne);
    var annulees = 0;
    final service = SynchronisationService(
      file: file,
      detecteur: detecteur,
      base: base,
      executer: (_) async => throw _erreurHttp(400),
      annuler: (action) async {
        annulees++;
        // Ce que fait réellement `ExecuteurActionsHorsLigne.annuler` : rétablir
        // la vérité du serveur.
        await cache.enregistrer(duServeur.first, enAttente: false);
      },
    );
    await service.demarrer();
    detecteur.basculer(EtatReseau.enLigne);

    await _attendre(() => annulees == 1);
    // La passe de synchronisation continue APRÈS l'annulation (compteurs,
    // notification d'état). L'arrêter en plein vol disposerait le notifieur
    // qu'elle s'apprête à écrire — un échec de test qui ne dit rien du
    // comportement mesuré ici.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // 3. La ligne locale porte de nouveau l'état du serveur, et n'est plus
    //    « en attente » : un rafraîchissement pourra l'écraser.
    final apres = await cache.lire('r1');
    expect(apres?.statut, ReserveStatut.corrigee);
    expect(await cache.estEnAttente('r1'), isFalse);

    await service.arreter();
  });

  test('une écriture optimiste NON refusée reste protégée', () async {
    // Contrôle symétrique : le rollback ne doit pas défaire le travail hors
    // ligne encore en attente. Une coupure réseau n'est pas un refus.
    await cache.enregistrer(reserve(ReserveStatut.enCours), enAttente: true);
    await file.deposer(
      type: TypeAction.changerStatutReserve,
      charge: {'reserveId': 'r1', 'statut': 'en_cours'},
    );

    final detecteur = DetecteurSimule(EtatReseau.horsLigne);
    var annulees = 0;
    final service = SynchronisationService(
      file: file,
      detecteur: detecteur,
      base: base,
      // 500 : panne passagère, on retentera — ce n'est PAS un refus.
      executer: (_) async => throw _erreurHttp(500),
      annuler: (_) async => annulees++,
    );
    await service.demarrer();
    detecteur.basculer(EtatReseau.enLigne);

    // On laisse la passe de synchronisation se dérouler entièrement : l'action
    // doit rester dans la file, en échec TEMPORAIRE, et rien ne doit être
    // défait.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(annulees, 0, reason: 'un 5xx ne défait rien : il sera retenté');
    expect(await cache.estEnAttente('r1'), isTrue);

    await service.arreter();
  });

  test('libererEnAttente rend la ligne écrasable par le serveur', () async {
    // Le mécanisme de secours, quand la vérité du serveur n'est pas joignable
    // au moment du refus.
    await cache.enregistrer(reserve(ReserveStatut.validee), enAttente: true);
    expect(await cache.estEnAttente('r1'), isTrue);

    // Tant que la ligne est « en attente », la version serveur est ignorée.
    await cache.enregistrerTous(duServeur);
    expect((await cache.lire('r1'))?.statut, ReserveStatut.validee);

    await cache.libererEnAttente('r1');
    expect(await cache.estEnAttente('r1'), isFalse);

    // Une fois relâchée, elle accepte de nouveau la version du serveur.
    await cache.enregistrerTous(duServeur);
    expect((await cache.lire('r1'))?.statut, ReserveStatut.corrigee);
  });
}
