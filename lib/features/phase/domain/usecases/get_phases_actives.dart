import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/phase_referentiel.dart';
import '../repositories/phase_repository.dart';

class GetPhasesActives {
  final PhaseRepository repository;
  GetPhasesActives(this.repository);

  Future<Either<Failure, List<PhaseReferentiel>>> call() => repository.getPhasesActives();
}
