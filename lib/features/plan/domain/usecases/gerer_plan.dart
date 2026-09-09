import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/plan.dart';
import '../repositories/plan_repository.dart';

/// Supprime un plan et toutes ses versions.
///
/// Le serveur exige le rôle OPERATIONNEL (voir `plan.route.js`) : l'appelant
/// masque l'action pour les autres rôles plutôt que de laisser partir un appel
/// qui reviendra en 403.
class SupprimerPlan {
  final PlanRepository repository;
  SupprimerPlan(this.repository);

  Future<Either<Failure, void>> call(String id) => repository.supprimerPlan(id);
}

/// Remplace le DOCUMENT d'un plan, sans en créer un nouveau.
///
/// C'est une nouvelle VERSION : le nom, le rattachement et les réserves déjà
/// posées dessus sont conservés, et la version précédente reste dans
/// l'historique. Déposer un second plan à côté aurait laissé deux documents
/// concurrents pour le même appartement, sans dire lequel fait foi.
class RemplacerFichierPlan {
  final PlanRepository repository;
  RemplacerFichierPlan(this.repository);

  Future<Either<Failure, Plan>> call(String id, {required String cheminFichier}) =>
      repository.remplacerFichier(id, cheminFichier: cheminFichier);
}
