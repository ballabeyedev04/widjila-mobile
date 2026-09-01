import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/chantier.dart';
import '../repositories/chantier_repository.dart';

/// Dépose une demande de création de chantier.
///
/// Le nom est le seul champ exigé par le serveur. Tous les autres champs de
/// la fiche chantier sont proposés dès la demande : le client a demandé « les
/// mêmes champs que côté admin », et un valideur qui doit rappeler le
/// demandeur pour connaître l'adresse ou les dates ne tranche pas.
///
/// Le statut du chantier renvoyé est décidé par le SERVEUR d'après le rôle de
/// l'appelant : tout compte autre que le super-admin plateforme obtient une
/// demande en attente, jamais un chantier utilisable.
class CreerChantier {
  final ChantierRepository repository;
  CreerChantier(this.repository);

  Future<Either<Failure, Chantier>> call({
    required String nom,
    String? code,
    String? adresse,
    String? description,
    double? latitude,
    double? longitude,
    DateTime? dateDebut,
    DateTime? dateFin,
    num? budget,
    String? responsableId,
  }) =>
      repository.creerChantier(
        nom: nom,
        code: code,
        adresse: adresse,
        description: description,
        latitude: latitude,
        longitude: longitude,
        dateDebut: dateDebut,
        dateFin: dateFin,
        budget: budget,
        responsableId: responsableId,
      );
}
