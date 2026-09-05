import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/abonnement.dart';
import '../repositories/abonnement_repository.dart';

/// Historique des souscriptions de l'organisation — formule, montant, statut.
class GetHistoriqueAbonnement {
  final AbonnementRepository repository;
  GetHistoriqueAbonnement(this.repository);

  Future<Either<Failure, List<SouscriptionHistorique>>> call() => repository.getHistorique();
}
