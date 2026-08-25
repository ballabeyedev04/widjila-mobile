import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/reserve.dart';
import '../repositories/reserve_repository.dart';

class ChangerStatutReserve {
  final ReserveRepository repository;
  ChangerStatutReserve(this.repository);

  Future<Either<Failure, Reserve>> call({required String reserveId, required ReserveStatut statut, String? motif}) {
    return repository.changerStatut(reserveId: reserveId, statut: statut, motif: motif);
  }
}
