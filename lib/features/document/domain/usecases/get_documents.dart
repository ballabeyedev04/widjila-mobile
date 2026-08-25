import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/document.dart';
import '../repositories/document_repository.dart';

class GetDocuments {
  final DocumentRepository repository;
  GetDocuments(this.repository);

  Future<Either<Failure, List<ChantierDocument>>> call({required String chantierId, String? search, DocumentType? type}) {
    return repository.getDocuments(chantierId: chantierId, search: search, type: type);
  }
}
