import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/abonnement.dart';
import '../repositories/abonnement_repository.dart';

/// Les gestes du parcours « Premium sur devis ».
///
/// Un seul fichier : ce sont cinq appels d'une même conversation
/// commerciale, et les séparer n'apporterait que des fichiers d'une ligne.
class ListerDevis {
  final AbonnementRepository repository;
  ListerDevis(this.repository);
  Future<Either<Failure, List<Devis>>> call() => repository.listerDevis();
}

class DemanderDevis {
  final AbonnementRepository repository;
  DemanderDevis(this.repository);
  Future<Either<Failure, Devis>> call(DemandeDevis demande) => repository.demanderDevis(demande);
}

class AccepterDevis {
  final AbonnementRepository repository;
  AccepterDevis(this.repository);
  Future<Either<Failure, Devis>> call(String id) => repository.accepterDevis(id);
}

class RefuserDevis {
  final AbonnementRepository repository;
  RefuserDevis(this.repository);
  Future<Either<Failure, Devis>> call(String id, String? motif) => repository.refuserDevis(id, motif);
}

/// Rend l'ADRESSE de la page Stripe — c'est le navigateur qui l'ouvrira.
class PayerDevis {
  final AbonnementRepository repository;
  PayerDevis(this.repository);
  Future<Either<Failure, String>> call(String id) => repository.payerDevis(id);
}
