import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/chantier.dart';
import '../repositories/chantier_repository.dart';

class GetChantierDetail {
  final ChantierRepository repository;
  GetChantierDetail(this.repository);

  Future<Either<Failure, Chantier>> call(String id) => repository.getChantierDetail(id);
}
