import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/offline/cache_reserves.dart';
import '../../../../core/offline/classification_erreur.dart';
import '../../../../core/offline/detecteur_connexion.dart';
import '../../../../core/offline/file_attente.dart';
import '../../../../core/offline/reconciliation.dart';
import '../../../../core/offline/stockage_medias.dart';
import '../../domain/entities/chantier_structure.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/entities/reserve_evolution.dart';
import '../../domain/entities/reserve_collaboration.dart';
import '../../domain/repositories/reserve_repository.dart';
import '../datasources/reserve_remote_datasource.dart';

/// Implémentation OFFLINE-AWARE de [ReserveRepository].
///
/// ## Lecture — le cache local comme filet, pas comme source première
///
/// Chaque lecture tente le réseau en premier (la donnée la plus fraîche
/// possible reste la priorité en usage normal). Sur SUCCÈS, la réponse est
/// RÉCONCILIÉE avec le travail local encore en file (voir
/// `core/offline/reconciliation.dart`) avant d'être écrite dans le cache et
/// affichée. Sur ÉCHEC RÉSEAU (et uniquement dans ce cas — une erreur 403 ne
/// doit surtout pas faire retomber sur une vieille donnée qui masquerait le
/// vrai refus), on sert le cache local, paginé et filtré comme le serveur
/// l'aurait fait.
///
/// ## Écriture — file d'attente automatique
///
/// [DetecteurConnexion.estEnLigne] est vérifié EN PREMIER, avant toute
/// tentative réseau : au sous-sol, ça évite d'attendre l'expiration d'une
/// requête avant de conclure qu'il faut mettre en file d'attente — la bascule
/// est immédiate. Si l'appareil se croit en ligne mais que l'envoi échoue
/// quand même pour une raison réseau, on bascule alors en file d'attente au
/// lieu de faire remonter une erreur : l'utilisateur ne doit jamais avoir à
/// deviner s'il doit « réessayer ».
///
/// ## Ordre (deuxième audit, A2-01)
///
/// Dès qu'une réserve a une action en file, TOUTE nouvelle action sur elle
/// passe par la file, même en ligne. Un appel direct doublait sinon l'action
/// plus ancienne : le vieux statut repartait APRÈS le nouveau, ou la photo
/// arrivait avant la réserve.
class ReserveRepositoryImpl implements ReserveRepository {
  final ReserveRemoteDataSource remoteDataSource;
  final DetecteurConnexion _detecteur;
  final FileAttente _fileAttente;
  final CacheReserves _cache;
  final StockageMedias _medias;
  final _uuid = const Uuid();

  // Paramètres nommés sans préfixe souligné pour un site d'appel lisible côté
  // DI — un initializing formal (`this._detecteur`, etc.) imposerait ce
  // préfixe jusque dans l'API publique du constructeur.
  // ignore_for_file: prefer_initializing_formals
  ReserveRepositoryImpl(
    this.remoteDataSource, {
    required DetecteurConnexion detecteur,
    required FileAttente fileAttente,
    required CacheReserves cache,
    required StockageMedias medias,
  })  : _detecteur = detecteur,
        _fileAttente = fileAttente,
        _cache = cache,
        _medias = medias;

  /// `true` si une action sur cette réserve attend encore dans la file : la
  /// nouvelle action doit alors passer derrière elle.
  Future<bool> _aDuTravailEnFile(String reserveId) => _fileAttente.aDesActionsEnAttentePour('reserve:$reserveId');

  // ─────────────────────────────── Lectures ────────────────────────────────

  @override
  Future<Either<Failure, ReservePage>> getReserves({
    required String chantierId,
    int page = 1,
    int limit = 20,
    String? search,
    ReserveStatut? statut,
  }) async {
    try {
      final result = await remoteDataSource.getReserves(
        chantierId: chantierId, page: page, limit: limit, search: search, statut: statut,
      );
      await _cache.enregistrerTous(result.items);
      return Right(await _avecTravailLocal(result, chantierId: chantierId, numeroPage: page, statut: statut, search: search));
    } catch (e) {
      final repli = await _replisiSansReseau(e, () => _cache.listerParChantier(chantierId));
      if (repli != null) return Right(_paginer(repli, page: page, limit: limit, statut: statut, search: search));
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, ReservePage>> getToutesReserves({
    int page = 1,
    int limit = 20,
    String? search,
    ReserveStatut? statut,
  }) async {
    try {
      final result = await remoteDataSource.getToutesReserves(page: page, limit: limit, search: search, statut: statut);
      await _cache.enregistrerTous(result.items);
      return Right(await _avecTravailLocal(result, numeroPage: page, statut: statut, search: search));
    } catch (e) {
      final repli = await _replisiSansReseau(e, () => _cache.listerTout());
      if (repli != null) return Right(_paginer(repli, page: page, limit: limit, statut: statut, search: search));
      return Left(exceptionToFailure(e));
    }
  }

  /// Superpose le travail local pas encore confirmé à une page venue du
  /// serveur (deuxième audit, A2-04).
  ///
  /// Sans elle, dès qu'on était en ligne, une réserve créée hors ligne et pas
  /// encore envoyée DISPARAISSAIT de la liste (le serveur ne la connaît pas),
  /// et un statut changé hors ligne y apparaissait sous son ancienne valeur.
  /// L'utilisateur croyait son travail perdu.
  ///
  ///  - une réserve de la page qui a un changement en file est remplacée par
  ///    sa vue réconciliée (déjà écrite par `enregistrerTous`) ;
  ///  - une réserve dont la suppression locale n'est pas partie est masquée ;
  ///  - les réserves créées localement et inconnues du serveur sont ajoutées
  ///    en tête de la PREMIÈRE page seulement (sinon elles se répéteraient à
  ///    chaque page).
  Future<ReservePage> _avecTravailLocal(
    ReservePage page, {
    String? chantierId,
    required int numeroPage,
    ReserveStatut? statut,
    String? search,
  }) async {
    final enAttente = await _cache.listerEnAttente(chantierId: chantierId);
    final enSuppression = await _cache.idsEnSuppression();
    if (enAttente.isEmpty && enSuppression.isEmpty) return page;

    final parId = {for (final r in enAttente) r.id: r};
    final items = <Reserve>[
      for (final r in page.items)
        if (!enSuppression.contains(r.id)) parId[r.id] ?? r,
    ].where((r) => _correspond(r, statut, search)).toList();

    var ajoutees = 0;
    if (numeroPage == 1) {
      final presentes = page.items.map((r) => r.id).toSet();
      final nouvelles = enAttente
          .where((r) => r.numero == Reserve.numeroEnAttente && !presentes.contains(r.id) && _correspond(r, statut, search))
          .toList();
      items.insertAll(0, nouvelles);
      ajoutees = nouvelles.length;
    }
    return ReservePage(items: items, total: page.total + ajoutees);
  }

  /// Filtre et recherche appliqués LOCALEMENT, avec la même sémantique que le
  /// serveur : statut exact ; recherche sans casse dans titre, description et
  /// numéro.
  static bool _correspond(Reserve r, ReserveStatut? statut, String? search) {
    if (statut != null && r.statut != statut) return false;
    final motif = search?.trim().toLowerCase() ?? '';
    if (motif.isEmpty) return true;
    return r.titre.toLowerCase().contains(motif) ||
        (r.description?.toLowerCase().contains(motif) ?? false) ||
        r.numero.toLowerCase().contains(motif);
  }

  /// Repli hors ligne PAGINÉ (deuxième audit, A2-15).
  ///
  /// La version précédente renvoyait tout le cache à CHAQUE page : la liste,
  /// qui ajoute la page suivante à la précédente, affichait les mêmes
  /// réserves deux, trois fois — et sur 10 000 réserves en cache, chaque
  /// défilement en recopiait 10 000.
  static ReservePage _paginer(
    List<Reserve> tout, {
    required int page,
    required int limit,
    ReserveStatut? statut,
    String? search,
  }) {
    final filtrees = tout.where((r) => _correspond(r, statut, search)).toList();
    final debut = math.max(0, (page - 1) * limit);
    final items = debut >= filtrees.length ? <Reserve>[] : filtrees.sublist(debut, math.min(debut + limit, filtrees.length));
    return ReservePage(items: items, total: filtrees.length);
  }

  @override
  Future<Either<Failure, ReserveStatutsCount>> getStatutsCount(String chantierId) async {
    try {
      final result = await remoteDataSource.getStatutsCount(chantierId);
      return Right(result);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, ReserveStatutsCount>> getStatutsCountGlobal() async {
    try {
      return Right(await remoteDataSource.getStatutsCountGlobal());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Reserve>> getReserveDetail(String id) async {
    final locale = await _cache.lire(id);
    final enAttente = locale != null && await _cache.estEnAttente(id);
    try {
      final serveur = await remoteDataSource.getReserveDetail(id);
      // Réconciliation (A2-02) : la version serveur, plus les changements
      // locaux encore en file. L'ancienne version écrasait la ligne locale et
      // effaçait son marqueur « en attente ».
      final vue = await _cache.reconcilier(serveur);
      if (vue == null) return Right(serveur);
      // Galerie et historique appartiennent au serveur : aucune action locale
      // ne les modifie, ils sont donc toujours repris de sa réponse.
      return Right(vue.copierAvec(medias: serveur.medias, historiques: serveur.historiques, photoApercu: serveur.photoApercu));
    } catch (e) {
      // Travail local pas encore confirmé : c'est lui la vérité de l'écran —
      // y compris quand le serveur ne connaît pas encore la réserve (404 d'une
      // création qui n'est pas encore partie).
      if (enAttente) return Right(locale);
      final repli = await _replisiSansReseau(e, () => _cache.lire(id));
      if (repli != null) return Right(repli);
      return Left(exceptionToFailure(e));
    }
  }

  // ─────────────────────────────── Écritures ───────────────────────────────

  @override
  Future<Either<Failure, Reserve>> modifierReserve({
    required String id,
    String? titre,
    String? description,
    ReserveSeverite? severite,
    ReserveCategorie? categorie,
    DateTime? dateLimite,
  }) async {
    // Seules les clés PRÉSENTES sont envoyées : `modifierReserveSchema`
    // n'exige aucun champ, et omettre ce qui n'a pas bougé évite d'écraser
    // une valeur modifiée entre-temps depuis l'admin web.
    final champs = <String, dynamic>{
      'titre': ?titre,
      'description': ?description,
      'severite': ?severite?.raw,
      'categorie': ?categorie?.raw,
      if (dateLimite != null) 'date_limite': dateLimite.toIso8601String().split('T').first,
    };
    // Valeurs de DÉPART (deuxième audit, A2-13) : celles que l'utilisateur
    // avait sous les yeux. Le serveur refuse si quelqu'un a modifié le même
    // champ entre-temps, au lieu de l'écraser en silence.
    final actuelle = await _cache.lire(id);
    final valeursInitiales = actuelle == null ? null : valeursDe(actuelle, champs.keys);

    if (!_detecteur.estEnLigne || await _aDuTravailEnFile(id)) {
      return _modifierHorsLigne(id: id, actuelle: actuelle, champs: champs, valeursInitiales: valeursInitiales);
    }
    try {
      final reserve = await remoteDataSource.modifierReserve(id, {
        ...champs,
        'valeursInitiales': ?valeursInitiales,
      });
      return Right(await _cache.reconcilier(reserve) ?? reserve);
    } on NetworkException catch (_) {
      return _modifierHorsLigne(id: id, actuelle: actuelle, champs: champs, valeursInitiales: valeursInitiales);
    } on DioException catch (e) {
      if (estCoupureReseau(e)) {
        return _modifierHorsLigne(id: id, actuelle: actuelle, champs: champs, valeursInitiales: valeursInitiales);
      }
      return Left(exceptionToFailure(e));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Modification HORS LIGNE (deuxième audit, A2-12) : écrite tout de suite
  /// en local, mise en file avec les valeurs de départ, dans UNE transaction.
  Future<Either<Failure, Reserve>> _modifierHorsLigne({
    required String id,
    required Reserve? actuelle,
    required Map<String, dynamic> champs,
    required Map<String, dynamic>? valeursInitiales,
  }) async {
    if (actuelle == null) {
      return const Left(NetworkFailure(
        errorMessage: "Cette réserve n'est pas disponible hors ligne — reconnectez-vous pour la modifier.",
      ));
    }
    final maj = appliquerChamps(actuelle, champs);
    return _ouEchec(() async {
      await _fileAttente.deposer(
        type: TypeAction.modifierReserve,
        charge: {'reserveId': id, 'champs': champs, 'valeursInitiales': ?valeursInitiales},
        avecEcriture: (txn) => _cache.enregistrer(maj, enAttente: true, executeur: txn),
      );
      return maj;
    });
  }

  @override
  Future<Either<Failure, void>> supprimerReserve(String id) async {
    if (!_detecteur.estEnLigne || await _aDuTravailEnFile(id)) return _supprimerHorsLigne(id);
    try {
      await remoteDataSource.supprimerReserve(id);
      // Le miroir local doit suivre : conservée, la ligne réapparaîtrait au
      // premier repli hors ligne, et rien dans l'application ne permettrait
      // plus de s'en débarrasser.
      await _cache.supprimer(id);
      return const Right(null);
    } on NetworkException catch (_) {
      return _supprimerHorsLigne(id);
    } on DioException catch (e) {
      if (estCoupureReseau(e)) return _supprimerHorsLigne(id);
      return Left(exceptionToFailure(e));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Suppression HORS LIGNE (deuxième audit, A2-12) : la réserve disparaît
  /// tout de suite de l'écran ; la suppression part en file avec un
  /// instantané, qui permet de la restaurer si le serveur refuse.
  Future<Either<Failure, void>> _supprimerHorsLigne(String id) async {
    final actuelle = await _cache.lire(id);
    try {
      await _fileAttente.deposer(
        type: TypeAction.supprimerReserve,
        charge: {'reserveId': id, 'instantane': ?actuelle?.toJson()},
        avecEcriture: (txn) => _cache.supprimer(id, executeur: txn),
      );
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<CommentaireReserve>>> getCommentaires(String reserveId) async {
    try {
      return Right(await remoteDataSource.getCommentaires(reserveId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<ReserveHistoriqueEntry>>> getHistorique(String reserveId) async {
    try {
      return Right(await remoteDataSource.getHistorique(reserveId));
    } catch (e) {
      // Sans réseau, la fiche en cache porte les lignes d'historique reçues
      // avec elle (`historiques`, ordre chronologique) : on les sert du plus
      // récent au plus ancien, comme le ferait le serveur.
      final repli = await _replisiSansReseau(e, () => _cache.lire(reserveId));
      if (repli != null) return Right(repli.historiques.reversed.toList());
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, CommentaireReserve>> ajouterCommentaire({
    required String reserveId,
    required String message,
  }) async {
    try {
      return Right(await remoteDataSource.ajouterCommentaire(reserveId, message));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<AffectationReserve>>> getAffectations(String reserveId) async {
    try {
      return Right(await remoteDataSource.getAffectations(reserveId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, AffectationReserve>> affecter({
    required String reserveId,
    String? utilisateurId,
    String? entrepriseId,
    String? partenaireId,
  }) async {
    try {
      return Right(await remoteDataSource.affecter(reserveId, {
        if (utilisateurId != null) 'utilisateurId': utilisateurId,
        if (entrepriseId != null) 'entrepriseId': entrepriseId,
        if (partenaireId != null) 'partenaireId': partenaireId,
      }));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> retirerAffectation({
    required String reserveId,
    required String affectationId,
  }) async {
    try {
      await remoteDataSource.retirerAffectation(reserveId, affectationId);
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Reserve>> dupliquerReserve(String id) async {
    try {
      final reserve = await remoteDataSource.dupliquerReserve(id);
      await _cache.reconcilier(reserve);
      return Right(reserve);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, QrReserve>> getQr(String id) async {
    try {
      return Right(await remoteDataSource.getQr(id));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Reserve>> creerReserve({
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
  }) async {
    // Identifiant généré ICI, AVANT toute tentative réseau, et partagé par
    // les deux chemins (en ligne et repli hors ligne). C'est ce qui rend un
    // rejeu inoffensif :
    //
    //   1. l'app envoie la création avec cet id ;
    //   2. le serveur la crée AVEC SUCCÈS ;
    //   3. la réponse se perd (réseau de chantier, `receiveTimeout` à 30 s) ;
    //   4. l'app croit avoir échoué et met l'action en file ;
    //   5. au retour du réseau, la file rejoue... le MÊME id.
    //
    // `ReserveService.creerReserve` (backend) reconnaît alors l'id déjà
    // présent et renvoie la réserve existante au lieu d'en créer une seconde.
    final id = _uuid.v4();

    Future<Either<Failure, Reserve>> horsLigne() => _ouEchec(() => _creerHorsLigne(
          id: id,
          chantierId: chantierId, titre: titre, description: description, priorite: priorite,
          categorie: categorie, batimentId: batimentId, etageId: etageId, zoneId: zoneId, lotId: lotId,
          dateLimite: dateLimite,
          planId: planId, positionX: positionX, positionY: positionY,
          positionPage: positionPage,
          partenaireId: partenaireId, severite: severite, corpsEtatId: corpsEtatId, phaseId: phaseId,
        ));

    if (!_detecteur.estEnLigne) return horsLigne();
    try {
      final result = await remoteDataSource.creerReserve(
        id: id,
        chantierId: chantierId, titre: titre, description: description, priorite: priorite,
        categorie: categorie, batimentId: batimentId, etageId: etageId, zoneId: zoneId, lotId: lotId,
        dateLimite: dateLimite,
        planId: planId, positionX: positionX, positionY: positionY,
        positionPage: positionPage,
        partenaireId: partenaireId, severite: severite, corpsEtatId: corpsEtatId, phaseId: phaseId,
      );
      return Right(await _cache.reconcilier(result) ?? result);
    } on NetworkException catch (_) {
      // Cas RÉEL : voir la note dans `_replisiSansReseau`.
      return horsLigne();
    } on DioException catch (e) {
      if (estCoupureReseau(e)) return horsLigne();
      return Left(exceptionToFailure(e));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Exécute une écriture HORS LIGNE et en rend l'issue, sans jamais lever.
  ///
  /// L'ancienne version laissait l'exception d'un dépôt raté (disque plein,
  /// base verrouillée) remonter NUE jusqu'au cubit, qui ne l'attendait pas :
  /// l'écran restait sur son indicateur, sans erreur ni résultat. Un échec
  /// doit être DIT — c'est un `Left`, jamais un faux succès.
  Future<Either<Failure, Reserve>> _ouEchec(Future<Reserve> Function() ecriture) async {
    try {
      return Right(await ecriture());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Construit une réserve LOCALE (id généré côté client — voir
  /// `backend/.../reserve.validation.js`), la place en cache marquée
  /// « en attente », et dépose l'action correspondante dans la file. L'écran
  /// appelant reçoit cette réserve exactement comme si le serveur avait
  /// répondu : il peut naviguer sur son détail, lui attacher une photo, tout
  /// de suite — la file respecte l'ordre de création, la photo ne partira
  /// jamais avant la réserve.
  ///
  /// L'écriture en cache et le dépôt sont ATOMIQUES (une seule transaction,
  /// voir `FileAttente.deposer`) : une réserve « en attente » sans action pour
  /// l'envoyer ne peut plus exister.
  Future<Reserve> _creerHorsLigne({
    /// Fourni par [creerReserve], JAMAIS généré ici : c'est le partage de cet
    /// id entre la tentative en ligne et le repli qui garantit l'idempotence
    /// du rejeu. Voir le commentaire détaillé dans [creerReserve].
    required String id,
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
  }) async {
    final reserve = Reserve(
      id: id,
      // Numéro provisoire — affiché en attendant que le serveur attribue le
      // vrai numéro de séquence du chantier (ex. « R-042 »), qu'il est seul à
      // pouvoir calculer sans risque de collision entre appareils. Traduit à
      // l'affichage par `Reserve.numeroAffiche` — voir sa doc.
      numero: Reserve.numeroEnAttente,
      chantierId: chantierId,
      titre: titre,
      description: description,
      severite: severite ?? priorite,
      priorite: priorite,
      categorie: categorie,
      statut: ReserveStatut.creee,
      dateLimite: dateLimite,
      createdAt: DateTime.now(),
      batiment: batimentId != null ? ReserveLocalisationRef(id: batimentId, nom: '') : null,
      etage: etageId != null ? ReserveLocalisationRef(id: etageId, nom: '') : null,
      zone: zoneId != null ? ReserveLocalisationRef(id: zoneId, nom: '') : null,
      lot: lotId != null ? ReserveLocalisationRef(id: lotId, nom: '') : null,
    );

    await _fileAttente.deposer(
      type: TypeAction.creerReserve,
      // Écriture locale et dépôt dans la MÊME transaction : tout ou rien.
      avecEcriture: (txn) => _cache.enregistrer(reserve, enAttente: true, executeur: txn),
      charge: {
        'id': id,
        'chantierId': chantierId,
        'titre': titre,
        'description': description,
        'priorite': priorite.raw,
        'categorie': categorie.raw,
        'batimentId': batimentId,
        'etageId': etageId,
        'zoneId': zoneId,
        'lotId': lotId,
        'dateLimite': dateLimite?.toIso8601String(),
        // Sans ces quatre clés, une réserve posée sur un plan SANS RÉSEAU
        // partait au retour de connexion en ayant perdu son point, son plan et
        // son entreprise — c'est-à-dire tout ce qui la rendait localisable.
        'planId': planId,
        'positionX': positionX,
        'positionY': positionY,
        // La PAGE, sans quoi une réserve posée hors ligne sur la page 7 d'un
        // PDF repartait sur la page 1 à la synchronisation — au bon endroit,
        // sur le mauvais plan.
        'positionPage': positionPage,
        'partenaireId': partenaireId,
        'severite': severite?.raw,
        // Sans cette clé, une réserve créée SANS RÉSEAU repartait au retour
        // de connexion en ayant perdu son métier.
        'corpsEtatId': corpsEtatId,
        // Sans cette clé, une réserve créée SANS RÉSEAU repartait au retour
        // de connexion sans phase — et le serveur la refuserait désormais.
        'phaseId': phaseId,
      },
    );
    return reserve;
  }

  @override
  Future<Either<Failure, Reserve>> changerStatut({
    required String reserveId,
    required ReserveStatut statut,
    String? motif,
  }) async {
    if (!_detecteur.estEnLigne || await _aDuTravailEnFile(reserveId)) {
      return _changerStatutHorsLigne(reserveId: reserveId, statut: statut, motif: motif);
    }
    try {
      final result = await remoteDataSource.changerStatut(reserveId: reserveId, statut: statut, motif: motif);
      return Right(await _cache.reconcilier(result) ?? result);
    } on NetworkException catch (_) {
      return _changerStatutHorsLigne(reserveId: reserveId, statut: statut, motif: motif);
    } on DioException catch (e) {
      if (estCoupureReseau(e)) {
        return _changerStatutHorsLigne(reserveId: reserveId, statut: statut, motif: motif);
      }
      return Left(exceptionToFailure(e));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Met à jour la réserve EN CACHE de façon optimiste : sans elle (créée en
  /// ligne puis jamais rouverte hors ligne, par exemple), impossible d'en
  /// afficher un nouveau statut avant confirmation serveur — l'action part
  /// quand même, seul le retour visuel immédiat manquerait.
  Future<Either<Failure, Reserve>> _changerStatutHorsLigne({
    required String reserveId,
    required ReserveStatut statut,
    String? motif,
  }) async {
    final actuelle = await _cache.lire(reserveId);
    if (actuelle == null) {
      return const Left(NetworkFailure(
        errorMessage: "Cette réserve n'est pas disponible hors ligne — reconnectez-vous pour la modifier.",
      ));
    }
    final maj = actuelle.copierAvecStatut(statut);
    return _ouEchec(() async {
      // Statut provisoire et action dans la MÊME transaction : un statut
      // affiché « en attente » a toujours une action pour le porter.
      await _fileAttente.deposer(
        type: TypeAction.changerStatutReserve,
        charge: {'reserveId': reserveId, 'statut': statut.raw, 'motif': motif},
        avecEcriture: (txn) => _cache.enregistrer(maj, enAttente: true, executeur: txn),
      );
      return maj;
    });
  }

  @override
  Future<Either<Failure, List<ReserveMedia>>> getMedias(String reserveId) async {
    try {
      final result = await remoteDataSource.getMedias(reserveId);
      return Right(result);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, ReserveMedia>> ajouterMedia({
    required String reserveId,
    required String cheminFichier,
    String type = 'photo',
  }) async {
    if (!_detecteur.estEnLigne || await _aDuTravailEnFile(reserveId)) {
      return _ajouterMediaHorsLigne(reserveId: reserveId, cheminFichier: cheminFichier, type: type);
    }
    try {
      final result = await remoteDataSource.ajouterMedia(reserveId: reserveId, cheminFichier: cheminFichier, type: type);
      return Right(result);
    } on NetworkException catch (_) {
      return _ajouterMediaHorsLigne(reserveId: reserveId, cheminFichier: cheminFichier, type: type);
    } on DioException catch (e) {
      if (estCoupureReseau(e)) {
        return _ajouterMediaHorsLigne(reserveId: reserveId, cheminFichier: cheminFichier, type: type);
      }
      return Left(exceptionToFailure(e));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Copie le fichier hors du cache temporaire de l'appareil photo AVANT de
  /// déposer l'action — voir `StockageMedias` pour la raison : sans cette
  /// copie, l'OS pourrait libérer l'espace et perdre le cliché avant l'envoi.
  ///
  /// Retourne un média PROVISOIRE (id local, url pointant sur le fichier
  /// local) : l'écran peut afficher la photo immédiatement, elle sera
  /// remplacée par la version serveur au prochain chargement du détail.
  Future<Either<Failure, ReserveMedia>> _ajouterMediaHorsLigne({
    required String reserveId,
    required String cheminFichier,
    required String type,
  }) async {
    final idAction = _uuid.v4();
    final String cheminDurable;
    try {
      cheminDurable = await _medias.copier(cheminFichier, idAction);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }

    try {
      await _fileAttente.deposer(
        type: TypeAction.ajouterPhotoReserve,
        charge: {'reserveId': reserveId, 'type': type},
        cheminFichier: cheminDurable,
        // Le nom de la copie EST l'identifiant de l'action : une photo sur le
        // disque se relie toujours à sa ligne de file.
        id: idAction,
      );
    } catch (e) {
      // Sans action pour l'envoyer, la copie deviendrait un fichier ORPHELIN :
      // une photo géolocalisée qui ne serait jamais ni envoyée ni effacée.
      await _medias.supprimer(cheminDurable);
      return Left(exceptionToFailure(e));
    }

    return Right(ReserveMedia(
      id: idAction,
      type: type,
      url: cheminDurable,
      prisLe: DateTime.now(),
    ));
  }

  @override
  Future<Either<Failure, ChantierStructure>> getStructure(String chantierId) async {
    try {
      final result = await remoteDataSource.getStructure(chantierId);
      return Right(result);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, ReserveEvolution>> getEvolution(String chantierId) async {
    try {
      final result = await remoteDataSource.getEvolution(chantierId);
      return Right(result);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Sert le cache local UNIQUEMENT si [erreur] est bien une coupure réseau —
  /// jamais sur un refus applicatif (403, 404…), qui doit remonter tel quel :
  /// masquer un « accès refusé » derrière une vieille donnée en cache serait
  /// trompeur, pas utile.
  ///
  /// `NetworkException` est le cas RÉEL : `ReserveRemoteDataSourceImpl`
  /// convertit déjà la `DioException` avant qu'elle n'atteigne ce
  /// repository (voir `mapDioException`). Le test `erreur is DioException`
  /// reste en filet, au cas où un appelant lèverait l'exception brute.
  Future<T?> _replisiSansReseau<T>(Object erreur, Future<T> Function() lireCache) async {
    final estReseau = erreur is NetworkException || (erreur is DioException && estCoupureReseau(erreur));
    if (!estReseau) return null;
    return lireCache();
  }
}
