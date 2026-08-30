import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/type_referentiel.dart';
import '../../domain/usecases/get_types_actifs.dart';

enum TypesStatus { initial, chargement, succes, vide, erreur }

/// État d'un référentiel de types.
///
/// [TypesStatus.vide] est distinct de [TypesStatus.succes] : un référentiel
/// vide n'est pas une erreur, mais il appelle un message différent
/// (« aucun type au référentiel », qui invite à en ajouter côté web) d'une
/// liste chargée. Les confondre afficherait un sélecteur muet sans que
/// l'utilisateur comprenne pourquoi.
class TypesReferentielState extends Equatable {
  final TypesStatus status;
  final List<TypeReferentiel> items;
  final String? erreur;

  const TypesReferentielState({
    this.status = TypesStatus.initial,
    this.items = const [],
    this.erreur,
  });

  TypesReferentielState copyWith({
    TypesStatus? status,
    List<TypeReferentiel>? items,
    String? erreur,
  }) {
    return TypesReferentielState(
      status: status ?? this.status,
      items: items ?? this.items,
      erreur: erreur,
    );
  }

  /// Vrai quand la liste est exploitable par un sélecteur.
  bool get pretPourSelection => status == TypesStatus.succes && items.isNotEmpty;

  /// Libellé d'un code, ou le code lui-même à défaut.
  ///
  /// Le repli sur le code compte : un enregistrement peut porter un type
  /// DÉSACTIVÉ depuis, absent de cette liste. Afficher un vide laisserait
  /// croire que la donnée est incomplète.
  String libelle(String? code) {
    if (code == null || code.isEmpty) return '';
    for (final t in items) {
      if (t.code == code) return t.nom;
    }
    return code;
  }

  @override
  List<Object?> get props => [status, items, erreur];
}

/// Charge les types ACTIFS d'un référentiel administrable.
///
/// Un cubit par référentiel : les trois listes sont indépendantes, et les
/// réunir obligerait à charger les trois pour en afficher une.
class TypesReferentielCubit extends Cubit<TypesReferentielState> {
  final GetTypesActifs getTypesActifs;
  final ReferentielType referentiel;

  TypesReferentielCubit({
    required this.getTypesActifs,
    required this.referentiel,
  }) : super(const TypesReferentielState());

  Future<void> charger() async {
    // Déjà chargé : le repository garde un cache de session, mais ré-émettre
    // `chargement` ferait clignoter le sélecteur à chaque réouverture.
    if (state.items.isNotEmpty) return;

    emit(state.copyWith(status: TypesStatus.chargement));

    final resultat = await getTypesActifs(referentiel);
    if (isClosed) return;

    emit(resultat.fold(
      (echec) => state.copyWith(status: TypesStatus.erreur, erreur: echec.errorMessage),
      (liste) => state.copyWith(
        status: liste.isEmpty ? TypesStatus.vide : TypesStatus.succes,
        items: liste,
      ),
    ));
  }
}
