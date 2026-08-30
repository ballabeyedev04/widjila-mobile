import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/reserve.dart';
import '../repositories/reserve_repository.dart';

class CreerReserve {
  final ReserveRepository repository;
  CreerReserve(this.repository);

  Future<Either<Failure, Reserve>> call({
    required String chantierId,
    required String titre,
    String? description,
    required ReserveSeverite priorite,
    /// Ancienne catégorie figée. Rendue FACULTATIVE : les écrans passés au
    /// catalogue dynamique envoient `corpsEtatId` à la place, et le serveur
    /// n'a plus besoin que d'une valeur de repli.
    ReserveCategorie categorie = ReserveCategorie.autre,
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? lotId,
    DateTime? dateLimite,
    /// Plan sur lequel la réserve a été posée, et point exact du clic —
    /// tous deux facultatifs : une réserve créée depuis la liste n'a ni l'un
    /// ni l'autre. Voir `ReservePosition` côté backend, `x`/`y` sont des
    /// POURCENTAGES de la page (0-100), jamais des pixels.
    String? planId,
    double? positionX,
    double? positionY,
    /// Entreprise responsable de la correction (« Entreprise concernée » du
    /// guide client) — un PARTENAIRE de l'annuaire du chantier, et non une
    /// organisation : la plupart des entreprises d'un chantier n'ont pas de
    /// compte dans l'application. Voir `reserve.model.js#partenaireId`.
    ///
    /// `severite` vaut `priorite` quand elle n'est pas précisée — c'était le
    /// comportement implicite jusqu'ici.
    String? partenaireId,
    ReserveSeverite? severite,
    /// Corps d'état (métier) — référence au catalogue administrable servi par
    /// `/corps-etat/actifs`. Remplace `categorie`, conservée pour les serveurs
    /// et les écrans qui s'appuient encore dessus.
    String? corpsEtatId,
    /// Phase du chantier — OBLIGATOIRE à la création (le serveur refuse sans).
    /// Figée ensuite : une réserve relevée en « Pré-cloisons » y reste quand le
    /// chantier passe en « Cloisons ».
    String? phaseId,
  }) {
    return repository.creerReserve(
      chantierId: chantierId,
      titre: titre,
      description: description,
      priorite: priorite,
      categorie: categorie,
      batimentId: batimentId,
      etageId: etageId,
      zoneId: zoneId,
      lotId: lotId,
      dateLimite: dateLimite,
      planId: planId,
      positionX: positionX,
      positionY: positionY,
      partenaireId: partenaireId,
      severite: severite,
      corpsEtatId: corpsEtatId,
      phaseId: phaseId,
    );
  }
}
