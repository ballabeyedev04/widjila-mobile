import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/executeur_actions.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/stockage_medias.dart';
import 'package:suivie_chantier_mobile/core/offline/synchronisation_service.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/reserve_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

import 'detecteur_simule.dart';

class _MockRemote extends Mock implements ReserveRemoteDataSource {}

class _MediasFaux extends Fake implements StockageMedias {}

/// File qui COMPTE les lignes qu'elle relit en entier — la mesure du coût
/// caché d'une synchronisation, indépendante de la vitesse de la machine.
class _FileComptee extends FileAttente {
  _FileComptee(super.base);
  int lignesRelues = 0;

  @override
  Future<List<ActionEnAttente>> aTraiter() async {
    final lignes = await super.aTraiter();
    lignesRelues += lignes.length;
    return lignes;
  }
}

/// Deuxième audit — coût d'une grosse file, et déconnexion pendant un envoi.
///
///  - A2-08 : chaque confirmation relisait TOUTE la file pour savoir s'il
///    restait une action sur la même réserve. Vider N actions coûtait donc
///    ~N²/2 lectures : 10 000 actions après une semaine au sous-sol, c'est
///    50 millions de lignes décodées — des minutes de CPU et de batterie.
///  - A2-09 : une action encore en vol au moment d'une déconnexion écrivait
///    sa réponse dans la base PURGÉE — celle du compte suivant.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_moteur_volume.db';
    registerFallbackValue(ReserveSeverite.moyenne);
    registerFallbackValue(ReserveCategorie.autre);
    registerFallbackValue(ReserveStatut.creee);
  });

  late BaseLocale base;
  late CacheReserves cache;
  late _MockRemote remote;

  setUp(() async {
    base = BaseLocale.instance;
    await base.fermer();
    await base.viderTout();
    cache = CacheReserves(base);
    remote = _MockRemote();
    when(() => remote.creerReserve(
          id: any(named: 'id'),
          chantierId: any(named: 'chantierId'),
          titre: any(named: 'titre'),
          description: any(named: 'description'),
          priorite: any(named: 'priorite'),
          categorie: any(named: 'categorie'),
          batimentId: any(named: 'batimentId'),
          etageId: any(named: 'etageId'),
          zoneId: any(named: 'zoneId'),
          lotId: any(named: 'lotId'),
          dateLimite: any(named: 'dateLimite'),
          planId: any(named: 'planId'),
          positionX: any(named: 'positionX'),
          positionY: any(named: 'positionY'),
          positionPage: any(named: 'positionPage'),
          partenaireId: any(named: 'partenaireId'),
          severite: any(named: 'severite'),
          corpsEtatId: any(named: 'corpsEtatId'),
          phaseId: any(named: 'phaseId'),
        )).thenAnswer((i) async => Reserve(
          id: i.namedArguments[#id] as String,
          numero: 'R-1',
          chantierId: 'ch-1',
          titre: 'T',
        ));
    when(() => remote.changerStatut(
          reserveId: any(named: 'reserveId'),
          statut: any(named: 'statut'),
          motif: any(named: 'motif'),
        )).thenAnswer((i) async => Reserve(
          id: i.namedArguments[#reserveId] as String,
          numero: 'R-1',
          chantierId: 'ch-1',
          titre: 'T',
          statut: i.namedArguments[#statut] as ReserveStatut,
        ));
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  test('A2-08 — vider N actions ne relit PAS N fois toute la file', () async {
    const n = 150;
    final file = _FileComptee(base);
    for (var i = 0; i < n; i++) {
      await file.deposer(type: TypeAction.creerReserve, charge: {'id': 'r$i', 'chantierId': 'ch-1', 'titre': 'T$i', 'phaseId': 'ph'});
      await file.deposer(type: TypeAction.changerStatutReserve, charge: {'reserveId': 'r$i', 'statut': 'affectee'});
    }
    final executeur = ExecuteurActionsHorsLigne(reserves: remote, cache: cache, medias: _MediasFaux(), file: file);
    final service = SynchronisationService(
      file: file,
      detecteur: DetecteurSimule(EtatReseau.enLigne),
      base: base,
      executer: executeur.executer,
      delaisRelance: const [],
    );
    file.lignesRelues = 0;

    final chrono = Stopwatch()..start();
    await service.synchroniser();
    chrono.stop();
    // Mesure publiée dans le rapport d'audit.
    // ignore: avoid_print
    print('[volume] ${2 * n} actions vidées en ${chrono.elapsedMilliseconds} ms, ${file.lignesRelues} lignes relues');

    expect(await file.nombreEnAttente(), 0);
    expect(file.lignesRelues, lessThan(3 * 2 * n),
        reason: 'le coût doit rester LINÉAIRE ; ~N²/2 = ${(2 * n) * (2 * n) ~/ 2} en cas de relecture intégrale');
    await service.arreter();
    // Délai EXPLICITE : ce test vérifie la LINÉARITÉ (lignes relues), pas la
    // vitesse. Seul, il vide 300 actions dans une vraie base SQLite en ~11 s ;
    // en suite complète, les fichiers de test tournent en parallèle et le
    // délai par défaut de 30 s coupait parfois le test en plein travail —
    // un échec qui ne disait rien du moteur.
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('A2-09 — une action en vol pendant une déconnexion n’écrit rien dans la base purgée', () async {
    final file = FileAttente(base);
    await base.definirProprietaire('u-1');
    await file.deposer(type: TypeAction.creerReserve, charge: {'id': 'res-1', 'chantierId': 'ch-1', 'titre': 'T', 'phaseId': 'ph'});
    final reponse = Completer<void>();
    var appele = false;
    when(() => remote.creerReserve(
          id: any(named: 'id'),
          chantierId: any(named: 'chantierId'),
          titre: any(named: 'titre'),
          description: any(named: 'description'),
          priorite: any(named: 'priorite'),
          categorie: any(named: 'categorie'),
          batimentId: any(named: 'batimentId'),
          etageId: any(named: 'etageId'),
          zoneId: any(named: 'zoneId'),
          lotId: any(named: 'lotId'),
          dateLimite: any(named: 'dateLimite'),
          planId: any(named: 'planId'),
          positionX: any(named: 'positionX'),
          positionY: any(named: 'positionY'),
          positionPage: any(named: 'positionPage'),
          partenaireId: any(named: 'partenaireId'),
          severite: any(named: 'severite'),
          corpsEtatId: any(named: 'corpsEtatId'),
          phaseId: any(named: 'phaseId'),
        )).thenAnswer((_) async {
      appele = true;
      await reponse.future;
      return const Reserve(id: 'res-1', numero: 'R-1', chantierId: 'ch-1', titre: 'T');
    });
    final executeur = ExecuteurActionsHorsLigne(reserves: remote, cache: cache, medias: _MediasFaux(), file: file);
    final service = SynchronisationService(
      file: file,
      detecteur: DetecteurSimule(EtatReseau.enLigne),
      base: base,
      executer: executeur.executer,
      delaisRelance: const [],
    );

    final passe = service.synchroniser();
    while (!appele) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // L'utilisateur se déconnecte pendant que la requête est en vol.
    await base.viderTout();
    reponse.complete();
    await passe;

    expect(await cache.lire('res-1'), isNull, reason: 'la réponse appartient au compte précédent');
    await service.arreter();
  });
}
