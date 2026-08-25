import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/chantier.dart';

/// Page de résultats — miroir du contrat de pagination backend
/// (`middlewares/pagination.middleware.js`) : `{ items, total }`.
class ChantierPage {
  final List<Chantier> items;
  final int total;
  const ChantierPage({required this.items, required this.total});
}

abstract class ChantierRepository {
  Future<Either<Failure, ChantierPage>> getChantiers({
    int page = 1,
    int limit = 20,
    String? search,
    ChantierStatut? statut,
  });
  Future<Either<Failure, Chantier>> getChantierDetail(String id);
}
