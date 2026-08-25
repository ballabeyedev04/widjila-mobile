import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/reserve.dart';
import '../repositories/reserve_repository.dart';

class GetReserveDetail {
  final ReserveRepository repository;
  GetReserveDetail(this.repository);

  Future<Either<Failure, Reserve>> call(String id) => repository.getReserveDetail(id);
}
