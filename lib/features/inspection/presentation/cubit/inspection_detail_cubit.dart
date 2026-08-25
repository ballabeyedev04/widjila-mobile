import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/inspection.dart';
import '../../domain/usecases/inspection_usecases.dart';
import 'inspection_detail_state.dart';

class InspectionDetailCubit extends Cubit<InspectionDetailState> {
  final GetInspection getInspection;
  final CocherLigneChecklist cocherLigne;
  final ChangerStatutInspection changerStatut;
  final GetConvocations getConvocations;
  final RepondreConvocation repondreConvocation;
  final String inspectionId;

  InspectionDetailCubit({
    required this.getInspection,
    required this.cocherLigne,
    required this.changerStatut,
    required this.getConvocations,
    required this.repondreConvocation,
    required this.inspectionId,
  }) : super(const InspectionDetailState());

  Future<void> charger() async {
    emit(state.copyWith(status: InspectionDetailStatus.chargement));

    final result = await getInspection(inspectionId);
    if (isClosed) return;

    await result.fold(
      (failure) async =>
          emit(state.copyWith(status: InspectionDetailStatus.erreur, erreur: failure.errorMessage)),
      (inspection) async {
        // Les convocations sont un appel SÉPARÉ, et leur échec ne doit pas
        // faire échouer l'écran : la checklist reste utilisable même si la
        // liste des convoqués n'a pas pu être récupérée.
        final conv = await getConvocations(inspectionId);
        if (isClosed) return;
        emit(state.copyWith(
          status: InspectionDetailStatus.succes,
          inspection: inspection,
          convocations: conv.fold((_) => const <Convocation>[], (c) => c),
        ));
      },
    );
  }

  /// Coche ou décoche un point de contrôle.
  ///
  /// Mise à jour OPTIMISTE : la case bascule immédiatement, sans attendre le
  /// réseau. Sur un chantier, la latence rendrait la saisie d'une checklist de
  /// quarante points pénible. En cas d'échec, la ligne revient à son état
  /// d'origine et l'erreur est signalée.
  Future<void> basculerLigne(LigneChecklist ligne, {String? commentaire}) async {
    final inspection = state.inspection;
    if (inspection == null) return;

    // Une visite signée est figée : le serveur refuserait, autant ne pas
    // laisser l'utilisateur croire que sa modification est prise.
    if (inspection.statut.estFigee) return;

    // Bascule déjà en vol sur cette ligne : ignorer évite d'inverser deux fois.
    if (state.lignesEnCours.contains(ligne.id)) return;

    final valeurVoulue = !ligne.coche;

    Inspection appliquer(bool valeur) => inspection.copyWith(
          checklist: inspection.checklist
              .map((l) => l.id == ligne.id ? l.copyWith(coche: valeur, commentaire: commentaire) : l)
              .toList(),
        );

    emit(state.copyWith(
      inspection: appliquer(valeurVoulue),
      lignesEnCours: {...state.lignesEnCours, ligne.id},
      effacerErreurAction: true,
    ));

    final result = await cocherLigne(
      inspectionId: inspectionId,
      ligneId: ligne.id,
      coche: valeurVoulue,
      commentaire: commentaire,
    );
    if (isClosed) return;

    final restantes = {...state.lignesEnCours}..remove(ligne.id);

    result.fold(
      (failure) => emit(state.copyWith(
        // Retour à l'état d'avant : la case reflète de nouveau le serveur.
        inspection: appliquer(ligne.coche),
        lignesEnCours: restantes,
        erreurAction: failure.errorMessage,
      )),
      (_) => emit(state.copyWith(lignesEnCours: restantes)),
    );
  }

  /// Fait avancer la visite (démarrer, terminer, signer).
  Future<void> avancerVers(InspectionStatut statut, {String? compteRendu}) async {
    final result = await changerStatut(id: inspectionId, statut: statut, compteRendu: compteRendu);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(erreurAction: failure.errorMessage)),
      (inspection) => emit(state.copyWith(inspection: inspection, effacerErreurAction: true)),
    );
  }

  Future<void> repondre(Convocation convocation, StatutConvocation statut) async {
    final result = await repondreConvocation(
      inspectionId: inspectionId,
      convocationId: convocation.id,
      statut: statut,
    );
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(erreurAction: failure.errorMessage)),
      (_) async {
        final conv = await getConvocations(inspectionId);
        if (isClosed) return;
        conv.fold(
          (_) => null,
          (liste) => emit(state.copyWith(convocations: liste, effacerErreurAction: true)),
        );
      },
    );
  }

  void accuserReceptionErreur() => emit(state.copyWith(effacerErreurAction: true));
}
