import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/corps_etat.dart';
import '../repositories/corps_etat_repository.dart';

class GetCorpsEtatActifs {
  final CorpsEtatRepository repository;
  GetCorpsEtatActifs(this.repository);

  Future<Either<Failure, List<CorpsEtat>>> call() => repository.getCorpsEtatActifs();
}
