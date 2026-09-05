import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../corps_etat/domain/usecases/get_corps_etat_actifs.dart';
import '../../../phase/domain/usecases/get_phases_actives.dart';
import '../../domain/entities/chantier_structure.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/usecases/creer_reserve.dart';
import '../../domain/usecases/get_chantier_structure.dart';
import 'reserve_wizard_state.dart';

class ReserveWizardCubit extends Cubit<ReserveWizardState> {
  final GetChantierStructure getChantierStructure;
  final CreerReserve creerReserve;
  final GetCorpsEtatActifs getCorpsEtatActifs;
  final GetPhasesActives getPhasesActives;
  final String chantierId;

  ReserveWizardCubit({
    required this.getChantierStructure,
    required this.creerReserve,
    required this.getCorpsEtatActifs,
    required this.getPhasesActives,
    required this.chantierId,
  }) : super(const ReserveWizardState());

  /// Catalogue des métiers.
  ///
  /// Chargé À PART de la structure, et son échec est ignoré : le métier est
  /// facultatif, alors que la structure conditionne l'étape de localisation.
  /// Les charger ensemble ferait échouer tout l'assistant pour une liste
  /// déroulante indisponible.
  Future<void> chargerCorpsEtat() async {
    final result = await getCorpsEtatActifs();
    if (isClosed) return;
    result.fold(
      (_) {},
      (liste) => emit(state.copyWith(corpsEtatDisponibles: liste)),
    );
  }

  Future<void> chargerStructure() async {
    emit(state.copyWith(structureStatus: StructureStatus.chargement));
    final result = await getChantierStructure(chantierId);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(structureStatus: StructureStatus.erreur, erreur: failure.errorMessage)),
      (structure) => emit(state.copyWith(structureStatus: StructureStatus.succes, structure: structure)),
    );
  }

  // ── Étape 1 ──────────────────────────────────────────────────────────────
  void changerTitre(String v) => emit(state.copyWith(titre: v));
  /// Référentiel des phases.
  ///
  /// Chargé À PART de la structure : son échec ne doit pas empêcher
  /// l'assistant de s'ouvrir. Le repository sert son cache en cas de coupure,
  /// ce qui laisse la saisie possible hors ligne.
  Future<void> chargerPhases() async {
    final result = await getPhasesActives();
    if (isClosed) return;
    result.fold(
      (_) {},
      (liste) => emit(state.copyWith(phasesDisponibles: liste)),
    );
  }

  void changerPhase(String? v) => emit(state.copyWith(phaseId: v));

  void changerCorpsEtat(String? v) => emit(
        v == null ? state.copyWith(effacerCorpsEtat: true) : state.copyWith(corpsEtatId: v),
      );
  void changerPriorite(ReserveSeverite v) => emit(state.copyWith(priorite: v));
  void changerDescription(String v) => emit(state.copyWith(description: v));

  // ── Étape 2 ──────────────────────────────────────────────────────────────
  /// Choisir un nouveau bâtiment réinitialise étage/zone (qui lui sont
  /// rattachés) — évite d'envoyer un `etageId` orphelin d'un autre bâtiment.
  void changerBatiment(BatimentStructure? v) {
    if (v == null) {
      emit(state.copyWith(effacerBatiment: true, effacerEtage: true, effacerZone: true));
    } else {
      emit(state.copyWith(batiment: v, effacerEtage: true, effacerZone: true));
    }
  }

  void changerEtage(EtageStructure? v) {
    if (v == null) {
      emit(state.copyWith(effacerEtage: true, effacerZone: true));
    } else {
      emit(state.copyWith(etageValue: v, effacerZone: true));
    }
  }

  void changerZone(ZoneStructure? v) {
    if (v == null) {
      emit(state.copyWith(effacerZone: true));
    } else {
      emit(state.copyWith(zoneValue: v));
    }
  }

  void changerLot(StructureRef? v) {
    if (v == null) {
      emit(state.copyWith(effacerLot: true));
    } else {
      emit(state.copyWith(lot: v));
    }
  }

  void changerDateLimite(DateTime? v) {
    if (v == null) {
      emit(state.copyWith(effacerDateLimite: true));
    } else {
      emit(state.copyWith(dateLimite: v));
    }
  }

  void allerEtape(int etape) => emit(state.copyWith(etape: etape));

  /// Rattache la réserve au plan par lequel l'assistant a été ouvert.
  ///
  /// Appelé une seule fois, à la construction de la page : le plan est un
  /// CONTEXTE d'arrivée, pas un champ que l'utilisateur modifie ensuite.
  void definirPlan({required String id, String? nom}) =>
      emit(state.copyWith(planId: id, planNom: nom));

  Future<Reserve?> soumettre() async {
    // Verrou de double soumission — LE plus important de l'app : deux appuis
    // sur « Créer la réserve » créaient deux réserves distinctes (chacune
    // avec son propre id, donc l'idempotence côté serveur ne pouvait pas les
    // rapprocher). La désactivation du bouton n'agit qu'à la frame suivante.
    if (state.soumissionStatus == SoumissionStatus.enCours) return null;
    emit(state.copyWith(soumissionStatus: SoumissionStatus.enCours));
    final result = await creerReserve(
      chantierId: chantierId,
      titre: state.titre.trim(),
      description: state.description.trim().isEmpty ? null : state.description.trim(),
      priorite: state.priorite,
      corpsEtatId: state.corpsEtatId,
      phaseId: state.phaseId,
      batimentId: state.batiment?.id,
      etageId: state.etage?.id,
      zoneId: state.zone?.id,
      lotId: state.lot?.id,
      dateLimite: state.dateLimite,
      // Sans position : l'assistant demande le plan, pas l'endroit exact. Le
      // pointage sur le plan reste le geste de `PlanViewerPage`, où l'on voit
      // le dessin. Le serveur accepte `planId` seul (`positionX`/`positionY`
      // sont facultatifs) — la réserve est donc bien rattachée au plan, sans
      // repère faussement précis.
      planId: state.planId,
    );
    if (isClosed) return null;
    return result.fold(
      (failure) {
        emit(state.copyWith(soumissionStatus: SoumissionStatus.erreur, erreur: failure.errorMessage));
        return null;
      },
      (reserve) {
        emit(state.copyWith(soumissionStatus: SoumissionStatus.succes));
        return reserve;
      },
    );
  }
}
