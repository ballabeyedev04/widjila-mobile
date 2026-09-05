import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/abonnement.dart';

abstract class AbonnementRepository {
  /// Formules proposées, telles que servies par le serveur.
  Future<Either<Failure, List<FormuleAbonnement>>> getFormules();

  /// Droits et consommation courants de l'organisation.
  Future<Either<Failure, DroitsAbonnement>> getDroits();

  /// Historique des souscriptions — formule, montant figé, statut, dates.
  ///
  /// Réservé aux rôles de GESTION côté serveur : un `AuthFailure` ici signifie
  /// « pas le droit de voir la facturation », pas « panne ».
  Future<Either<Failure, List<SouscriptionHistorique>>> getHistorique();
}
