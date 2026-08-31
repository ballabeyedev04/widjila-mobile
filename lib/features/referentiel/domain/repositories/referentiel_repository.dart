import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/pays.dart';
import '../entities/type_referentiel.dart';

abstract class ReferentielRepository {
  /// Types ACTIFS d'un référentiel — alimente les sélecteurs.
  Future<Either<Failure, List<TypeReferentiel>>> getTypesActifs(ReferentielType referentiel);

  /// Pays proposés à l'inscription, et les identifiants de chacun.
  Future<Either<Failure, List<Pays>>> getPays();
}
