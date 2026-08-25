import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../repositories/auth_repository.dart';

class ForgotPassword {
  final AuthRepository repository;
  ForgotPassword(this.repository);

  Future<Either<Failure, String>> call({required String email}) {
    return repository.forgotPassword(email: email);
  }
}
