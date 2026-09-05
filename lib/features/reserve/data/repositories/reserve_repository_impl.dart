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
/// écrite dans le cache local en tâche de fond — c'est ce qui la rendra
/// disponible la prochaine fois que le réseau manquera. Sur ÉCHEC RÉSEAU
/// (et uniquement dans ce cas — une erreur 403 ne doit surtout pas faire
/// retomber sur une vieille donnée qui masquerait le vrai refus), on sert le
/// cache local à la place de faire échouer l'écran.
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
/// Dans les deux cas, l'écriture locale est faite immédiatement (avant tout
/// aller-retour réseau) : l'écran affiche le résultat sans attendre.
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
      return Right(result);
    } catch (e) {
      final repli = await _replisiSansReseau(e, () => _cache.listerParChantier(chantierId));
      if (repli != null) return Right(ReservePage(items: repli, total: repli.length));
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
      return Right(result);
    } catch (e) {
      final repli = await _replisiSansReseau(e, () => _cache.listerTout());
      if (repli != null) return Right(ReservePage(items: repli, total: repli.length));
      return Left(exceptionToFailure(e));
    }
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
  Future<Either<Failure, Reserve>> modifierReserve({
    required String id,
    String? titre,
    String? description,
    ReserveSeverite? severite,
    ReserveCategorie? categorie,
    DateTime? dateLimite,
  }) async {
    try {
      // Seules les clés PRÉSENTES sont envoyées : `modifierReserveSchema`
      // n'exige aucun champ, et omettre ce qui n'a pas bougé évite d'écraser
      // une valeur modifiée entre-temps depuis l'admin web.
      final reserve = await remoteDataSource.modifierReserve(id, {
        if (titre != null) 'titre': titre,
        if (description != null) 'description': description,
        if (severite != null) 'severite': severite.raw,
        if (categorie != null) 'categorie': categorie.raw,
        if (dateLimite != null) 'date_limite': dateLimite.toIso8601String(),
      });
      await _cache.enregistrer(reserve);
      return Right(reserve);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> supprimerReserve(String id) async {
    try {
      await remoteDataSource.supprimerReserve(id);
      // Le miroir local doit suivre : conservée, la ligne réapparaîtrait au
      // premier repli hors ligne, et rien dans l'application ne permettrait
      // plus de s'en débarrasser.
      await _cache.supprimer(id);
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
  }) async {
    try {
      return Right(await remoteDataSource.affecter(reserveId, {
        if (utilisateurId != null) 'utilisateurId': utilisateurId,
        if (entrepriseId != null) 'entrepriseId': entrepriseId,
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
      await _cache.enregistrer(reserve);
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
  Future<Either<Failure, Reserve>> getReserveDetail(String id) async {
    try {
      final result = await remoteDataSource.getReserveDetail(id);
      await _cache.enregistrer(result);
      return Right(result);
    } catch (e) {
      final repli = await _replisiSansReseau(e, () => _cache.lire(id));
      if (repli != null) return Right(repli);
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
    // Générer l'id seulement au moment du repli — ce que faisait la version
    // précédente — produisait un id DIFFÉRENT de celui déjà enregistré côté
    // serveur, donc un doublon à chaque timeout sur une création réussie.
    final id = _uuid.v4();

    if (!_detecteur.estEnLigne) {
      return Right(await _creerHorsLigne(
        id: id,
        chantierId: chantierId, titre: titre, description: description, priorite: priorite,
        categorie: categorie, batimentId: batimentId, etageId: etageId, zoneId: zoneId, lotId: lotId,
        dateLimite: dateLimite,
        planId: planId, positionX: positionX, positionY: positionY,
        partenaireId: partenaireId, severite: severite, corpsEtatId: corpsEtatId, phaseId: phaseId,
      ));
    }
    try {
      final result = await remoteDataSource.creerReserve(
        id: id,
        chantierId: chantierId, titre: titre, description: description, priorite: priorite,
        categorie: categorie, batimentId: batimentId, etageId: etageId, zoneId: zoneId, lotId: lotId,
        dateLimite: dateLimite,
        planId: planId, positionX: positionX, positionY: positionY,
        partenaireId: partenaireId, severite: severite, corpsEtatId: corpsEtatId, phaseId: phaseId,
      );
      await _cache.enregistrer(result);
      return Right(result);
    } on NetworkException catch (_) {
      // Cas RÉEL : voir la note dans `_replisiSansReseau`.
      return Right(await _creerHorsLigne(
        id: id,
        chantierId: chantierId, titre: titre, description: description, priorite: priorite,
        categorie: categorie, batimentId: batimentId, etageId: etageId, zoneId: zoneId, lotId: lotId,
        dateLimite: dateLimite,
        planId: planId, positionX: positionX, positionY: positionY,
        partenaireId: partenaireId, severite: severite, corpsEtatId: corpsEtatId, phaseId: phaseId,
      ));
    } on DioException catch (e) {
      if (estCoupureReseau(e)) {
        return Right(await _creerHorsLigne(
          id: id,
          chantierId: chantierId, titre: titre, description: description, priorite: priorite,
          categorie: categorie, batimentId: batimentId, etageId: etageId, zoneId: zoneId, lotId: lotId,
          dateLimite: dateLimite,
          planId: planId, positionX: positionX, positionY: positionY,
          partenaireId: partenaireId, severite: severite, corpsEtatId: corpsEtatId, phaseId: phaseId,
        ));
      }
      return Left(exceptionToFailure(e));
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

    await _cache.enregistrer(reserve, enAttente: true);
    await _fileAttente.deposer(
      type: TypeAction.creerReserve,
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
    if (!_detecteur.estEnLigne) {
      return _changerStatutHorsLigne(reserveId: reserveId, statut: statut, motif: motif);
    }
    try {
      final result = await remoteDataSource.changerStatut(reserveId: reserveId, statut: statut, motif: motif);
      await _cache.enregistrer(result);
      return Right(result);
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
    await _cache.enregistrer(maj, enAttente: true);
    await _fileAttente.deposer(
      type: TypeAction.changerStatutReserve,
      charge: {'reserveId': reserveId, 'statut': statut.raw, 'motif': motif},
    );
    return Right(maj);
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
    if (!_detecteur.estEnLigne) {
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
    final cheminDurable = await _medias.copier(cheminFichier, idAction);

    await _fileAttente.deposer(
      type: TypeAction.ajouterPhotoReserve,
      charge: {'reserveId': reserveId, 'type': type},
      cheminFichier: cheminDurable,
    );

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
