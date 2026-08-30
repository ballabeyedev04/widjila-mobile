import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/abonnement.dart';
import '../../domain/usecases/get_droits.dart';
import '../../domain/usecases/get_formules.dart';

enum AbonnementStatus { initial, chargement, succes, erreur }

class AbonnementState extends Equatable {
  final AbonnementStatus status;
  final List<FormuleAbonnement> formules;
  final DroitsAbonnement droits;
  final String? erreur;

  const AbonnementState({
    this.status = AbonnementStatus.initial,
    this.formules = const [],
    this.droits = const DroitsAbonnement(),
    this.erreur,
  });

  AbonnementState copyWith({
    AbonnementStatus? status,
    List<FormuleAbonnement>? formules,
    DroitsAbonnement? droits,
    String? erreur,
  }) {
    return AbonnementState(
      status: status ?? this.status,
      formules: formules ?? this.formules,
      droits: droits ?? this.droits,
      erreur: erreur,
    );
  }

  /// Formule actuellement souscrite, retrouvée dans le catalogue par son CODE.
  ///
  /// Par le code et non par le nom : l'administrateur peut renommer une
  /// formule, le code ne bouge pas.
  FormuleAbonnement? get formuleActuelle {
    final code = droits.planCode;
    if (code == null) return null;
    for (final f in formules) {
      if (f.code == code) return f;
    }
    return null;
  }

  @override
  List<Object?> get props => [status, formules, droits, erreur];
}

/// Écran d'abonnement du mobile.
///
/// Les deux appels sont INDÉPENDANTS : le catalogue est public, les droits
/// demandent une session. Les enchaîner ferait perdre l'affichage des offres à
/// une organisation dont l'essai est terminé — précisément celle qui a besoin
/// de les voir.
class AbonnementCubit extends Cubit<AbonnementState> {
  final GetFormules getFormules;
  final GetDroits getDroits;

  AbonnementCubit({required this.getFormules, required this.getDroits})
      : super(const AbonnementState());

  Future<void> charger() async {
    if (state.formules.isEmpty) {
      emit(state.copyWith(status: AbonnementStatus.chargement));
    }

    final resultats = await Future.wait([getFormules(), getDroits()]);
    if (isClosed) return;

    final formules = resultats[0].fold<List<FormuleAbonnement>>(
      (_) => state.formules,
      (liste) => liste as List<FormuleAbonnement>,
    );
    final droits = resultats[1].fold<DroitsAbonnement>(
      (_) => state.droits,
      (d) => d as DroitsAbonnement,
    );

    // On n'échoue que si le CATALOGUE manque : sans droits, l'écran reste
    // utile — il montre les offres.
    final catalogueEnEchec = resultats[0].isLeft() && formules.isEmpty;

    emit(state.copyWith(
      status: catalogueEnEchec ? AbonnementStatus.erreur : AbonnementStatus.succes,
      formules: formules,
      droits: droits,
      erreur: catalogueEnEchec
          ? resultats[0].fold((f) => f.errorMessage, (_) => null)
          : null,
    ));
  }
}
