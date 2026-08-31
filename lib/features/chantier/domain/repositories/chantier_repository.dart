import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/chantier.dart';

/// Page de résultats — miroir du contrat de pagination backend
/// (`middlewares/pagination.middleware.js`) : `{ items, total }`.
class ChantierPage {
  final List<Chantier> items;
  final int total;
  const ChantierPage({required this.items, required this.total});
}

/// Vue demandee sur les chantiers EN DEMANDE.
///
/// Le serveur les ecarte de la liste par defaut : un chantier en attente ou
/// refuse n'est pas un chantier en activite. Ces deux valeurs rouvrent
/// explicitement la reserve.
enum VueDemandes {
  /// Les demandes deposees par le compte connecte — « Suivi des demandes ».
  miennes,

  /// La file d'attente de ceux qui tranchent.
  aValider,
}

extension VueDemandesX on VueDemandes {
  String get raw => this == VueDemandes.miennes ? 'mes' : 'a_valider';
}

abstract class ChantierRepository {
  Future<Either<Failure, ChantierPage>> getChantiers({
    int page = 1,
    int limit = 20,
    String? search,
    ChantierStatut? statut,
    VueDemandes? demandes,
  });
  Future<Either<Failure, Chantier>> getChantierDetail(String id);

  /// Dépose une demande de création de chantier.
  ///
  /// Le chantier renvoyé porte le statut décidé par le SERVEUR : pour tout
  /// compte autre que le super-admin plateforme, ce sera
  /// `en_attente_validation`.
  Future<Either<Failure, Chantier>> creerChantier({
    required String nom,
    String? adresse,
    String? description,
  });
}
