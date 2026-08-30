import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/corps_etat.dart';

abstract class CorpsEtatRepository {
  /// Métiers ACTIFS visibles par l'organisation de l'utilisateur — c'est la
  /// seule lecture dont le mobile a besoin : il consulte le catalogue pour
  /// remplir une liste déroulante, il ne l'administre pas.
  Future<Either<Failure, List<CorpsEtat>>> getCorpsEtatActifs();
}
