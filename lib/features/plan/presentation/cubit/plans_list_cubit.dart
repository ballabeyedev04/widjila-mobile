import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/plan.dart';
import '../../domain/usecases/get_plans_chantier.dart';
import '../../domain/usecases/get_tous_plans.dart';
import '../../domain/usecases/uploader_plan.dart';

enum PlansListStatus { initial, chargement, succes, erreur }

class PlansListState extends Equatable {
  final PlansListStatus status;
  final List<Plan> items;
  final String recherche;

  /// Format retenu — `null` = tous. Champ d'état À PART ENTIÈRE, et non un
  /// mot glissé dans [recherche] : le format injecté dans le texte écrasait
  /// la recherche en cours et faisait remonter au passage les plans dont le
  /// NOM contient « PDF ».
  final PlanFormat? filtreFormat;

  final String? erreur;

  /// Import de plan en cours — distinct de [status] : la liste déjà affichée
  /// doit rester visible pendant l'envoi, on ne repasse pas par un écran de
  /// chargement plein.
  final bool importEnCours;

  /// Message à afficher une fois l'import terminé. Consommé par la page puis
  /// remis à null (voir [effacerMessage]).
  final String? messageSucces;

  const PlansListState({
    this.status = PlansListStatus.initial,
    this.items = const [],
    this.recherche = '',
    this.filtreFormat,
    this.erreur,
    this.importEnCours = false,
    this.messageSucces,
  });

  /// Filtrage local : la liste des plans d'une organisation reste courte
  /// (quelques dizaines), le back ne propose pas de `search` sur cette route
  /// et en ajouter un pour ça serait disproportionné.
  List<Plan> get itemsFiltres {
    final motif = recherche.trim().toLowerCase();
    return items.where((p) {
      final correspondFormat = filtreFormat == null || p.format == filtreFormat;
      final correspondTexte = motif.isEmpty ||
          p.nom.toLowerCase().contains(motif) ||
          (p.chantierNom ?? '').toLowerCase().contains(motif);
      return correspondFormat && correspondTexte;
    }).toList();
  }

  /// Nombre de plans d'un format, `null` pour le total.
  ///
  /// Compté sur [items] — la liste complète — et non sur [itemsFiltres] :
  /// une puce doit annoncer ce qu'elle contient, pas ce qu'il en reste après
  /// s'être elle-même appliquée. Le back renvoie tous les plans en une fois
  /// (pas de pagination sur cette route), le compte est donc exact.
  int comptePourFormat(PlanFormat? format) =>
      format == null ? items.length : items.where((p) => p.format == format).length;

  /// Formats effectivement présents — inutile d'afficher une puce « IFC (0) »
  /// pour une organisation qui n'en dépose jamais.
  List<PlanFormat> get formatsPresents =>
      PlanFormat.values.where((f) => items.any((p) => p.format == f)).toList();

  bool get filtreEnPlace => recherche.trim().isNotEmpty || filtreFormat != null;

  PlansListState copyWith({
    PlansListStatus? status,
    List<Plan>? items,
    String? recherche,
    PlanFormat? filtreFormat,
    bool effacerFiltreFormat = false,
    String? erreur,
    bool? importEnCours,
    String? messageSucces,
  }) {
    return PlansListState(
      status: status ?? this.status,
      items: items ?? this.items,
      recherche: recherche ?? this.recherche,
      filtreFormat: effacerFiltreFormat ? null : (filtreFormat ?? this.filtreFormat),
      erreur: erreur,
      importEnCours: importEnCours ?? this.importEnCours,
      messageSucces: messageSucces,
    );
  }

  @override
  List<Object?> get props =>
      [status, items, recherche, filtreFormat, erreur, importEnCours, messageSucces];
}

/// Liste des plans — transversale par défaut, ou limitée à un chantier
/// lorsque [chantierId] est fourni (accès depuis le détail d'un chantier).
class PlansListCubit extends Cubit<PlansListState> {
  final GetTousPlans getTousPlans;
  final GetPlansChantier getPlansChantier;
  final UploaderPlan uploaderPlan;

  PlansListCubit({
    required this.getTousPlans,
    required this.getPlansChantier,
    required this.uploaderPlan,
  }) : super(const PlansListState());

  /// Voir `ReservesListCubit._jetonListe` — protège des réponses arrivant
  /// dans le désordre (recherche locale, mais le rechargement après import
  /// peut s'entrelacer avec un rafraîchissement manuel).
  int _jetonListe = 0;

  Future<void> charger({String? chantierId}) async {
    final jeton = ++_jetonListe;
    emit(state.copyWith(status: PlansListStatus.chargement));
    final result = chantierId == null ? await getTousPlans() : await getPlansChantier(chantierId);
    if (isClosed || jeton != _jetonListe) return;
    result.fold(
      (failure) => emit(state.copyWith(status: PlansListStatus.erreur, erreur: failure.errorMessage)),
      (plans) => emit(state.copyWith(status: PlansListStatus.succes, items: plans)),
    );
  }

  void rechercher(String texte) => emit(state.copyWith(recherche: texte));

  /// `null` = « Tous » : le filtre est effacé, pas remplacé.
  void filtrerParFormat(PlanFormat? format) =>
      emit(state.copyWith(filtreFormat: format, effacerFiltreFormat: format == null));

  /// Dépose un plan puis recharge la liste.
  ///
  /// Le rechargement plutôt qu'un simple ajout local : le back renseigne le
  /// numéro de version et le nom du chantier, et l'onglet transversal trie
  /// les plans à sa façon — insérer l'élément à la main risquerait de
  /// diverger de ce que renverra le prochain chargement.
  Future<void> importer({
    required String chantierId,
    required String cheminFichier,
    required String nom,
    PlanFormat? format,
    String? chantierIdCourant,
  }) async {
    if (state.importEnCours) return;
    emit(state.copyWith(importEnCours: true));

    final result = await uploaderPlan(
      chantierId: chantierId,
      cheminFichier: cheminFichier,
      nom: nom,
      format: format,
    );

    if (isClosed) return;
    await result.fold(
      (failure) async {
        emit(state.copyWith(importEnCours: false, erreur: failure.errorMessage));
      },
      (plan) async {
        emit(state.copyWith(importEnCours: false, messageSucces: '« ${plan.nom} » importé.'));
        await charger(chantierId: chantierIdCourant);
      },
    );
  }

  /// À appeler après affichage, pour qu'un rebuild ne rejoue pas la même
  /// notification.
  void effacerMessage() {
    if (state.messageSucces == null && state.erreur == null) return;
    emit(state.copyWith(messageSucces: null));
  }
}
