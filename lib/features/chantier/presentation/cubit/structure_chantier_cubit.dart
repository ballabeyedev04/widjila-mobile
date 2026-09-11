import 'dart:math' as math;

import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failure.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../../../reserve/domain/usecases/get_chantier_structure.dart';
import '../../domain/usecases/creer_structure.dart';
import 'structure_chantier_state.dart';

/// Structure d'un chantier : bâtiments → niveaux → appartements.
///
/// Toute modification est suivie d'un rechargement de la structure : le
/// serveur renvoie l'élément modifié SEUL (un bâtiment sans ses niveaux), et
/// recomposer l'arbre à la main dupliquerait la logique d'ordre et de
/// rattachement du serveur.
class StructureChantierCubit extends Cubit<StructureChantierState> {
  final String chantierId;
  final GetChantierStructure getStructure;
  final CreerBatiment creerBatimentUsecase;
  final ModifierBatiment modifierBatimentUsecase;
  final SupprimerBatiment supprimerBatimentUsecase;
  final CreerEtage creerEtageUsecase;
  final ModifierEtage modifierEtageUsecase;
  final SupprimerEtage supprimerEtageUsecase;
  final CreerZone creerZoneUsecase;
  final ModifierZone modifierZoneUsecase;
  final SupprimerZone supprimerZoneUsecase;

  StructureChantierCubit({
    required this.chantierId,
    required this.getStructure,
    required this.creerBatimentUsecase,
    required this.modifierBatimentUsecase,
    required this.supprimerBatimentUsecase,
    required this.creerEtageUsecase,
    required this.modifierEtageUsecase,
    required this.supprimerEtageUsecase,
    required this.creerZoneUsecase,
    required this.modifierZoneUsecase,
    required this.supprimerZoneUsecase,
  }) : super(const StructureChantierState());

  /// [silencieux] : rechargement après une modification — l'écran garde la
  /// structure affichée au lieu de repasser par le squelette.
  Future<void> charger({bool silencieux = false}) async {
    if (!silencieux || state.structure == null) {
      emit(state.copyWith(status: StructureStatus.chargement, effacerErreur: true));
    }
    final resultat = await getStructure(chantierId);
    if (isClosed) return;
    resultat.fold(
      (failure) {
        // Un rechargement silencieux qui échoue garde la structure connue
        // plutôt que de remplacer l'écran par une erreur.
        if (silencieux && state.structure != null) return;
        emit(state.copyWith(status: StructureStatus.erreur, erreur: failure.errorMessage));
      },
      (structure) => emit(state.copyWith(
        status: StructureStatus.succes,
        structure: structure,
        effacerErreur: true,
      )),
    );
  }

  /// Envoie une modification puis recharge la structure.
  ///
  /// Renvoie le message d'erreur du serveur — « des réserves y sont
  /// rattachées », typiquement —, ou `null` si tout s'est bien passé.
  Future<String?> _modifier(Future<Either<Failure, Object?>> Function() action) async {
    if (state.actionEnCours) return null;
    emit(state.copyWith(actionEnCours: true));
    final resultat = await action();
    if (isClosed) return null;
    final erreur = resultat.fold<String?>((failure) => failure.errorMessage, (_) => null);
    if (erreur == null) await charger(silencieux: true);
    if (!isClosed) emit(state.copyWith(actionEnCours: false));
    return erreur;
  }

  // ── Bâtiments ─────────────────────────────────────────────────────────────

  Future<String?> ajouterBatiment(String nom) =>
      _modifier(() => creerBatimentUsecase(chantierId, nom: nom));

  Future<String?> renommerBatiment(String batimentId, String nom) =>
      _modifier(() => modifierBatimentUsecase(chantierId, batimentId, nom: nom));

  Future<String?> retirerBatiment(String batimentId) =>
      _modifier(() => supprimerBatimentUsecase(chantierId, batimentId));

  // ── Niveaux ───────────────────────────────────────────────────────────────

  Future<String?> ajouterNiveau(String batimentId, {required String nom, required TypeNiveau type}) =>
      _modifier(() => creerEtageUsecase(
            chantierId,
            batimentId,
            nom: nom,
            typeNiveau: type,
            niveau: coteSuivante(batimentId, type),
          ));

  Future<String?> renommerNiveau(String batimentId, String etageId, String nom) =>
      _modifier(() => modifierEtageUsecase(chantierId, batimentId, etageId, nom: nom));

  Future<String?> retirerNiveau(String batimentId, String etageId) =>
      _modifier(() => supprimerEtageUsecase(chantierId, batimentId, etageId));

  // ── Appartements ──────────────────────────────────────────────────────────

  Future<String?> ajouterAppartement(String batimentId, String etageId, String nom) =>
      _modifier(() => creerZoneUsecase(chantierId, batimentId, etageId, nom: nom, type: 'logement'));

  Future<String?> renommerAppartement(String batimentId, String etageId, String zoneId, String nom) =>
      _modifier(() => modifierZoneUsecase(chantierId, batimentId, etageId, zoneId, nom: nom));

  Future<String?> retirerAppartement(String batimentId, String etageId, String zoneId) =>
      _modifier(() => supprimerZoneUsecase(chantierId, batimentId, etageId, zoneId));

  /// Cote du prochain niveau d'un type donné.
  ///
  /// Sans elle, tous les niveaux créés d'ici partaient à la cote 0 et se
  /// rangeaient dans un ordre arbitraire. On la déduit plutôt que de la faire
  /// saisir : sous le plus bas des sous-sols, au-dessus du plus haut des
  /// étages, au sommet du bâtiment pour une toiture.
  int coteSuivante(String batimentId, TypeNiveau type) {
    final batiment = state.structure?.batiments.where((b) => b.id == batimentId).firstOrNull;
    final niveaux = batiment?.etages ?? const <EtageStructure>[];
    Iterable<int> cotes(TypeNiveau t) => niveaux.where((e) => e.typeNiveau == t).map((e) => e.niveau);

    switch (type) {
      case TypeNiveau.sousSol:
        final c = cotes(TypeNiveau.sousSol);
        return c.isEmpty ? -1 : c.reduce(math.min) - 1;
      case TypeNiveau.etage:
        final c = cotes(TypeNiveau.etage);
        return c.isEmpty ? 0 : c.reduce(math.max) + 1;
      case TypeNiveau.toiture:
        final toutes = niveaux.map((e) => e.niveau);
        return toutes.isEmpty ? 1 : toutes.reduce(math.max) + 1;
    }
  }
}
