import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/core/offline/executeur_actions.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/stockage_medias.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/reserve_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

class _MockRemote extends Mock implements ReserveRemoteDataSource {}

class _MockMedias extends Mock implements StockageMedias {}

/// Audit synchronisation — ce que l'exécuteur écrit en local APRÈS un succès.
///
/// ## Le défaut
///
/// Une réserve confirmée par le serveur était TOUJOURS réécrite « à jour »
/// (`en_attente = 0`), avec la version serveur — même quand un autre
/// changement fait hors ligne sur cette réserve attendait encore son tour.
/// Création confirmée, passage en « corrigée » pas encore parti : l'écran
/// retombait sur « créée », et un rafraîchissement de liste pouvait effacer
/// l'écriture optimiste avant même son envoi.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_executeur_confirmation.db';
    registerFallbackValue(ReserveSeverite.moyenne);
    registerFallbackValue(ReserveCategorie.autre);
    registerFallbackValue(ReserveStatut.creee);
  });

  late BaseLocale base;
  late CacheReserves cache;
  late FileAttente file;
  late _MockRemote remote;
  late ExecuteurActionsHorsLigne executeur;

  setUp(() async {
    base = BaseLocale.instance;
    await base.fermer();
    await base.viderTout();
    cache = CacheReserves(base);
    file = FileAttente(base);
    remote = _MockRemote();
    executeur = ExecuteurActionsHorsLigne(reserves: remote, cache: cache, medias: _MockMedias(), file: file);
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  Reserve serveur(String id, ReserveStatut statut) =>
      Reserve(id: id, numero: 'R-0042', chantierId: 'ch-1', titre: 'Fissure', statut: statut);

  Future<ActionEnAttente> deposer(TypeAction type, Map<String, dynamic> charge) async {
    final id = await file.deposer(type: type, charge: charge);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return (await file.parId(id))!;
  }

  void creationRepond(Reserve r) => when(() => remote.creerReserve(
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
      )).thenAnswer((_) async => r);

  test('création confirmée, statut hors ligne encore en file : le statut LOCAL est conservé, la ligne reste protégée', () async {
    // État local : réserve créée hors ligne puis passée en « corrigée ».
    await cache.enregistrer(
      const Reserve(id: 'res-1', numero: Reserve.numeroEnAttente, chantierId: 'ch-1', titre: 'Fissure', statut: ReserveStatut.corrigee),
      enAttente: true,
    );
    final creation = await deposer(TypeAction.creerReserve, {'id': 'res-1', 'chantierId': 'ch-1', 'titre': 'Fissure', 'phaseId': 'ph-1'});
    await deposer(TypeAction.changerStatutReserve, {'reserveId': 'res-1', 'statut': 'corrigee'});
    creationRepond(serveur('res-1', ReserveStatut.creee));

    await executeur.executer(creation);

    final relue = await cache.lire('res-1');
    expect(relue!.statut, ReserveStatut.corrigee, reason: 'l’utilisateur a déclaré la correction : l’écran doit le montrer');
    expect(relue.numero, 'R-0042', reason: 'le numéro définitif du serveur, lui, est repris');
    expect(await cache.estEnAttente('res-1'), isTrue, reason: 'un rafraîchissement ne doit pas l’écraser avant l’envoi du statut');
  });

  test('création confirmée sans autre action en file : version serveur, ligne à jour', () async {
    await cache.enregistrer(
      const Reserve(id: 'res-1', numero: Reserve.numeroEnAttente, chantierId: 'ch-1', titre: 'Fissure', statut: ReserveStatut.creee),
      enAttente: true,
    );
    final creation = await deposer(TypeAction.creerReserve, {'id': 'res-1', 'chantierId': 'ch-1', 'titre': 'Fissure', 'phaseId': 'ph-1'});
    creationRepond(serveur('res-1', ReserveStatut.creee));

    await executeur.executer(creation);

    expect((await cache.lire('res-1'))!.numero, 'R-0042');
    expect(await cache.estEnAttente('res-1'), isFalse);
  });

  test('statut confirmé alors qu’un statut PLUS RÉCENT attend : on garde le plus récent', () async {
    await cache.enregistrer(serveur('res-1', ReserveStatut.enCours), enAttente: true);
    final premier = await deposer(TypeAction.changerStatutReserve, {'reserveId': 'res-1', 'statut': 'affectee'});
    await deposer(TypeAction.changerStatutReserve, {'reserveId': 'res-1', 'statut': 'en_cours'});
    when(() => remote.changerStatut(reserveId: 'res-1', statut: ReserveStatut.affectee, motif: any(named: 'motif')))
        .thenAnswer((_) async => serveur('res-1', ReserveStatut.affectee));

    await executeur.executer(premier);

    expect((await cache.lire('res-1'))!.statut, ReserveStatut.enCours);
    expect(await cache.estEnAttente('res-1'), isTrue);
  });

  test('dernier statut confirmé : la ligne redevient à jour', () async {
    await cache.enregistrer(serveur('res-1', ReserveStatut.enCours), enAttente: true);
    final seul = await deposer(TypeAction.changerStatutReserve, {'reserveId': 'res-1', 'statut': 'en_cours'});
    when(() => remote.changerStatut(reserveId: 'res-1', statut: ReserveStatut.enCours, motif: any(named: 'motif')))
        .thenAnswer((_) async => serveur('res-1', ReserveStatut.enCours));

    await executeur.executer(seul);

    expect(await cache.estEnAttente('res-1'), isFalse);
  });

  test('une PHOTO encore en file ne retient pas la ligne « en attente »', () async {
    // Régression trouvée par le test de chaos : l'envoi d'une photo ne
    // repasse jamais par la confirmation — la ligne serait restée en attente
    // pour toujours, insensible à toute correction du serveur.
    await cache.enregistrer(serveur('res-1', ReserveStatut.enCours), enAttente: true);
    final statut = await deposer(TypeAction.changerStatutReserve, {'reserveId': 'res-1', 'statut': 'en_cours'});
    await file.deposer(
      type: TypeAction.ajouterPhotoReserve,
      charge: {'reserveId': 'res-1', 'type': 'photo'},
      cheminFichier: '/tmp/photo.jpg',
    );
    when(() => remote.changerStatut(reserveId: 'res-1', statut: ReserveStatut.enCours, motif: any(named: 'motif')))
        .thenAnswer((_) async => serveur('res-1', ReserveStatut.enCours));

    await executeur.executer(statut);

    expect(await cache.estEnAttente('res-1'), isFalse);
  });

  test('une photo sans fichier est une ActionInvalide (sortie du cycle), pas un StateError anonyme', () async {
    final photo = ActionEnAttente(
      id: 'p-1',
      type: TypeAction.ajouterPhotoReserve,
      charge: const {'reserveId': 'res-1'},
      creeLe: DateTime(2026, 9, 11),
    );

    await expectLater(executeur.executer(photo), throwsA(isA<ActionInvalide>()));
  });
}
