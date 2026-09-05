import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/abonnement.dart';
import '../../domain/repositories/abonnement_repository.dart';
import '../datasources/abonnement_remote_datasource.dart';

class AbonnementRepositoryImpl implements AbonnementRepository {
  final AbonnementRemoteDataSource remoteDataSource;

  /// Derniers droits reçus.
  ///
  /// Sert de repli hors ligne : sur un chantier sans réseau, l'application
  /// doit continuer de savoir ce qu'elle a le droit d'afficher. Ce cache ne
  /// donne AUCUN accès — les gardes réelles sont côté serveur, un droit
  /// périmé en cache ne fait au pire qu'afficher un bouton qui sera refusé.
  DroitsAbonnement? _cacheDroits;

  AbonnementRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<FormuleAbonnement>>> getFormules() async {
    try {
      return Right(await remoteDataSource.getFormules());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, DroitsAbonnement>> getDroits() async {
    try {
      final droits = await remoteDataSource.getDroits();
      _cacheDroits = droits;
      return Right(droits);
    } catch (e) {
      final cache = _cacheDroits;
      if (cache != null) return Right(cache);
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<SouscriptionHistorique>>> getHistorique() async {
    try {
      return Right(await remoteDataSource.getHistorique());
    } catch (e) {
      // Pas de repli en cache ici, contrairement aux droits : un historique
      // de facturation périmé induirait en erreur sur ce qui a réellement été
      // payé. Mieux vaut ne rien montrer que montrer un montant faux.
      return Left(exceptionToFailure(e));
    }
  }
}
