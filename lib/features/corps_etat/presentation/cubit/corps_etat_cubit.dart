import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/corps_etat.dart';
import '../../domain/usecases/get_corps_etat_actifs.dart';

enum CorpsEtatStatus { initial, chargement, succes, vide, erreur }

/// État du catalogue des métiers BTP.
///
/// [CorpsEtatStatus.vide] est distinct de [CorpsEtatStatus.succes] : un
/// catalogue vide n'est pas une erreur, mais il appelle un message différent
/// (« aucun métier au catalogue », qui invite à en ajouter côté web) d'une
/// liste chargée. Les confondre afficherait une liste déroulante muette sans
/// que l'utilisateur comprenne pourquoi.
class CorpsEtatState extends Equatable {
  final CorpsEtatStatus status;
  final List<CorpsEtat> items;
  final String? erreur;

  const CorpsEtatState({
    this.status = CorpsEtatStatus.initial,
    this.items = const [],
    this.erreur,
  });

  CorpsEtatState copyWith({
    CorpsEtatStatus? status,
    List<CorpsEtat>? items,
    String? erreur,
  }) {
    return CorpsEtatState(
      status: status ?? this.status,
      items: items ?? this.items,
      erreur: erreur,
    );
  }

  /// Vrai quand la liste est exploitable par un sélecteur.
  bool get pretPourSelection => status == CorpsEtatStatus.succes && items.isNotEmpty;

  @override
  List<Object?> get props => [status, items, erreur];
}

class CorpsEtatCubit extends Cubit<CorpsEtatState> {
  final GetCorpsEtatActifs getCorpsEtatActifs;

  CorpsEtatCubit({required this.getCorpsEtatActifs}) : super(const CorpsEtatState());

  Future<void> charger() async {
    // Ne repasse pas par un écran de chargement quand on a déjà la liste :
    // le rafraîchissement d'un catalogue déjà affiché ne doit pas faire
    // clignoter le formulaire ouvert par-dessus.
    if (state.items.isEmpty) {
      emit(state.copyWith(status: CorpsEtatStatus.chargement));
    }

    final result = await getCorpsEtatActifs();
    if (isClosed) return;

    result.fold(
      (failure) => emit(state.copyWith(
        // Une panne alors qu'on tient déjà une liste ne doit pas la jeter :
        // le repli du repository rend le dernier catalogue connu, et
        // l'utilisateur continue de saisir sa réserve.
        status: state.items.isEmpty ? CorpsEtatStatus.erreur : CorpsEtatStatus.succes,
        erreur: failure.errorMessage,
      )),
      (liste) => emit(CorpsEtatState(
        status: liste.isEmpty ? CorpsEtatStatus.vide : CorpsEtatStatus.succes,
        items: liste,
      )),
    );
  }

  /// Rechargement explicite — utilisé par le bouton « Réessayer ».
  Future<void> rafraichir() => charger();
}
