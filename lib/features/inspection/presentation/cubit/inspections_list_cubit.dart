import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/inspection.dart';
import '../../domain/usecases/inspection_usecases.dart';
import 'inspections_list_state.dart';

class InspectionsListCubit extends Cubit<InspectionsListState> {
  final GetInspections getInspections;
  final CreerInspection creerInspection;
  final String chantierId;

  /// Voir `DocumentsListCubit._jetonListe` : un changement de filtre annule
  /// l'affichage du résultat précédent, pas la requête déjà partie. Sans ce
  /// jeton, une réponse lente au filtre A écraserait celle du filtre B.
  int _jetonListe = 0;

  InspectionsListCubit({
    required this.getInspections,
    required this.creerInspection,
    required this.chantierId,
  }) : super(const InspectionsListState());

  Future<void> charger() async {
    final jeton = ++_jetonListe;
    emit(state.copyWith(status: InspectionsListStatus.chargement));
    final result = await getInspections(chantierId: chantierId, statut: state.filtreStatut);
    if (isClosed || jeton != _jetonListe) return;
    result.fold(
      (failure) => emit(state.copyWith(status: InspectionsListStatus.erreur, erreur: failure.errorMessage)),
      (items) => emit(state.copyWith(status: InspectionsListStatus.succes, items: items)),
    );
  }

  void filtrerParStatut(InspectionStatut? statut) {
    if (statut == null) {
      emit(state.copyWith(effacerFiltreStatut: true));
    } else {
      emit(state.copyWith(filtreStatut: statut));
    }
    charger();
  }

  /// Planifie une visite. La visite créée est insérée en tête sans recharger :
  /// le back renvoie l'objet complet, une seconde requête n'apprendrait rien.
  Future<void> planifier({
    required InspectionType type,
    DateTime? dateVisite,
    List<String> libellesChecklist = const [],
  }) async {
    // Verrou de double soumission : la désactivation du bouton ne prend effet
    // qu'à la frame suivante, deux appuis dans la même frame créeraient donc
    // deux visites identiques.
    if (state.creationStatus == CreationInspectionStatus.enCours) return;
    emit(state.copyWith(creationStatus: CreationInspectionStatus.enCours, effacerCreationErreur: true));

    final result = await creerInspection(
      chantierId: chantierId,
      type: type,
      dateVisite: dateVisite,
      libellesChecklist: libellesChecklist,
    );
    if (isClosed) return;

    result.fold(
      (failure) => emit(state.copyWith(
        creationStatus: CreationInspectionStatus.erreur,
        creationErreur: failure.errorMessage,
      )),
      (inspection) => emit(state.copyWith(
        creationStatus: CreationInspectionStatus.succes,
        items: [inspection, ...state.items],
      )),
    );
  }

  void accuserReceptionCreation() =>
      emit(state.copyWith(creationStatus: CreationInspectionStatus.inactif, effacerCreationErreur: true));

  /// Remplace une visite modifiée ailleurs (écran de détail) sans recharger
  /// toute la liste — l'utilisateur revient sur une liste déjà à jour.
  void remplacer(Inspection inspection) {
    emit(state.copyWith(
      items: state.items.map((i) => i.id == inspection.id ? inspection : i).toList(),
    ));
  }
}
