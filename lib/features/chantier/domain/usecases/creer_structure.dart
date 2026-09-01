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
