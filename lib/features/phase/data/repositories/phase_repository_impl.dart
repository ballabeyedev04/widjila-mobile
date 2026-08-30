import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/phase_referentiel.dart';
import '../../domain/repositories/phase_repository.dart';
import '../datasources/phase_remote_datasource.dart';

class PhaseRepositoryImpl implements PhaseRepository {
  final PhaseRemoteDataSource remoteDataSource;

  /// Dernier référentiel reçu, conservé pour la durée de la session.
  ///
  /// Ce cache compte DOUBLE ici : la phase est OBLIGATOIRE à la création
  /// d'une réserve. Sur un chantier sans réseau, sans lui, la liste
  /// déroulante serait vide et il deviendrait impossible d'enregistrer le
  /// moindre constat. On rend donc la dernière version connue plutôt qu'une
  /// erreur.
  List<PhaseReferentiel>? _cache;

  PhaseRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<PhaseReferentiel>>> getPhasesActives() async {
    try {
      final liste = await remoteDataSource.getPhasesActives();
      _cache = liste;
      return Right(liste);
    } catch (e) {
      final cache = _cache;
      if (cache != null) return Right(cache);
      return Left(exceptionToFailure(e));
    }
  }
}
