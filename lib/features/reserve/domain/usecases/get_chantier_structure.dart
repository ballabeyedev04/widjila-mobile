import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/chantier_structure.dart';
import '../repositories/reserve_repository.dart';

class GetChantierStructure {
  final ReserveRepository repository;
  GetChantierStructure(this.repository);

  Future<Either<Failure, ChantierStructure>> call(String chantierId) => repository.getStructure(chantierId);
}
