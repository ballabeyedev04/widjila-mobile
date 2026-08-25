import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../repositories/auth_repository.dart';

class ResetPassword {
  final AuthRepository repository;
  ResetPassword(this.repository);

  Future<Either<Failure, String>> call({
    required String email,
    required String otp,
    required String nouveauMotDePasse,
  }) {
    return repository.resetPassword(email: email, otp: otp, nouveauMotDePasse: nouveauMotDePasse);
  }
}
