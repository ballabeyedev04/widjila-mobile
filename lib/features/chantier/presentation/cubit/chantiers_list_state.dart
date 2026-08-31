import 'package:equatable/equatable.dart';
import '../../domain/entities/chantier.dart';

enum ChantiersListStatus { initial, chargement, succes, erreur }

class ChantiersListState extends Equatable {
  final ChantiersListStatus status;
  final List<Chantier> items;
  final int total;
  final int page;
  final bool chargementPage;
  final String recherche;

  /// Statut retenu — `null` = tous. Filtré CÔTÉ SERVEUR (`?statut=`).
  final ChantierStatut? filtreStatut;

  /// Nombre de chantiers par statut sur toute l'organisation.
  ///
  /// Vient de `GET /dashboard` (`stats.parChantier`, qui liste chaque
  /// chantier avec son statut) et non de [items] : la liste est paginée, la
  /// compter donnerait le contenu de la page courante et non le volume réel
  /// de chaque puce.
  final Map<ChantierStatut, int> compteursParStatut;

  /// Nombre total de chantiers, toutes catégories — pour la puce « Tous ».
  final int totalGlobal;

  final String? erreur;

  const ChantiersListState({
    this.status = ChantiersListStatus.initial,
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.chargementPage = false,
    this.recherche = '',
    this.filtreStatut,
    this.compteursParStatut = const {},
    this.totalGlobal = 0,
    this.erreur,
  });

  bool get aPlusDeResultats => items.length < total;

  /// Un filtre est-il posé ? Sert à distinguer « aucun chantier » de
  /// « aucun résultat » dans l'état vide.
  bool get filtreEnPlace => recherche.trim().isNotEmpty || filtreStatut != null;

  /// Compte d'une puce — `null` pour « Tous ».
  int comptePourStatut(ChantierStatut? statut) =>
      statut == null ? totalGlobal : (compteursParStatut[statut] ?? 0);

  /// Statuts effectivement représentés — inutile d'afficher une puce
  /// « Clôturé (0) » pour une organisation qui n'en a aucun.
  ///
  /// Les statuts du CIRCUIT en sont exclus : les demandes ont leur propre
  /// écran, et le serveur les écarte déjà de cette liste — une puce qui ne
  /// ramènerait rien serait pire qu'une puce absente.
  List<ChantierStatut> get statutsPresents => ChantierStatut.values
      .where((s) => !s.estUneDemande && (compteursParStatut[s] ?? 0) > 0)
      .toList();

  ChantiersListState copyWith({
    ChantiersListStatus? status,
    List<Chantier>? items,
    int? total,
    int? page,
    bool? chargementPage,
    String? recherche,
    ChantierStatut? filtreStatut,
    bool effacerFiltreStatut = false,
    Map<ChantierStatut, int>? compteursParStatut,
    int? totalGlobal,
    String? erreur,
  }) {
    return ChantiersListState(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      chargementPage: chargementPage ?? false,
      recherche: recherche ?? this.recherche,
      filtreStatut: effacerFiltreStatut ? null : (filtreStatut ?? this.filtreStatut),
      compteursParStatut: compteursParStatut ?? this.compteursParStatut,
      totalGlobal: totalGlobal ?? this.totalGlobal,
      erreur: erreur,
    );
  }

  @override
  List<Object?> get props => [
        status, items, total, page, chargementPage, recherche,
        filtreStatut, compteursParStatut, totalGlobal, erreur,
      ];
}
