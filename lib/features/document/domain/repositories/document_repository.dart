import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/document.dart';

abstract class DocumentRepository {
  Future<Either<Failure, List<ChantierDocument>>> getDocuments({
    required String chantierId,
    String? search,
    DocumentType? type,
  });

  /// Dépôt d'un document — réservé côté back à OPERATIONNEL_CONTROLE
  /// (`requireRole` sur `POST /chantiers/:chantierId/documents`).
  Future<Either<Failure, ChantierDocument>> ajouterDocument({
    required String chantierId,
    required String cheminFichier,
    required DocumentType type,
  });
}
