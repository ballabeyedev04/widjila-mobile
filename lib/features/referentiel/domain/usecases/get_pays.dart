import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/pays.dart';
import '../repositories/referentiel_repository.dart';

class GetPays {
  final ReferentielRepository repository;
  GetPays(this.repository);

  Future<Either<Failure, List<Pays>>> call() => repository.getPays();
}
