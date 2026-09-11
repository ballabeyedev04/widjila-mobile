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
  ///
  /// [nomFichier] : nom d'origine, quand le chemin est celui d'une copie en
  /// cache (sélecteur de fichiers).
  Future<void> deposer({
    required String cheminFichier,
    required DocumentType type,
    String? nomFichier,
  }) async {
    // Verrou de double soumission : la désactivation du bouton ne prend effet
    // qu'à la frame suivante, deux appuis dans la même frame passeraient donc
    // au travers et téléverseraient le fichier deux fois.
    if (state.depotStatus == DepotStatus.enCours) return;
    emit(state.copyWith(
      depotStatus: DepotStatus.enCours,
      effacerDepotErreur: true,
      effacerDepotProgression: true,
    ));

    // Une émission par point de pourcentage au plus : Dio signale chaque
    // paquet envoyé, soit des milliers d'appels pour une vidéo.
    var dernierPourcent = -1;
    final result = await ajouterDocument(
      chantierId: chantierId,
      cheminFichier: cheminFichier,
      type: type,
      nomFichier: nomFichier,
      onProgression: (progression) {
        final borne = progression.clamp(0.0, 1.0);
        final pourcent = (borne * 100).floor();
        if (isClosed || pourcent == dernierPourcent) return;
        dernierPourcent = pourcent;
        emit(state.copyWith(depotProgression: borne));
      },
    );
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(
        depotStatus: DepotStatus.erreur,
        depotErreur: failure.errorMessage,
        effacerDepotProgression: true,
      )),
      (document) => emit(state.copyWith(
        depotStatus: DepotStatus.succes,
        items: [document, ...state.items],
        effacerDepotProgression: true,
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
