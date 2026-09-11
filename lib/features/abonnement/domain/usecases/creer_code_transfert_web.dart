import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../repositories/abonnement_repository.dart';

class CreerCodeTransfertWeb {
  final AbonnementRepository repository;
  CreerCodeTransfertWeb(this.repository);

  Future<Either<Failure, String>> call() => repository.creerCodeTransfertWeb();
}
