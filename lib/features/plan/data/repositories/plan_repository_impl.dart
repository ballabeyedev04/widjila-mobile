import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/offline/cache_reserves.dart';
import '../../domain/entities/plan.dart';
import '../../domain/repositories/plan_repository.dart';
import '../datasources/plan_remote_datasource.dart';

class PlanRepositoryImpl implements PlanRepository {
  final PlanRemoteDataSource remoteDataSource;

  /// Réserves de la base locale — pour que celles posées SANS RÉSEAU
  /// apparaissent sur le plan tout de suite (guide hors connexion, §4 :
  /// « apparaît tout de suite sur le plan »). Facultatif : sans lui, le plan
  /// n'affiche que ce que le serveur connaît.
  final CacheReserves? reservesLocales;

  PlanRepositoryImpl(this.remoteDataSource, {this.reservesLocales});

  @override
  Future<Either<Failure, List<Plan>>> getTousPlans() async {
    try {
      return Right(await remoteDataSource.getTousPlans());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Plan>>> getPlansChantier(String chantierId) async {
    try {
      return Right(await remoteDataSource.getPlansChantier(chantierId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Plan>>> getPlansRacines(String chantierId) async {
    try {
      return Right(await remoteDataSource.getPlansRacines(chantierId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Plan>>> getSousPlans(String planId) async {
    try {
      return Right(await remoteDataSource.getSousPlans(planId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> supprimerPlan(String id) async {
    try {
      await remoteDataSource.supprimerPlan(id);
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Plan>> remplacerFichier(String id, {required String cheminFichier}) async {
    try {
      return Right(await remoteDataSource.remplacerFichier(id, cheminFichier: cheminFichier));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Plan>> getPlanDetail(String id) async {
    try {
      final plan = await remoteDataSource.getPlanDetail(id);
      return Right(await _avecReservesLocales(plan));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Ajoute au plan les réserves locales qui y sont posées et que sa liste
  /// ne contient pas : créées hors ligne et pas encore synchronisées, ou
  /// reçues depuis le détail mis en copie. Jamais bloquant : une base locale
  /// illisible laisse simplement le plan tel que le serveur l'a donné.
  Future<Plan> _avecReservesLocales(Plan plan) async {
    final cache = reservesLocales;
    if (cache == null) return plan;
    try {
      final connues = plan.reserves.map((r) => r.id).toSet();
      final locales = await cache.listerParChantier(plan.chantierId);
      final ajoutees = <PlanReserve>[];
      for (final r in locales) {
        final position = r.position;
        if (r.plan?.id != plan.id || position == null || connues.contains(r.id)) continue;
        ajoutees.add(PlanReserve(
          id: r.id,
          numero: r.numero,
          numeroPlan: r.numeroPlan,
          titre: r.titre,
          description: r.description,
          statut: r.statut,
          severite: r.severite,
          position: PlanPosition(x: position.x, y: position.y, page: position.page),
          createdAt: r.createdAt,
          dateLimite: r.dateLimite,
        ));
      }
      if (ajoutees.isEmpty) return plan;
      return plan.avecReserves([...plan.reserves, ...ajoutees]);
    } catch (_) {
      return plan;
    }
  }

  @override
  Future<Either<Failure, Plan>> uploaderPlan({
    required String chantierId,
    required String cheminFichier,
    required String nom,
    PlanFormat? format,
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? parentId,
    /// Discipline du plan et date DU PLAN — cahier technique § 4.
    /// Facultatives : un chantier qui n'a qu'un jeu de plans n'a rien à
    /// distinguer, et une date inconnue vaut mieux qu'une date inventée.
    String? typePlan,
    DateTime? datePlan,
  }) async {
    try {
      return Right(await remoteDataSource.uploaderPlan(
        chantierId: chantierId,
        cheminFichier: cheminFichier,
        nom: nom,
        format: format,
        batimentId: batimentId,
        etageId: etageId,
        zoneId: zoneId,
        parentId: parentId,
        typePlan: typePlan,
        datePlan: datePlan,
      ));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
