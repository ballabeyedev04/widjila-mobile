import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/document.dart';
import '../repositories/document_repository.dart';

class AjouterDocument {
  final DocumentRepository repository;
  AjouterDocument(this.repository);

  Future<Either<Failure, ChantierDocument>> call({
    required String chantierId,
    required String cheminFichier,
    required DocumentType type,
  }) {
    return repository.ajouterDocument(chantierId: chantierId, cheminFichier: cheminFichier, type: type);
  }
}
