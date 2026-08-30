import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/abonnement.dart';

abstract class AbonnementRepository {
  /// Formules proposées, telles que servies par le serveur.
  Future<Either<Failure, List<FormuleAbonnement>>> getFormules();

  /// Droits et consommation courants de l'organisation.
  Future<Either<Failure, DroitsAbonnement>> getDroits();
}
