import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/reserve.dart';
import '../repositories/reserve_repository.dart';

class AjouterMediaReserve {
  final ReserveRepository repository;
  AjouterMediaReserve(this.repository);

  Future<Either<Failure, ReserveMedia>> call({
    required String reserveId,
    required String cheminFichier,
    String type = 'photo',
  }) {
    return repository.ajouterMedia(reserveId: reserveId, cheminFichier: cheminFichier, type: type);
  }
}
