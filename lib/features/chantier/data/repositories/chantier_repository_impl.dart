import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/offline/cache_chantiers.dart';
import '../../../../core/offline/classification_erreur.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../../domain/entities/chantier.dart';
import '../../domain/repositories/chantier_repository.dart';
import '../datasources/chantier_remote_datasource.dart';

/// Lecture seule, mais OFFLINE-AWARE : aucun chantier n'est créé depuis le
/// mobile (c'est un geste de l'espace d'administration), donc pas de file
/// d'attente ici — uniquement un cache qui prend le relais du réseau. Voir
/// `ReserveRepositoryImpl` pour le pendant en écriture.
class ChantierRepositoryImpl implements ChantierRepository {
  final ChantierRemoteDataSource remoteDataSource;
  final CacheChantiers _cache;

  // `this._cache` imposerait le préfixe souligné au site d'appel (`cache:`
  // devrait s'écrire `_cache:`) — voir la même remarque dans
  // ReserveRepositoryImpl.
  // ignore: prefer_initializing_formals
  ChantierRepositoryImpl(this.remoteDataSource, {required CacheChantiers cache}) : _cache = cache;

  @override
  Future<Either<Failure, ChantierPage>> getChantiers({
    int page = 1,
    int limit = 20,
    String? search,
    ChantierStatut? statut,
    VueDemandes? demandes,
  }) async {
    try {
      final result = await remoteDataSource.getChantiers(
        page: page, limit: limit, search: search, statut: statut, demandes: demandes,
      );
      // Les DEMANDES ne rejoignent pas le cache des chantiers. Sans ce tri,
      // la liste hors ligne les afficherait comme des chantiers en activité —
      // précisément ce que le filtrage serveur évite.
      final aRetenir = result.items.where((c) => !c.statut.estUneDemande).toList();
      if (aRetenir.isNotEmpty) await _cache.enregistrerTous(aRetenir);
      return Right(result);
    } catch (e) {
      // Aucun repli sur une vue de DEMANDES : le cache ne porte pas le
      // demandeur, il ne saurait pas distinguer les demandes du compte
      // connecté de celles des autres. Afficher celles d'un collègue comme
      // les siennes serait pire qu'un message d'erreur.
      if (demandes != null) return Left(exceptionToFailure(e));

      final repli = await _replisiSansReseau(e, () => _cache.listerTout());
      if (repli == null) return Left(exceptionToFailure(e));
      // Repli hors ligne : le cache contient TOUS les chantiers connus, sans
      // notion de page ni de filtre. On applique donc au moins le statut
      // demandé, sans quoi le filtre paraîtrait ignoré dès la perte du réseau.
      final filtres = statut == null ? repli : repli.where((c) => c.statut == statut).toList();
      return Right(ChantierPage(items: filtres, total: filtres.length));
    }
  }

  @override
  Future<Either<Failure, Chantier>> creerChantier({
    required String nom,
    String? code,
    String? adresse,
    String? description,
    double? latitude,
    double? longitude,
    DateTime? dateDebut,
    DateTime? dateFin,
    num? budget,
    String? responsableId,
  }) async {
    try {
      final chantier = await remoteDataSource.creerChantier(
        nom: nom,
        code: code,
        adresse: adresse,
        description: description,
        latitude: latitude,
        longitude: longitude,
        dateDebut: dateDebut,
        dateFin: dateFin,
        budget: budget,
        responsableId: responsableId,
      );
      // Une DEMANDE ne rejoint pas le cache des chantiers : hors ligne, elle
      // s'afficherait comme un chantier en activité.
      if (!chantier.statut.estUneDemande) await _cache.enregistrer(chantier);
      return Right(chantier);
    } catch (e) {
      // Aucun repli hors ligne : une création ne se devine pas depuis un
      // cache, et prétendre qu'elle a réussi serait mentir.
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, BatimentStructure>> creerBatiment(
    String chantierId, {
    required String nom,
    String? code,
  }) async {
    try {
      return Right(await remoteDataSource.creerBatiment(chantierId, nom: nom, code: code));
    } catch (e) {
      // Aucun repli hors ligne : une création ne se devine pas depuis un
      // cache, et prétendre qu'elle a réussi ferait perdre la saisie.
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, EtageStructure>> creerEtage(
    String chantierId,
    String batimentId, {
    required String nom,
    required TypeNiveau typeNiveau,
    String? codeNiveau,
    String? description,
    int? niveau,
  }) async {
    try {
      return Right(await remoteDataSource.creerEtage(
        chantierId,
        batimentId,
        nom: nom,
        typeNiveau: typeNiveau,
        codeNiveau: codeNiveau,
        description: description,
        niveau: niveau,
      ));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Chantier>> getChantierDetail(String id) async {
    try {
      final result = await remoteDataSource.getChantierDetail(id);
      await _cache.enregistrer(result);
      return Right(result);
    } catch (e) {
      final repli = await _replisiSansReseau(e, () => _cache.lire(id));
      if (repli != null) return Right(repli);
      return Left(exceptionToFailure(e));
    }
  }

  /// Même règle que `ReserveRepositoryImpl` : seule une coupure RÉSEAU fait
  /// retomber sur le cache, jamais un refus applicatif. `NetworkException`
  /// est le cas RÉEL (voir la note détaillée dans `ReserveRepositoryImpl`).
  Future<T?> _replisiSansReseau<T>(Object erreur, Future<T> Function() lireCache) async {
    final estReseau = erreur is NetworkException || (erreur is DioException && estCoupureReseau(erreur));
    if (!estReseau) return null;
    return lireCache();
  }
}
