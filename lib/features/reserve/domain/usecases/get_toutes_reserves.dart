import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/reserve.dart';
import '../repositories/reserve_repository.dart';

/// Réserves de toute l'organisation, tous chantiers confondus — l'onglet
/// « Réserves » de la barre de navigation. [GetReserves] reste l'accès par
/// chantier.
class GetToutesReserves {
  final ReserveRepository repository;
  GetToutesReserves(this.repository);

  Future<Either<Failure, ReservePage>> call({
    int page = 1,
    int limit = 20,
    String? search,
    ReserveStatut? statut,
  }) {
    return repository.getToutesReserves(page: page, limit: limit, search: search, statut: statut);
  }
}
