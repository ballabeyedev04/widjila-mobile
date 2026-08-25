import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/partenaire.dart';
import '../../domain/usecases/changer_statut_partenaire.dart';
import '../../domain/usecases/creer_partenaire.dart';
import '../../domain/usecases/get_partenaires.dart';

enum PartenairesStatus { initial, chargement, succes, erreur }

/// Statut de la SOUMISSION du formulaire, distinct de celui de la liste :
/// une erreur de création ne doit pas effacer la liste déjà affichée.
enum SoumissionPartenaireStatus { inactif, enCours, succes, erreur }

class PartenairesState extends Equatable {
  final PartenairesStatus status;
  final List<Partenaire> items;
  final String recherche;
  final PartenaireType? filtreType;

  /// `null` = tous, `true` = actifs seulement, `false` = archivés seulement.
  final bool? filtreActif;

  final String? erreur;

  final SoumissionPartenaireStatus soumissionStatus;
  final String? soumissionErreur;

  /// Identifiant de l'intervenant dont la bascule actif/inactif est en vol —
  /// permet de n'immobiliser QUE sa fiche, pas toute la liste.
  final String? partenaireEnCoursDeMaj;
  final String? statutErreur;

  const PartenairesState({
    this.status = PartenairesStatus.initial,
    this.items = const [],
    this.recherche = '',
    this.filtreType,
    this.filtreActif,
    this.erreur,
    this.soumissionStatus = SoumissionPartenaireStatus.inactif,
    this.soumissionErreur,
    this.partenaireEnCoursDeMaj,
    this.statutErreur,
  });

  /// Filtrage local — `GET /organisation/partenaires` ne renvoie ni
  /// pagination ni recherche côté back, et la liste reste courte.
  List<Partenaire> get itemsFiltres {
    final motif = recherche.trim().toLowerCase();
    return items.where((p) {
      final correspondType = filtreType == null || p.type == filtreType;
      final correspondActif = filtreActif == null || p.actif == filtreActif;
      final correspondTexte = motif.isEmpty ||
          p.nom.toLowerCase().contains(motif) ||
          (p.contact ?? '').toLowerCase().contains(motif) ||
          (p.email ?? '').toLowerCase().contains(motif) ||
          (p.telephone ?? '').toLowerCase().contains(motif) ||
          (p.adresse ?? '').toLowerCase().contains(motif);
      return correspondType && correspondActif && correspondTexte;
    }).toList();
  }

  /// Un filtre est-il posé ? Sert à distinguer « aucun intervenant » de
  /// « aucun résultat » dans l'état vide — le premier invite à créer, le
  /// second à élargir la recherche.
  bool get filtreEnPlace =>
      recherche.trim().isNotEmpty || filtreType != null || filtreActif != null;

  int get nombreActifs => items.where((p) => p.actif).length;

  PartenairesState copyWith({
    PartenairesStatus? status,
    List<Partenaire>? items,
    String? recherche,
    PartenaireType? filtreType,
    bool effacerFiltreType = false,
    bool? filtreActif,
    bool effacerFiltreActif = false,
    String? erreur,
    SoumissionPartenaireStatus? soumissionStatus,
    String? soumissionErreur,
    bool effacerSoumissionErreur = false,
    String? partenaireEnCoursDeMaj,
    bool effacerPartenaireEnCoursDeMaj = false,
    String? statutErreur,
    bool effacerStatutErreur = false,
  }) {
    return PartenairesState(
      status: status ?? this.status,
      items: items ?? this.items,
      recherche: recherche ?? this.recherche,
      filtreType: effacerFiltreType ? null : (filtreType ?? this.filtreType),
      filtreActif: effacerFiltreActif ? null : (filtreActif ?? this.filtreActif),
      erreur: erreur,
      soumissionStatus: soumissionStatus ?? this.soumissionStatus,
      soumissionErreur: effacerSoumissionErreur ? null : (soumissionErreur ?? this.soumissionErreur),
      partenaireEnCoursDeMaj: effacerPartenaireEnCoursDeMaj
          ? null
          : (partenaireEnCoursDeMaj ?? this.partenaireEnCoursDeMaj),
      statutErreur: effacerStatutErreur ? null : (statutErreur ?? this.statutErreur),
    );
  }

  @override
  List<Object?> get props => [
        status,
        items,
        recherche,
        filtreType,
        filtreActif,
        erreur,
        soumissionStatus,
        soumissionErreur,
        partenaireEnCoursDeMaj,
        statutErreur,
      ];
}

class PartenairesCubit extends Cubit<PartenairesState> {
  final GetPartenaires getPartenaires;
  final CreerPartenaire creerPartenaireUsecase;
  final ChangerStatutPartenaire changerStatutPartenaireUsecase;

  PartenairesCubit({
    required this.getPartenaires,
    required this.creerPartenaireUsecase,
    required this.changerStatutPartenaireUsecase,
  }) : super(const PartenairesState());

  Future<void> charger() async {
    emit(state.copyWith(status: PartenairesStatus.chargement));
    final result = await getPartenaires();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(status: PartenairesStatus.erreur, erreur: failure.errorMessage)),
      (partenaires) => emit(state.copyWith(status: PartenairesStatus.succes, items: partenaires)),
    );
  }

  void rechercher(String texte) => emit(state.copyWith(recherche: texte));

  void filtrerParType(PartenaireType? type) =>
      emit(state.copyWith(filtreType: type, effacerFiltreType: type == null));

  void filtrerParActivite(bool? actif) =>
      emit(state.copyWith(filtreActif: actif, effacerFiltreActif: actif == null));

  void reinitialiserFiltres() => emit(state.copyWith(
        recherche: '',
        effacerFiltreType: true,
        effacerFiltreActif: true,
      ));

  /// Bascule actif ↔ archivé.
  ///
  /// Renvoie `true` si le serveur a accepté ; sinon le message est dans
  /// `state.statutErreur`. Réservé côté back aux rôles opérationnels
  /// (`requireRole` sur `PUT /partenaires/:id`) : la présentation masque
  /// l'action pour les autres plutôt que de laisser découvrir le refus.
  Future<bool> basculerStatut(String partenaireId, {required bool activer}) async {
    if (state.partenaireEnCoursDeMaj != null) return false;
    emit(state.copyWith(partenaireEnCoursDeMaj: partenaireId, effacerStatutErreur: true));

    final result = await changerStatutPartenaireUsecase(partenaireId: partenaireId, actif: activer);
    if (isClosed) return false;

    return result.fold(
      (failure) {
        emit(state.copyWith(effacerPartenaireEnCoursDeMaj: true, statutErreur: failure.errorMessage));
        return false;
      },
      (partenaire) {
        // Remplacement en place : la liste garde son ordre et sa position de
        // défilement, contrairement à un rechargement complet.
        emit(state.copyWith(
          effacerPartenaireEnCoursDeMaj: true,
          items: [
            for (final p in state.items) p.id == partenaire.id ? partenaire : p,
          ],
        ));
        return true;
      },
    );
  }

  Future<void> ajouter({
    required String nom,
    required PartenaireType type,
    String? email,
    String? telephone,
    String? contact,
    String? adresse,
    String? notes,
  }) async {
    // Verrou de double soumission : deux appuis créeraient deux intervenants
    // identiques dans l'annuaire de l'organisation.
    if (state.soumissionStatus == SoumissionPartenaireStatus.enCours) return;
    emit(state.copyWith(soumissionStatus: SoumissionPartenaireStatus.enCours, effacerSoumissionErreur: true));
    final result = await creerPartenaireUsecase(
      nom: nom,
      type: type,
      email: email,
      telephone: telephone,
      contact: contact,
      adresse: adresse,
      notes: notes,
    );
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(
        soumissionStatus: SoumissionPartenaireStatus.erreur,
        soumissionErreur: failure.errorMessage,
      )),
      (partenaire) => emit(state.copyWith(
        soumissionStatus: SoumissionPartenaireStatus.succes,
        items: [partenaire, ...state.items],
      )),
    );
  }

  void reinitialiserSoumission() => emit(state.copyWith(
        soumissionStatus: SoumissionPartenaireStatus.inactif,
        effacerSoumissionErreur: true,
      ));
}
