import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/chantier.dart';
import '../repositories/chantier_repository.dart';

class GetChantiers {
  final ChantierRepository repository;
  GetChantiers(this.repository);

  Future<Either<Failure, ChantierPage>> call({
    int page = 1,
    int limit = 20,
    String? search,
    ChantierStatut? statut,
  }) {
    return repository.getChantiers(page: page, limit: limit, search: search, statut: statut);
  }
}
