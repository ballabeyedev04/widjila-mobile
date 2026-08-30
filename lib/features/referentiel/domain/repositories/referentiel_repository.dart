import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/type_referentiel.dart';

abstract class ReferentielRepository {
  /// Types ACTIFS d'un référentiel — alimente les sélecteurs.
  Future<Either<Failure, List<TypeReferentiel>>> getTypesActifs(ReferentielType referentiel);
}
