import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/login_result.dart';
import '../repositories/auth_repository.dart';

class LoginUser {
  final AuthRepository repository;
  LoginUser(this.repository);

  Future<Either<Failure, LoginResult>> call({
    required String identifiant,
    required String motDePasse,
  }) {
    return repository.login(identifiant: identifiant, motDePasse: motDePasse);
  }
}
