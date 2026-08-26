import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/organisation.dart';
import '../../domain/usecases/get_mon_organisation.dart';
import '../../domain/usecases/modifier_organisation.dart';

enum MonOrganisationStatus { initial, chargement, succes, erreur }

class MonOrganisationState {
  final MonOrganisationStatus status;
  final Organisation? organisation;
  final String? erreur;

  const MonOrganisationState({
    this.status = MonOrganisationStatus.initial,
    this.organisation,
    this.erreur,
  });

  MonOrganisationState copyWith({
    MonOrganisationStatus? status,
    Organisation? organisation,
    String? erreur,
  }) =>
      MonOrganisationState(
        status: status ?? this.status,
        organisation: organisation ?? this.organisation,
        erreur: erreur,
      );
}

/// Organisation de l'utilisateur connecté, pour la fiche de profil.
///
/// L'échec est NON BLOQUANT : la fiche affiche d'abord les informations
/// personnelles, qui viennent de `AuthBloc` et sont déjà en mémoire. Un
/// compte sans organisation (ou une panne de ce seul appel) ne doit pas
/// priver l'utilisateur de son propre profil — la section « Entreprise »
/// se contente alors de disparaître.
class MonOrganisationCubit extends Cubit<MonOrganisationState> {
  final GetMonOrganisation getMonOrganisation;
  final ModifierOrganisation modifierOrganisationUsecase;

  MonOrganisationCubit({
    required this.getMonOrganisation,
    required this.modifierOrganisationUsecase,
  }) : super(const MonOrganisationState());

  Future<void> charger() async {
    emit(state.copyWith(status: MonOrganisationStatus.chargement));
    final result = await getMonOrganisation();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(
        status: MonOrganisationStatus.erreur,
        erreur: failure.errorMessage,
      )),
      (organisation) => emit(MonOrganisationState(
        status: MonOrganisationStatus.succes,
        organisation: organisation,
      )),
    );
  }

  /// Retourne `null` en cas de succès, le message d'erreur sinon — la feuille
  /// d'édition en a besoin pour rester ouverte et afficher le motif du refus
  /// (403 si le rôle n'est pas GESTION, validation Joi, etc.).
  Future<String?> enregistrer({
    String? nom,
    String? raisonSociale,
    String? siret,
    String? numTva,
    String? rccm,
    String? ninea,
    String? telephone,
    String? email,
    String? adresse,
    String? ville,
    String? pays,
  }) async {
    final result = await modifierOrganisationUsecase(
      nom: nom,
      raisonSociale: raisonSociale,
      siret: siret,
      numTva: numTva,
      rccm: rccm,
      ninea: ninea,
      telephone: telephone,
      email: email,
      adresse: adresse,
      ville: ville,
      pays: pays,
    );
    if (isClosed) return null;
    return result.fold(
      (failure) => failure.errorMessage,
      (organisation) {
        emit(MonOrganisationState(
          status: MonOrganisationStatus.succes,
          organisation: organisation,
        ));
        return null;
      },
    );
  }
}
