import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class RestaurerSession {
  final AuthRepository repository;
  RestaurerSession(this.repository);

  Future<User?> call() => repository.restaurerSession();
}
