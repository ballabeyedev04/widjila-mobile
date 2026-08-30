import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/type_referentiel.dart';
import '../repositories/referentiel_repository.dart';

class GetTypesActifs {
  final ReferentielRepository repository;
  GetTypesActifs(this.repository);

  Future<Either<Failure, List<TypeReferentiel>>> call(ReferentielType referentiel) =>
      repository.getTypesActifs(referentiel);
}
