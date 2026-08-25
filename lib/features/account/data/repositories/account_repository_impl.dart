import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/connexion_log_entry.dart';
import '../../domain/entities/mfa_provisionnement.dart';
import '../../domain/entities/session_active.dart';
import '../../../auth/domain/entities/user.dart';
import '../../domain/repositories/account_repository.dart';
import '../datasources/account_remote_datasource.dart';

class AccountRepositoryImpl implements AccountRepository {
  final AccountRemoteDataSource remoteDataSource;
  AccountRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, bool>> getStatutMfa() async {
    try {
      return Right(await remoteDataSource.getStatutMfa());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<ConnexionLogEntry>>> getConnexions() async {
    try {
      return Right(await remoteDataSource.getConnexions());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<SessionActive>>> getSessions() async {
    try {
      return Right(await remoteDataSource.getSessions());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> revokerSession(String sessionId) async {
    try {
      await remoteDataSource.revokerSession(sessionId);
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> revokerToutesSessions() async {
    try {
      await remoteDataSource.revokerToutesSessions();
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, MfaProvisionnement>> provisionnerMfa() async {
    try {
      return Right(await remoteDataSource.provisionnerMfa());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> activerMfa({required String secret, required String code}) async {
    try {
      await remoteDataSource.activerMfa(secret: secret, code: code);
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> desactiverMfa({required String code}) async {
    try {
      await remoteDataSource.desactiverMfa(code: code);
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> changerLangue(String code) async {
    try {
      await remoteDataSource.changerLangue(code);
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, User>> modifierProfil({
    String? nom,
    String? prenom,
    String? telephone,
    String? fonction,
    String? cheminPhoto,
  }) async {
    try {
      return Right(await remoteDataSource.modifierProfil(
        nom: nom,
        prenom: prenom,
        telephone: telephone,
        fonction: fonction,
        cheminPhoto: cheminPhoto,
      ));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, int>> changerMotDePasse({
    required String ancienMotDePasse,
    required String nouveauMotDePasse,
  }) async {
    try {
      return Right(await remoteDataSource.changerMotDePasse(
        ancienMotDePasse: ancienMotDePasse,
        nouveauMotDePasse: nouveauMotDePasse,
      ));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> exporterDonnees() async {
    try {
      return Right(await remoteDataSource.exporterDonnees());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> supprimerCompte() async {
    try {
      await remoteDataSource.supprimerCompte();
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
