import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/reserve_evolution.dart';
import '../repositories/reserve_repository.dart';

class GetReserveEvolution {
  final ReserveRepository repository;
  GetReserveEvolution(this.repository);

  Future<Either<Failure, ReserveEvolution>> call(String chantierId) => repository.getEvolution(chantierId);
}
