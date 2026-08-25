import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/document.dart';
import '../../domain/usecases/ajouter_document.dart';
import '../../domain/usecases/get_documents.dart';
import 'documents_list_state.dart';

class DocumentsListCubit extends Cubit<DocumentsListState> {
  final GetDocuments getDocuments;
  final AjouterDocument ajouterDocument;
  final String chantierId;

  Timer? _debounce;

  /// Voir `ReservesListCubit._jetonListe` : le debounce annule le timer, pas
  /// la requête déjà partie. Une réponse périmée (recherche précédente,
  /// filtre précédent) ne doit jamais écraser une plus récente.
  int _jetonListe = 0;

  DocumentsListCubit({
    required this.getDocuments,
    required this.ajouterDocument,
    required this.chantierId,
  }) : super(const DocumentsListState());

  Future<void> charger() async {
    final jeton = ++_jetonListe;
    emit(state.copyWith(status: DocumentsListStatus.chargement));
    final result = await getDocuments(chantierId: chantierId, search: state.recherche, type: state.filtreType);
    if (isClosed || jeton != _jetonListe) return;
    result.fold(
      (failure) => emit(state.copyWith(status: DocumentsListStatus.erreur, erreur: failure.errorMessage)),
      (items) => emit(state.copyWith(status: DocumentsListStatus.succes, items: items)),
    );
  }

  void rechercher(String texte) {
    _debounce?.cancel();
    emit(state.copyWith(recherche: texte));
    _debounce = Timer(const Duration(milliseconds: 400), charger);
  }

  void filtrerParType(DocumentType? type) {
    if (type == null) {
      emit(state.copyWith(effacerFiltreType: true));
    } else {
      emit(state.copyWith(filtreType: type));
    }
    charger();
  }

  /// Dépose un fichier dans la médiathèque du chantier. Le document créé est
  /// inséré en tête de liste sans recharger : le back renvoie l'objet complet,
  /// une seconde requête n'apprendrait rien de plus.
  Future<void> deposer({required String cheminFichier, required DocumentType type}) async {
    // Verrou de double soumission : la désactivation du bouton ne prend effet
    // qu'à la frame suivante, deux appuis dans la même frame passeraient donc
    // au travers et téléverseraient le fichier deux fois.
    if (state.depotStatus == DepotStatus.enCours) return;
    emit(state.copyWith(depotStatus: DepotStatus.enCours, effacerDepotErreur: true));
    final result = await ajouterDocument(chantierId: chantierId, cheminFichier: cheminFichier, type: type);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(depotStatus: DepotStatus.erreur, depotErreur: failure.errorMessage)),
      (document) => emit(state.copyWith(
        depotStatus: DepotStatus.succes,
        items: [document, ...state.items],
      )),
    );
  }

  void accuserReceptionDepot() =>
      emit(state.copyWith(depotStatus: DepotStatus.inactif, effacerDepotErreur: true));

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
