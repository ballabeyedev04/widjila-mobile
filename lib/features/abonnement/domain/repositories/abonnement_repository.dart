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

  /// Code de transfert de session vers la page de paiement du web — deux
  /// minutes, usage unique. Voir `AbonnementPage`.
  Future<Either<Failure, String>> creerCodeTransfertWeb();

  /// Dernier paiement Stripe engagé par l'organisation, tel que le serveur
  /// le connaît — `null` s'il n'y en a jamais eu. Jamais mis en cache : c'est
  /// l'état le plus récent qu'on veut, ou une erreur.
  Future<Either<Failure, EtatPaiement?>> getEtatPaiement();
}
