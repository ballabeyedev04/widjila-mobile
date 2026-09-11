import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/executeur_actions.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/stockage_medias.dart';
import 'package:suivie_chantier_mobile/core/offline/synchronisation_service.dart';
import 'package:suivie_chantier_mobile/core/offline/tirage_reserves.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/reserve_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/repositories/reserve_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

import 'detecteur_simule.dart';

/// Matrice des transitions — COPIE de `TRANSITIONS` (backend
/// `reserve.service.js`). Le serveur simulé applique les mêmes règles que le
/// vrai, correctif compris : un statut identique rejoué est sans effet.
const _transitions = <String, List<String>>{
  'creee': ['affectee', 'en_cours', 'rouverte'],
  'affectee': ['prise_en_charge', 'en_cours', 'corrigee', 'rouverte'],
  'prise_en_charge': ['en_cours', 'corrigee', 'rouverte'],
  'en_cours': ['corrigee', 'a_verifier', 'rouverte'],
  'corrigee': ['a_verifier', 'validee', 'refusee', 'rouverte'],
  'a_verifier': ['validee', 'refusee', 'en_cours', 'rouverte'],
  'validee': ['cloturee', 'rouverte'],
  'refusee': ['en_cours', 'corrigee', 'rouverte'],
  'rouverte': ['affectee', 'prise_en_charge', 'en_cours', 'corrigee', 'a_verifier'],
  'cloturee': [],
};

class _LigneServeur {
  String titre;
  String statut;
  final String numero;
  final String chantierId;
  bool supprimee = false;
  int marque;
  final List<String> photos = [];

  _LigneServeur({required this.titre, required this.statut, required this.numero, required this.chantierId, required this.marque});
}

/// Serveur simulé, fidèle aux règles du backend CORRIGÉ :
///  - création idempotente par identifiant client ;
///  - statut identique rejoué = succès sans effet ; transition hors matrice = 400 ;
///  - média dédoublonné par contenu (empreinte) ;
///  - tirage incrémental par curseur, suppressions comprises.
///
/// Et, à la demande, INJECTE des pannes : coupure avant la requête, 503, 429,
/// et surtout la RÉPONSE PERDUE — le serveur a écrit, le mobile ne le sait pas.
class _ServeurSimule {
  _ServeurSimule(this._alea);

  final Random _alea;
  final lignes = <String, _LigneServeur>{};
  int _horloge = 0;
  int _numero = 0;

  double pCoupureAvant = 0;
  double p503 = 0;
  double p429 = 0;
  double pPerteReponse = 0;

  int requetes = 0;
  int reponsesPerdues = 0;
  int pannesInjectees = 0;

  void calmer() => pCoupureAvant = p503 = p429 = pPerteReponse = 0;

  T _appel<T>(T Function() operation) {
    requetes++;
    final tirage = _alea.nextDouble();
    if (tirage < pCoupureAvant) {
      pannesInjectees++;
      throw const NetworkException();
    }
    if (tirage < pCoupureAvant + p503) {
      pannesInjectees++;
      throw const ServerException(message: 'Service indisponible', statusCode: 503);
    }
    if (tirage < pCoupureAvant + p503 + p429) {
      pannesInjectees++;
      throw const ServerException(message: 'Trop de requêtes', statusCode: 429);
    }
    final resultat = operation();
    if (_alea.nextDouble() < pPerteReponse) {
      reponsesPerdues++;
      throw const NetworkException();
    }
    return resultat;
  }

  Reserve _vers(String id) {
    final l = lignes[id]!;
    return Reserve(id: id, numero: l.numero, chantierId: l.chantierId, titre: l.titre, statut: ReserveStatutX.fromString(l.statut));
  }

  Reserve creer(String id, String chantierId, String titre) => _appel(() {
        final existante = lignes[id];
        if (existante != null) {
          if (existante.supprimee) throw const ServerException(message: 'Réserve supprimée', statusCode: 400);
          return _vers(id);
        }
        _numero++;
        lignes[id] = _LigneServeur(
          titre: titre,
          statut: 'creee',
          numero: 'R-${_numero.toString().padLeft(4, '0')}',
          chantierId: chantierId,
          marque: ++_horloge,
        );
        return _vers(id);
      });

  Reserve changerStatut(String id, String statut) => _appel(() {
        final l = lignes[id];
        if (l == null || l.supprimee) throw const ServerException(message: 'Réserve introuvable', statusCode: 400);
        if (l.statut == statut) return _vers(id);
        if (!(_transitions[l.statut] ?? const []).contains(statut)) {
          throw ServerException(message: 'Transition impossible : ${l.statut} → $statut.', statusCode: 400);
        }
        l
          ..statut = statut
          ..marque = ++_horloge;
        return _vers(id);
      });

  ReserveMedia ajouterMedia(String reserveId, String chemin) => _appel(() {
        final l = lignes[reserveId];
        if (l == null || l.supprimee) throw const ServerException(message: 'Réserve introuvable', statusCode: 400);
        final contenu = File(chemin).readAsStringSync();
        if (!l.photos.contains(contenu)) l.photos.add(contenu);
        return ReserveMedia(id: 'm-$contenu', type: 'photo', url: 'https://cdn.test/$contenu', prisLe: DateTime(2026, 9, 11));
      });

  Reserve detail(String id) => _appel(() {
        final l = lignes[id];
        if (l == null || l.supprimee) throw const ServerException(message: 'Réserve introuvable', statusCode: 404);
        return _vers(id);
      });

  LotSyncReserves delta(String? curseur) => _appel(() {
        const limite = 3;
        final depuis = int.tryParse(curseur ?? '') ?? 0;
        final changements = lignes.entries.where((e) => e.value.marque > depuis).toList()
          ..sort((a, b) => a.value.marque.compareTo(b.value.marque));
        final page = changements.take(limite).toList();
        return LotSyncReserves(
          modifiees: page.where((e) => !e.value.supprimee).map((e) => _vers(e.key)).toList(),
          supprimees: page.where((e) => e.value.supprimee).map((e) => e.key).toList(),
          curseur: page.isEmpty ? (curseur ?? '0') : '${page.last.value.marque}',
          termine: changements.length <= limite,
        );
      });

  // Gestes faits « depuis le web », hors de toute panne.
  void supprimerDepuisLeWeb(String id) => lignes[id]!
    ..supprimee = true
    ..marque = ++_horloge;

  void renommerDepuisLeWeb(String id, String titre) => lignes[id]!
    ..titre = titre
    ..marque = ++_horloge;

  Set<String> get vivantes => lignes.entries.where((e) => !e.value.supprimee).map((e) => e.key).toSet();
}

/// Datasource branchée sur le serveur simulé — rien ne passe si l'appareil
/// est hors ligne.
class _DatasourceSimulee extends Fake implements ReserveRemoteDataSource {
  _DatasourceSimulee(this._serveur, this._reseau);

  final _ServeurSimule _serveur;
  final DetecteurSimule _reseau;

  void _exigerReseau() {
    if (!_reseau.estEnLigne) throw const NetworkException();
  }

  @override
  Future<Reserve> creerReserve({
    required String chantierId,
    required String titre,
    String? description,
    required ReserveSeverite priorite,
    required ReserveCategorie categorie,
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? lotId,
    DateTime? dateLimite,
    String? planId,
    double? positionX,
    double? positionY,
    int positionPage = 1,
    String? partenaireId,
    ReserveSeverite? severite,
    String? corpsEtatId,
    String? phaseId,
    String? id,
  }) async {
    _exigerReseau();
    return _serveur.creer(id!, chantierId, titre);
  }

  @override
  Future<Reserve> changerStatut({required String reserveId, required ReserveStatut statut, String? motif}) async {
    _exigerReseau();
    return _serveur.changerStatut(reserveId, statut.raw);
  }

  @override
  Future<ReserveMedia> ajouterMedia({required String reserveId, required String cheminFichier, String type = 'photo'}) async {
    _exigerReseau();
    return _serveur.ajouterMedia(reserveId, cheminFichier);
  }

  @override
  Future<Reserve> getReserveDetail(String id) async {
    _exigerReseau();
    return _serveur.detail(id);
  }

  @override
  Future<LotSyncReserves> syncReserves({String? curseur, int limite = 200}) async {
    _exigerReseau();
    return _serveur.delta(curseur);
  }
}

/// La photo reste sur le disque du test : son ménage n'est pas l'objet ici.
class _MediasSansMenage extends Fake implements StockageMedias {
  @override
  Future<void> supprimer(String chemin) async {}
}

/// Un téléphone : son propre fichier de base, son propre réseau. [demarrer]
/// recrée TOUS les objets — c'est un redémarrage d'application, le disque seul
/// survit.
class _Appareil {
  _Appareil(this.nom, this.serveur);

  final String nom;
  final _ServeurSimule serveur;
  final reseau = DetecteurSimule(EtatReseau.enLigne);

  late FileAttente file;
  late CacheReserves cache;
  late ReserveRepositoryImpl repo;
  late SynchronisationService sync;

  bool _allume = false;

  String get fichier => 'test_chaos_$nom.db';

  Future<void> preparer() async {
    await BaseLocale.instance.fermer();
    BaseLocale.surchargeNomFichier = fichier;
    await BaseLocale.instance.viderTout();
    await BaseLocale.instance.definirProprietaire('u-1');
    await BaseLocale.instance.fermer();
  }

  Future<void> demarrer() async {
    await BaseLocale.instance.fermer();
    BaseLocale.surchargeNomFichier = fichier;
    final base = BaseLocale.instance;
    file = FileAttente(base);
    cache = CacheReserves(base);
    final ds = _DatasourceSimulee(serveur, reseau);
    repo = ReserveRepositoryImpl(ds, detecteur: reseau, fileAttente: file, cache: cache, medias: StockageMedias());
    final executeur = ExecuteurActionsHorsLigne(reserves: ds, cache: cache, medias: _MediasSansMenage(), file: file);
    final tirage = TirageReserves(base: base, cache: cache, lireLot: (c) => ds.syncReserves(curseur: c));
    sync = SynchronisationService(
      file: file,
      detecteur: reseau,
      base: base,
      executer: executeur.executer,
      annuler: executeur.annuler,
      tirer: () async {
        await tirage.tirer();
      },
      // Les passes sont pilotées par le test : aucune relance en tâche de fond.
      delaisRelance: const [],
    );
    _allume = true;
  }

  /// L'application est TUÉE : plus rien en mémoire, seul le disque reste.
  Future<void> tuer() async {
    if (!_allume) return;
    await sync.arreter();
    await BaseLocale.instance.fermer();
    _allume = false;
  }

  Future<String> creer(String titre) async {
    final r = await repo.creerReserve(
      chantierId: 'ch-1',
      titre: titre,
      priorite: ReserveSeverite.moyenne,
      categorie: ReserveCategorie.autre,
      phaseId: 'ph-1',
    );
    return r.fold((f) => throw StateError('création refusée : ${f.errorMessage}'), (r) => r.id);
  }

  Future<void> statut(String id, ReserveStatut statut) async {
    final r = await repo.changerStatut(reserveId: id, statut: statut);
    r.fold((f) => throw StateError('statut refusé : ${f.errorMessage}'), (_) {});
  }

  Future<Map<String, Reserve>> etatLocal() async => {for (final r in await cache.listerTout()) r.id: r};
}

String _libelle(ActionEnAttente a) => switch (a.type) {
      TypeAction.creerReserve => 'creer:${a.charge['id']}',
      TypeAction.ajouterPhotoReserve => 'photo:${a.charge['reserveId']}',
      TypeAction.changerStatutReserve => 'statut:${a.charge['reserveId']}',
      TypeAction.envoyerRapport => 'rapport:${a.charge['rapportId']}',
      // Ajoutés au deuxième audit (A2-12) — même clé que le statut et la
      // photo : la réserve visée.
      TypeAction.modifierReserve => 'modifier:${a.charge['reserveId']}',
      TypeAction.supprimerReserve => 'supprimer:${a.charge['reserveId']}',
    };

/// Audit synchronisation — scénario CHAOS complet et convergence
/// multi-appareils, sur les VRAIS composants mobiles (repository, file,
/// cache, exécuteur, moteur de synchronisation, tirage incrémental) branchés
/// sur un serveur simulé fidèle aux règles du backend.
///
/// Ce que ces tests prouvent, au-delà des tests unitaires :
///  - des centaines de pannes mêlées (réponses perdues, 503, 429, coupures,
///    réseau qui bascule, application tuée) ne créent AUCUN doublon, ne
///    perdent AUCUNE action, et laissent LOCAL et SERVEUR identiques ;
///  - deux appareils qui travaillent hors ligne sur les mêmes réserves
///    CONVERGENT vers l'état du serveur, conflit métier compris.
///
/// Ce qu'ils ne prouvent PAS : le comportement d'un vrai PostgreSQL, d'un
/// vrai réseau mobile ou d'un vrai système qui tue le processus au milieu
/// d'une écriture SQLite — voir le rapport d'audit (« non vérifié »).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dossierPhotos;
  var compteurPhotos = 0;

  setUp(() async {
    dossierPhotos = await Directory.systemTemp.createTemp('chaos_photos_');
  });

  tearDown(() async {
    await BaseLocale.instance.fermer();
    if (await dossierPhotos.exists()) await dossierPhotos.delete(recursive: true);
  });

  /// Photo prise hors ligne : un fichier au contenu UNIQUE, déposé en file.
  Future<String> photo(_Appareil a, String reserveId) async {
    compteurPhotos++;
    final contenu = 'photo-$compteurPhotos';
    final f = File('${dossierPhotos.path}/$contenu.jpg')..writeAsStringSync(contenu);
    await a.file.deposer(
      type: TypeAction.ajouterPhotoReserve,
      charge: {'reserveId': reserveId, 'type': 'photo'},
      cheminFichier: f.path,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return contenu;
  }

  for (final graine in [1, 7, 42, 2024, 31337]) {
    test('chaos complet (graine $graine) : aucun doublon, aucune perte, LOCAL = SERVEUR', () async {
      final alea = Random(graine);
      final serveur = _ServeurSimule(alea);
      final a = _Appareil('solo', serveur);
      await a.preparer();
      await a.demarrer();

      // 1. EN LIGNE, serveur parfait : trois réserves.
      final enLigne = [for (var i = 0; i < 3; i++) await a.creer('En ligne $i')];

      // 2. HORS LIGNE : cinq réserves, des statuts, des photos.
      a.reseau.basculer(EtatReseau.horsLigne);
      final horsLigne = [for (var i = 0; i < 5; i++) await a.creer('Hors ligne $i')];
      final statutsAttendus = <String, ReserveStatut>{};
      for (final id in horsLigne.take(3)) {
        await a.statut(id, ReserveStatut.affectee);
        await a.statut(id, ReserveStatut.enCours);
        statutsAttendus[id] = ReserveStatut.enCours;
      }
      await a.statut(enLigne[0], ReserveStatut.affectee);
      statutsAttendus[enLigne[0]] = ReserveStatut.affectee;

      final photosAttendues = <String, List<String>>{
        horsLigne[0]: [await photo(a, horsLigne[0]), await photo(a, horsLigne[0])],
        horsLigne[1]: [await photo(a, horsLigne[1])],
        enLigne[2]: [await photo(a, enLigne[2])],
      };
      // Photo sur une réserve que le WEB va supprimer : elle ne peut pas passer.
      await photo(a, enLigne[1]);

      expect(await a.file.nombreEnAttente(), 5 + 7 + 5);

      // 3. Application TUÉE hors ligne, puis relancée : la file a survécu.
      await a.tuer();
      await a.demarrer();
      expect(await a.file.nombreEnAttente(), 17, reason: 'rien ne se perd à l’arrêt brutal');

      // 4. Pendant ce temps, sur le web.
      serveur.renommerDepuisLeWeb(enLigne[2], 'Renommée depuis le web');
      serveur.supprimerDepuisLeWeb(enLigne[1]);

      // 5. CHAOS : pannes serveur, réponses perdues, réseau qui bascule,
      //    application tuée entre deux passes.
      serveur
        ..pCoupureAvant = 0.12
        ..p503 = 0.10
        ..p429 = 0.05
        ..pPerteReponse = 0.25;
      var passes = 0;
      while (passes < 500 && await a.file.nombreEnAttente() > 0) {
        final r = alea.nextDouble();
        a.reseau.basculer(r < 0.2 ? EtatReseau.horsLigne : EtatReseau.enLigne);
        if (r > 0.93) {
          await a.tuer();
          await a.demarrer();
        }
        await a.sync.synchroniser();
        passes++;
      }

      // 6. Retour au calme : réseau stable, serveur sain. Une passe pour
      //    finir, une passe pour tirer les changements.
      serveur.calmer();
      a.reseau.basculer(EtatReseau.enLigne);
      await a.sync.synchroniser();
      await a.sync.synchroniser();

      // ── 7. COMPARAISON LOCAL / SERVEUR ──────────────────────────────────
      expect(serveur.reponsesPerdues, greaterThan(0), reason: 'le scénario doit avoir perdu des réponses');
      expect(await a.file.nombreEnAttente(), 0, reason: 'la file doit être vidée');

      final echecs = (await a.file.toutesLesTaches()).map(_libelle).toList();
      expect(echecs, ['photo:${enLigne[1]}'], reason: 'seule la photo d’une réserve supprimée par le web échoue');

      expect(serveur.lignes.length, 8, reason: 'AUCUN doublon : chaque identifiant n’a été créé qu’une fois');
      final distant = serveur.vivantes;
      expect(distant, hasLength(7));

      final local = await a.etatLocal();
      expect(local.keys.toSet(), distant, reason: 'mêmes réserves des deux côtés ; la supprimée a disparu du local');

      for (final id in distant) {
        final l = serveur.lignes[id]!;
        final r = local[id]!;
        expect(r.statut.raw, l.statut, reason: 'statut de $id');
        expect(r.titre, l.titre, reason: 'titre de $id');
        expect(r.numero, l.numero, reason: 'numéro définitif de $id');
        expect(await a.cache.estEnAttente(id), isFalse, reason: '$id doit être confirmée');
      }
      statutsAttendus.forEach((id, s) => expect(serveur.lignes[id]!.statut, s.raw, reason: 'statut voulu pour $id'));
      expect(local[enLigne[2]]!.titre, 'Renommée depuis le web', reason: 'la modification web est descendue');

      photosAttendues.forEach((id, photos) {
        expect(serveur.lignes[id]!.photos, unorderedEquals(photos), reason: 'photos de $id : toutes, une seule fois');
      });

      await a.tuer();
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('multi-appareils : deux téléphones hors ligne sur les mêmes réserves CONVERGENT', () async {
    final serveur = _ServeurSimule(Random(99));
    final a = _Appareil('A', serveur);
    final b = _Appareil('B', serveur);
    await a.preparer();
    await b.preparer();

    // Situation de départ, commune : trois réserves créées en ligne par A.
    await a.demarrer();
    final r0 = await a.creer('Commune');
    final conflit = await a.creer('Disputée');
    final web = await a.creer('Supprimée par le web');
    await a.tuer();

    // B récupère l'état du serveur (tirage incrémental).
    await b.demarrer();
    await b.sync.synchroniser();
    expect((await b.etatLocal()).keys.toSet(), {r0, conflit, web});

    // B, hors ligne : démarre la réserve disputée, en crée une.
    b.reseau.basculer(EtatReseau.horsLigne);
    await b.statut(conflit, ReserveStatut.enCours);
    final rb = await b.creer('Créée par B');
    await b.tuer();

    // A, hors ligne : déclare la réserve disputée corrigée, en crée une.
    await a.demarrer();
    a.reseau.basculer(EtatReseau.horsLigne);
    await a.statut(conflit, ReserveStatut.affectee);
    await a.statut(conflit, ReserveStatut.corrigee);
    await a.statut(r0, ReserveStatut.affectee);
    final ra = await a.creer('Créée par A');
    await a.tuer();

    // Sur le web : une suppression, un renommage.
    serveur.supprimerDepuisLeWeb(web);
    serveur.renommerDepuisLeWeb(r0, 'Commune (renommée)');

    // A retrouve le réseau le premier, sur un réseau médiocre.
    await a.demarrer();
    a.reseau.basculer(EtatReseau.enLigne);
    serveur
      ..pPerteReponse = 0.3
      ..p503 = 0.1;
    for (var i = 0; i < 200 && await a.file.nombreEnAttente() > 0; i++) {
      await a.sync.synchroniser();
    }
    serveur.calmer();
    await a.sync.synchroniser();
    expect(await a.file.nombreEnAttente(), 0);
    await a.tuer();

    // Puis B. Son « en cours » arrive sur une réserve déjà CORRIGÉE : la
    // matrice le refuse — c'est la règle métier qui tranche, pas l'horloge.
    await b.demarrer();
    b.reseau.basculer(EtatReseau.enLigne);
    serveur.pPerteReponse = 0.3;
    for (var i = 0; i < 200 && await b.file.nombreEnAttente() > 0; i++) {
      await b.sync.synchroniser();
    }
    serveur.calmer();
    await b.sync.synchroniser();
    final echecsB = await b.file.toutesLesTaches();
    expect(echecsB.map(_libelle), ['statut:$conflit'], reason: 'le refus reste VISIBLE sur B, avec son motif');
    expect(echecsB.single.derniereErreur, contains('Transition impossible'));
    final localB = await b.etatLocal();
    await b.tuer();

    // A tire ce que B a apporté.
    await a.demarrer();
    await a.sync.synchroniser();
    final localA = await a.etatLocal();
    await a.tuer();

    // ── CONVERGENCE ────────────────────────────────────────────────────────
    final distant = serveur.vivantes;
    expect(distant, {r0, conflit, ra, rb});
    for (final local in [localA, localB]) {
      expect(local.keys.toSet(), distant, reason: 'même ensemble de réserves que le serveur');
      for (final id in distant) {
        final l = serveur.lignes[id]!;
        expect(local[id]!.statut.raw, l.statut, reason: 'statut de $id');
        expect(local[id]!.titre, l.titre, reason: 'titre de $id');
        expect(local[id]!.numero, l.numero, reason: 'numéro de $id');
      }
    }
    expect(serveur.lignes[conflit]!.statut, 'corrigee', reason: 'la transition refusée n’a rien écrit');
    expect(serveur.lignes[r0]!.titre, 'Commune (renommée)');
    expect(serveur.lignes.length, 5, reason: 'aucun doublon malgré les réponses perdues');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
