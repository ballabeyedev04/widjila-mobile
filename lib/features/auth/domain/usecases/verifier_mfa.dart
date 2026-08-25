import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class VerifierMfa {
  final AuthRepository repository;
  VerifierMfa(this.repository);

  Future<Either<Failure, User>> call({required String code}) {
    return repository.verifierMfa(code: code);
  }
}
