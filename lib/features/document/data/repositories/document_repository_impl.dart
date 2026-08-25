import 'package:dartz/dartz.dart';
import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/document.dart';
import '../../domain/repositories/document_repository.dart';
import '../datasources/document_remote_datasource.dart';

class DocumentRepositoryImpl implements DocumentRepository {
  final DocumentRemoteDataSource remoteDataSource;
  DocumentRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<ChantierDocument>>> getDocuments({
    required String chantierId,
    String? search,
    DocumentType? type,
  }) async {
    try {
      final result = await remoteDataSource.getDocuments(chantierId: chantierId, search: search, type: type);
      return Right(result);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, ChantierDocument>> ajouterDocument({
    required String chantierId,
    required String cheminFichier,
    required DocumentType type,
  }) async {
    try {
      final result = await remoteDataSource.ajouterDocument(chantierId: chantierId, cheminFichier: cheminFichier, type: type);
      return Right(result);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
