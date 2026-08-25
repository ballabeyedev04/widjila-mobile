import 'package:equatable/equatable.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/repositories/reserve_repository.dart';

enum ReservesListStatus { initial, chargement, succes, erreur }

class ReservesListState extends Equatable {
  final ReservesListStatus status;
  final List<Reserve> items;
  final int total;
  final int page;
  final bool chargementPage;
  final String recherche;
  final ReserveStatut? filtreStatut;
  final ReserveStatutsCount statutsCount;
  final String? erreur;

  const ReservesListState({
    this.status = ReservesListStatus.initial,
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.chargementPage = false,
    this.recherche = '',
    this.filtreStatut,
    this.statutsCount = const ReserveStatutsCount(parStatut: {}, total: 0),
    this.erreur,
  });

  bool get aPlusDeResultats => items.length < total;

  ReservesListState copyWith({
    ReservesListStatus? status,
    List<Reserve>? items,
    int? total,
    int? page,
    bool? chargementPage,
    String? recherche,
    ReserveStatut? filtreStatut,
    bool effacerFiltreStatut = false,
    ReserveStatutsCount? statutsCount,
    String? erreur,
  }) {
    return ReservesListState(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      chargementPage: chargementPage ?? false,
      recherche: recherche ?? this.recherche,
      filtreStatut: effacerFiltreStatut ? null : (filtreStatut ?? this.filtreStatut),
      statutsCount: statutsCount ?? this.statutsCount,
      erreur: erreur,
    );
  }

  @override
  List<Object?> get props =>
      [status, items, total, page, chargementPage, recherche, filtreStatut, statutsCount, erreur];
}
