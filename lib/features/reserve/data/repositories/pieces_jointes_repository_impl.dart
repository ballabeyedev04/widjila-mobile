import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/piece_jointe.dart';
import '../../domain/repositories/pieces_jointes_repository.dart';
import '../datasources/pieces_jointes_remote_datasource.dart';

class PiecesJointesRepositoryImpl implements PiecesJointesRepository {
  final PiecesJointesRemoteDataSource remoteDataSource;
  PiecesJointesRepositoryImpl(this.remoteDataSource);

  Future<Either<Failure, T>> _appel<T>(Future<T> Function() action) async {
    try {
      return Right(await action());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<PieceJointe>>> lister(String reserveId) =>
      _appel(() => remoteDataSource.lister(reserveId));

  @override
  Future<Either<Failure, PieceJointe>> ajouter(
    String reserveId, {
    required String cheminFichier,
    required String nomFichier,
    void Function(double progression)? onProgression,
  }) =>
      _appel(() => remoteDataSource.ajouter(
            reserveId,
            cheminFichier: cheminFichier,
            nomFichier: nomFichier,
            onProgression: onProgression,
          ));

  @override
  Future<Either<Failure, void>> supprimer(String pieceId) => _appel(() => remoteDataSource.supprimer(pieceId));
}
