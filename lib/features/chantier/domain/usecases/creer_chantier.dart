import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/chantier.dart';
import '../repositories/chantier_repository.dart';

/// Dépose une demande de création de chantier.
///
/// Le nom est le seul champ exigé par le serveur ; l'adresse et la
/// description sont ce qui permet à un valideur de trancher sans rappeler le
/// demandeur, d'où leur présence dès la demande.
///
/// Le statut du chantier renvoyé est décidé par le SERVEUR d'après le rôle de
/// l'appelant : tout compte autre que le super-admin plateforme obtient une
/// demande en attente, jamais un chantier utilisable.
class CreerChantier {
  final ChantierRepository repository;
  CreerChantier(this.repository);

  Future<Either<Failure, Chantier>> call({
    required String nom,
    String? adresse,
    String? description,
  }) =>
      repository.creerChantier(nom: nom, adresse: adresse, description: description);
}
