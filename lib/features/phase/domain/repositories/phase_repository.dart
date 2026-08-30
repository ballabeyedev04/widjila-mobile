import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/phase_referentiel.dart';

abstract class PhaseRepository {
  /// Phases ACTIVES du référentiel, dans l'ordre fixé par l'administrateur.
  /// Seule lecture dont le mobile a besoin : il remplit une liste déroulante,
  /// il n'administre pas le référentiel.
  Future<Either<Failure, List<PhaseReferentiel>>> getPhasesActives();
}
