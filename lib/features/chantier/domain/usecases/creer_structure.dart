import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../repositories/chantier_repository.dart';

/// Ajoute un bâtiment au chantier.
///
/// Le bâtiment est le premier niveau de décomposition : le plan global montre
/// les bâtiments, et c'est en entrant dans l'un d'eux qu'on atteint les trois
/// sections de niveaux.
class CreerBatiment {
  final ChantierRepository repository;
  CreerBatiment(this.repository);

  Future<Either<Failure, BatimentStructure>> call(
    String chantierId, {
    required String nom,
    String? code,
  }) =>
      repository.creerBatiment(chantierId, nom: nom, code: code);
}

/// Ajoute un niveau à un bâtiment.
///
/// [typeNiveau] range le niveau sous « SOUS-SOLS », « ÉTAGES » ou
/// « TOITURE » — c'est la seule chose qui distingue un sous-sol d'une toiture,
/// la cote (`niveau`) ne le disant pas.
class CreerEtage {
  final ChantierRepository repository;
  CreerEtage(this.repository);

  Future<Either<Failure, EtageStructure>> call(
    String chantierId,
    String batimentId, {
    required String nom,
    required TypeNiveau typeNiveau,
    String? codeNiveau,
    String? description,
    int? niveau,
  }) =>
      repository.creerEtage(
        chantierId,
        batimentId,
        nom: nom,
        typeNiveau: typeNiveau,
        codeNiveau: codeNiveau,
        description: description,
        niveau: niveau,
      );
}

/// Ajoute un appartement (zone) à un niveau.
///
/// C'est le dernier cran de la structure : un plan déposé sur une zone est
/// celui d'un logement précis, et non plus d'un étage entier.
class CreerZone {
  final ChantierRepository repository;
  CreerZone(this.repository);

  Future<Either<Failure, ZoneStructure>> call(
    String chantierId,
    String batimentId,
    String etageId, {
    required String nom,
    String? type,
  }) =>
      repository.creerZone(chantierId, batimentId, etageId, nom: nom, type: type);
}

/// Renomme un appartement d'un niveau.
class ModifierZone {
  final ChantierRepository repository;
  ModifierZone(this.repository);

  Future<Either<Failure, ZoneStructure>> call(
    String chantierId,
    String batimentId,
    String etageId,
    String zoneId, {
    required String nom,
  }) =>
      repository.modifierZone(chantierId, batimentId, etageId, zoneId, nom: nom);
}

/// Supprime un appartement.
///
/// Le serveur refuse tant qu'une réserve y pointe — son message remonte tel
/// quel : c'est lui qui dit à l'utilisateur pourquoi il ne peut pas.
class SupprimerZone {
  final ChantierRepository repository;
  SupprimerZone(this.repository);

  Future<Either<Failure, void>> call(
    String chantierId,
    String batimentId,
    String etageId,
    String zoneId,
  ) =>
      repository.supprimerZone(chantierId, batimentId, etageId, zoneId);
}
