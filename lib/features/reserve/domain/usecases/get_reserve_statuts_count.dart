import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../repositories/reserve_repository.dart';

class GetReserveStatutsCount {
  final ReserveRepository repository;
  GetReserveStatutsCount(this.repository);

  Future<Either<Failure, ReserveStatutsCount>> call(String chantierId) {
    return repository.getStatutsCount(chantierId);
  }
}

/// Répartition par statut sur TOUTE l'organisation.
///
/// Alimente les compteurs des puces de filtre de l'onglet « Réserves » :
/// sans lui, seule la puce « Toutes » pouvait afficher un nombre, car le
/// `total` de la liste paginée ne décrit que le filtre COURANT et ne dit rien
/// du volume des autres puces.
class GetReserveStatutsCountGlobal {
  final ReserveRepository repository;
  GetReserveStatutsCountGlobal(this.repository);

  Future<Either<Failure, ReserveStatutsCount>> call() => repository.getStatutsCountGlobal();
}
