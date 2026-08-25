import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/reserve.dart';
import '../repositories/reserve_repository.dart';

class GetReserves {
  final ReserveRepository repository;
  GetReserves(this.repository);

  Future<Either<Failure, ReservePage>> call({
    required String chantierId,
    int page = 1,
    int limit = 20,
    String? search,
    ReserveStatut? statut,
  }) {
    return repository.getReserves(chantierId: chantierId, page: page, limit: limit, search: search, statut: statut);
  }
}
