import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../organisation/domain/entities/membre.dart';
import '../../../organisation/domain/usecases/get_membres.dart';
import '../../domain/entities/chantier.dart';
import '../../domain/usecases/creer_chantier.dart';

enum CreerChantierStatus { saisie, envoi, succes, erreur }

class CreerChantierState extends Equatable {
  final CreerChantierStatus status;

  /// Membres proposés comme responsable. Vide tant que la liste n'est pas
  /// revenue — le champ reste alors simplement absent.
  final List<Membre> membres;

  final String? erreur;
  final Chantier? cree;

  const CreerChantierState({
    this.status = CreerChantierStatus.saisie,
    this.membres = const [],
    this.erreur,
    this.cree,
  });

  CreerChantierState copyWith({
    CreerChantierStatus? status,
    List<Membre>? membres,
    String? erreur,
    Chantier? cree,
    bool effacerErreur = false,
  }) {
    return CreerChantierState(
      status: status ?? this.status,
      membres: membres ?? this.membres,
      erreur: effacerErreur ? null : (erreur ?? this.erreur),
      cree: cree ?? this.cree,
    );
  }

  @override
  List<Object?> get props => [status, membres, erreur, cree];
}

/// Demande de création d'un chantier depuis le mobile.
///
/// Le résultat n'est pas un chantier utilisable mais une DEMANDE : le serveur
/// met en attente tout chantier créé par un compte autre que le super-admin
/// plateforme. Le mobile ne décide de rien — il envoie et affiche le statut
/// que le serveur renvoie.
class CreerChantierCubit extends Cubit<CreerChantierState> {
  final CreerChantier creerChantier;
  final GetMembres getMembres;

  CreerChantierCubit({required this.creerChantier, required this.getMembres})
      : super(const CreerChantierState());

  /// Charge les responsables possibles.
  ///
  /// Un échec est SILENCIEUX : le responsable est facultatif, et barrer le
  /// formulaire d'un message d'erreur empêcherait de déposer une demande pour
  /// un champ dont on peut se passer.
  Future<void> chargerMembres() async {
    final result = await getMembres();
    if (isClosed) return;
    result.fold((_) {}, (membres) => emit(state.copyWith(membres: membres)));
  }

  Future<void> envoyer({
    required String nom,
    String? code,
    String? adresse,
    String? description,
    double? latitude,
    double? longitude,
    DateTime? dateDebut,
    DateTime? dateFin,
    num? budget,
    String? responsableId,
  }) async {
    if (state.status == CreerChantierStatus.envoi) return;
    emit(state.copyWith(status: CreerChantierStatus.envoi, effacerErreur: true));

    final result = await creerChantier(
      nom: nom,
      code: code,
      adresse: adresse,
      description: description,
      latitude: latitude,
      longitude: longitude,
      dateDebut: dateDebut,
      dateFin: dateFin,
      budget: budget,
      responsableId: responsableId,
    );
    if (isClosed) return;

    result.fold(
      (echec) => emit(state.copyWith(
        status: CreerChantierStatus.erreur,
        erreur: echec.errorMessage,
      )),
      (chantier) => emit(state.copyWith(
        status: CreerChantierStatus.succes,
        cree: chantier,
      )),
    );
  }
}
