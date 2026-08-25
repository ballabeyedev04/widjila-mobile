import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/reserve.dart';
import '../repositories/reserve_repository.dart';

class CreerReserve {
  final ReserveRepository repository;
  CreerReserve(this.repository);

  Future<Either<Failure, Reserve>> call({
    required String chantierId,
    required String titre,
    String? description,
    required ReserveSeverite priorite,
    required ReserveCategorie categorie,
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? lotId,
    DateTime? dateLimite,
  }) {
    return repository.creerReserve(
      chantierId: chantierId,
      titre: titre,
      description: description,
      priorite: priorite,
      categorie: categorie,
      batimentId: batimentId,
      etageId: etageId,
      zoneId: zoneId,
      lotId: lotId,
      dateLimite: dateLimite,
    );
  }
}
