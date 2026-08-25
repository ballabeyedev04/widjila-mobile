import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/chantier_structure.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/usecases/creer_reserve.dart';
import '../../domain/usecases/get_chantier_structure.dart';
import 'reserve_wizard_state.dart';

class ReserveWizardCubit extends Cubit<ReserveWizardState> {
  final GetChantierStructure getChantierStructure;
  final CreerReserve creerReserve;
  final String chantierId;

  ReserveWizardCubit({
    required this.getChantierStructure,
    required this.creerReserve,
    required this.chantierId,
  }) : super(const ReserveWizardState());

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
  void changerCategorie(ReserveCategorie v) => emit(state.copyWith(categorie: v));
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
      categorie: state.categorie,
      batimentId: state.batiment?.id,
      etageId: state.etage?.id,
      zoneId: state.zone?.id,
      lotId: state.lot?.id,
      dateLimite: state.dateLimite,
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
