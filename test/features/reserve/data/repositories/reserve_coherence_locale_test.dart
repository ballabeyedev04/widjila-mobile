import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/stockage_medias.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/reserve_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/repositories/reserve_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';

import '../../../../core/offline/detecteur_simule.dart';

class _MockRemote extends Mock implements ReserveRemoteDataSource {}

/// Copie de photo sans disque : le test porte sur l'ORDRE, pas sur le fichier.
class _MediasFaux extends Fake implements StockageMedias {
  @override
  Future<String> copier(String cheminSource, String idAction) async => '/tmp/$idAction.jpg';

  @override
  Future<void> supprimer(String chemin) async {}
}

Reserve _r(String id, ReserveStatut statut, {String titre = 'Fissure', String numero = 'R-0001', String? description}) =>
    Reserve(id: id, numero: numero, chantierId: 'ch-1', titre: titre, statut: statut, description: description);

/// Deuxième audit — la base locale reste la source de vérité de l'ÉCRAN tant
/// qu'un changement local n'est pas confirmé par le serveur.
///
/// Défauts visés (reproduits AVANT correction) :
///  - A2-01 : en ligne, une action directe doublait une action plus ancienne
///    encore en file pour la même réserve (ordre inversé) ;
///  - A2-02 : une lecture en ligne écrasait une ligne en attente et effaçait
///    son marqueur ;
///  - A2-04 : une réserve créée hors ligne, pas encore envoyée, disparaissait
///    des listes dès qu'on était en ligne ;
///  - A2-12 : modifier ou supprimer une réserve hors ligne était impossible.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_coherence_locale.db';
    registerFallbackValue(ReserveStatut.creee);
  });

  late BaseLocale base;
  late CacheReserves cache;
  late FileAttente file;
  late _MockRemote remote;

  setUp(() async {
    base = BaseLocale.instance;
    await base.fermer();
    await base.viderTout();
    cache = CacheReserves(base);
    file = FileAttente(base);
    remote = _MockRemote();
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  ReserveRepositoryImpl repo({required bool enLigne}) => ReserveRepositoryImpl(
        remote,
        detecteur: DetecteurSimule(enLigne ? EtatReseau.enLigne : EtatReseau.horsLigne),
        fileAttente: file,
        cache: cache,
        medias: _MediasFaux(),
      );

  Future<void> pause() => Future<void>.delayed(const Duration(milliseconds: 5));

  group('A2-01 — l’ordre des actions d’une même réserve est préservé en ligne', () {
    test('un statut sur une réserve qui a déjà une action en file passe PAR LA FILE', () async {
      await cache.enregistrer(_r('res-1', ReserveStatut.affectee), enAttente: true);
      await file.deposer(type: TypeAction.changerStatutReserve, charge: {'reserveId': 'res-1', 'statut': 'affectee'});
      await pause();

      final r = await repo(enLigne: true).changerStatut(reserveId: 'res-1', statut: ReserveStatut.enCours);

      expect(r.isRight(), isTrue);
      verifyNever(() => remote.changerStatut(
          reserveId: any(named: 'reserveId'), statut: any(named: 'statut'), motif: any(named: 'motif')));
      final actions = await file.aTraiter();
      expect(actions.map((a) => a.charge['statut']), ['affectee', 'en_cours'],
          reason: 'l’ancien statut ne doit jamais repasser APRÈS le nouveau');
      expect((await cache.lire('res-1'))!.statut, ReserveStatut.enCours);
    });

    test('une photo sur une réserve dont la création attend encore part APRÈS elle', () async {
      await cache.enregistrer(_r('res-1', ReserveStatut.creee, numero: Reserve.numeroEnAttente), enAttente: true);
      await file.deposer(type: TypeAction.creerReserve, charge: {'id': 'res-1', 'titre': 'Fissure', 'phaseId': 'ph-1'});
      await pause();

      final r = await repo(enLigne: true).ajouterMedia(reserveId: 'res-1', cheminFichier: '/camera/p.jpg');

      expect(r.isRight(), isTrue);
      verifyNever(() => remote.ajouterMedia(
          reserveId: any(named: 'reserveId'), cheminFichier: any(named: 'cheminFichier'), type: any(named: 'type')));
      expect((await file.aTraiter()).map((a) => a.type.code), ['creerReserve', 'ajouterPhotoReserve']);
    });
  });

  group('A2-02 — une lecture en ligne n’écrase pas un changement local en attente', () {
    test('le détail montre le statut LOCAL en attente, le reste vient du serveur', () async {
      // L'état RÉEL d'un changement hors ligne : la ligne locale ET l'action
      // en file, écrites ensemble (`FileAttente.deposer(avecEcriture:)`). La
      // vue se reconstruit en rejouant l'action sur la version serveur
      // (`reconciliation.dart`).
      //
      // Le test ne posait que la ligne, sans l'action : un état que l'app ne
      // produit plus depuis l'écriture atomique, et que le cache traite par
      // prudence en gardant la ligne locale entière (voir le test suivant).
      await cache.enregistrer(_r('res-1', ReserveStatut.corrigee), enAttente: true);
      await file.deposer(type: TypeAction.changerStatutReserve, charge: {'reserveId': 'res-1', 'statut': 'corrigee'});
      await pause();
      when(() => remote.getReserveDetail('res-1'))
          .thenAnswer((_) async => _r('res-1', ReserveStatut.affectee, titre: 'Titre du serveur'));

      final r = await repo(enLigne: true).getReserveDetail('res-1');

      final vue = r.getOrElse(() => throw StateError('échec inattendu'));
      expect(vue.statut, ReserveStatut.corrigee, reason: 'l’écran montre ce que l’utilisateur a fait');
      expect(vue.titre, 'Titre du serveur');
      expect(await cache.estEnAttente('res-1'), isTrue, reason: 'le marqueur « en attente » ne doit pas tomber');
      expect((await cache.lire('res-1'))!.statut, ReserveStatut.corrigee);
    });

    test('ligne « en attente » HÉRITÉE, sans action en file : rien de ce que l’utilisateur voit n’est effacé',
        () async {
      // État laissé par une version antérieure à l'écriture atomique. On ne
      // sait pas QUEL champ a été changé localement : plutôt que de deviner,
      // la ligne locale est gardée entière et reste marquée (`cache_reserves.dart`).
      await cache.enregistrer(_r('res-1', ReserveStatut.corrigee, titre: 'Titre local'), enAttente: true);
      when(() => remote.getReserveDetail('res-1'))
          .thenAnswer((_) async => _r('res-1', ReserveStatut.affectee, titre: 'Titre du serveur'));

      final vue = (await repo(enLigne: true).getReserveDetail('res-1'))
          .getOrElse(() => throw StateError('échec inattendu'));

      expect(vue.statut, ReserveStatut.corrigee);
      expect(vue.titre, 'Titre local');
      expect(await cache.estEnAttente('res-1'), isTrue);
    });

    test('sans changement en attente, le détail serveur remplace la ligne', () async {
      await cache.enregistrer(_r('res-1', ReserveStatut.affectee));
      when(() => remote.getReserveDetail('res-1'))
          .thenAnswer((_) async => _r('res-1', ReserveStatut.enCours, titre: 'À jour'));

      await repo(enLigne: true).getReserveDetail('res-1');

      expect((await cache.lire('res-1'))!.statut, ReserveStatut.enCours);
      expect(await cache.estEnAttente('res-1'), isFalse);
    });
  });

  group('A2-04 — les listes en ligne montrent aussi le travail local pas encore envoyé', () {
    test('une réserve créée hors ligne reste visible, et un statut en attente est celui affiché', () async {
      await cache.enregistrer(_r('locale', ReserveStatut.creee, numero: Reserve.numeroEnAttente), enAttente: true);
      await cache.enregistrer(_r('srv-2', ReserveStatut.corrigee), enAttente: true);
      when(() => remote.getToutesReserves(page: any(named: 'page'), limit: any(named: 'limit')))
          .thenAnswer((_) async => ReservePage(items: [_r('srv-1', ReserveStatut.creee), _r('srv-2', ReserveStatut.affectee)], total: 2));

      final r = await repo(enLigne: true).getToutesReserves();

      final page = r.getOrElse(() => throw StateError('échec inattendu'));
      expect(page.items.map((x) => x.id), containsAll(['locale', 'srv-1', 'srv-2']));
      expect(page.items.firstWhere((x) => x.id == 'srv-2').statut, ReserveStatut.corrigee);
    });

    test('un filtre de statut s’applique aussi au travail local', () async {
      await cache.enregistrer(_r('locale', ReserveStatut.creee, numero: Reserve.numeroEnAttente), enAttente: true);
      when(() => remote.getToutesReserves(
              page: any(named: 'page'), limit: any(named: 'limit'), statut: ReserveStatut.corrigee))
          .thenAnswer((_) async => const ReservePage(items: [], total: 0));

      final r = await repo(enLigne: true).getToutesReserves(statut: ReserveStatut.corrigee);

      expect(r.getOrElse(() => throw StateError('x')).items, isEmpty);
    });
  });

  group('A2-12 — modifier et supprimer hors ligne', () {
    test('modifier le titre hors ligne : écrit en local ET mis en file, avec la valeur de départ', () async {
      await cache.enregistrer(_r('res-1', ReserveStatut.affectee, titre: 'Ancien titre'));

      final r = await repo(enLigne: false).modifierReserve(id: 'res-1', titre: 'Nouveau titre');

      expect(r.isRight(), isTrue);
      expect((await cache.lire('res-1'))!.titre, 'Nouveau titre');
      expect(await cache.estEnAttente('res-1'), isTrue);
      final action = (await file.aTraiter()).single;
      expect(action.type.code, 'modifierReserve');
      expect((action.charge['champs'] as Map)['titre'], 'Nouveau titre');
      expect((action.charge['valeursInitiales'] as Map)['titre'], 'Ancien titre',
          reason: 'sans valeur de départ, le serveur ne peut pas détecter un conflit');
    });

    test('supprimer hors ligne : la réserve disparaît de l’écran, la suppression part en file', () async {
      await cache.enregistrer(_r('res-1', ReserveStatut.affectee));

      final r = await repo(enLigne: false).supprimerReserve('res-1');

      expect(r.isRight(), isTrue);
      expect(await cache.lire('res-1'), isNull);
      expect((await file.aTraiter()).single.type.code, 'supprimerReserve');
    });
  });
}
