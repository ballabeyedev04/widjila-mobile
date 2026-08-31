import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../plan/domain/usecases/uploader_plan.dart';
import '../../domain/entities/chantier.dart';
import '../../domain/usecases/creer_chantier.dart';

/// Un plan choisi, pas encore envoyé.
class PlanAJoindre extends Equatable {
  final String chemin;
  final String nom;

  const PlanAJoindre({required this.chemin, required this.nom});

  @override
  List<Object?> get props => [chemin, nom];
}

enum EnvoiPlanStatus { saisie, envoi, succes, erreur }

class EnvoiPlanState extends Equatable {
  final EnvoiPlanStatus status;
  final List<PlanAJoindre> plans;
  final String? erreur;

  /// La demande a été enregistrée, mais tous ses plans ne sont pas partis.
  ///
  /// Distinct d'un échec : la demande EXISTE, et la présenter comme perdue
  /// pousserait le demandeur à la déposer une deuxième fois.
  final List<String> plansEnEchec;

  /// Chantier créé — permet à l'écran de renvoyer vers la demande.
  final Chantier? demande;

  const EnvoiPlanState({
    this.status = EnvoiPlanStatus.saisie,
    this.plans = const [],
    this.erreur,
    this.plansEnEchec = const [],
    this.demande,
  });

  EnvoiPlanState copyWith({
    EnvoiPlanStatus? status,
    List<PlanAJoindre>? plans,
    String? erreur,
    List<String>? plansEnEchec,
    Chantier? demande,
    bool effacerErreur = false,
  }) {
    return EnvoiPlanState(
      status: status ?? this.status,
      plans: plans ?? this.plans,
      erreur: effacerErreur ? null : (erreur ?? this.erreur),
      plansEnEchec: plansEnEchec ?? this.plansEnEchec,
      demande: demande ?? this.demande,
    );
  }

  @override
  List<Object?> get props => [status, plans, erreur, plansEnEchec, demande];
}

/// Parcours « Envoi Plan » : décrire le chantier, y joindre ses plans, envoyer.
///
/// L'ordre est imposé par le serveur : un plan appartient à un chantier, il
/// n'existe pas de plan orphelin. La demande est donc créée d'abord, les plans
/// déposés ensuite.
///
/// Conséquence assumée : si un plan échoue, la demande reste. C'est le bon
/// compromis — elle porte le nom, l'adresse et la description déjà saisis, et
/// les plans manquants se rejoignent depuis la demande. L'inverse (tout
/// annuler) ferait tout ressaisir pour un fichier trop lourd.
class EnvoiPlanCubit extends Cubit<EnvoiPlanState> {
  final CreerChantier creerChantier;
  final UploaderPlan uploaderPlan;

  EnvoiPlanCubit({required this.creerChantier, required this.uploaderPlan})
      : super(const EnvoiPlanState());

  void ajouter(PlanAJoindre plan) {
    // Le même fichier deux fois produirait deux versions du même plan côté
    // serveur, sans que rien à l'écran ne l'ait laissé prévoir.
    if (state.plans.any((p) => p.chemin == plan.chemin)) return;
    emit(state.copyWith(plans: [...state.plans, plan], effacerErreur: true));
  }

  void retirer(PlanAJoindre plan) {
    emit(state.copyWith(plans: state.plans.where((p) => p != plan).toList()));
  }

  Future<void> envoyer({
    required String nom,
    String? adresse,
    String? description,
  }) async {
    if (state.status == EnvoiPlanStatus.envoi) return;
    emit(state.copyWith(status: EnvoiPlanStatus.envoi, effacerErreur: true, plansEnEchec: const []));

    final creation = await creerChantier(nom: nom, adresse: adresse, description: description);
    if (isClosed) return;

    final chantier = creation.fold((echec) {
      emit(state.copyWith(status: EnvoiPlanStatus.erreur, erreur: echec.errorMessage));
      return null;
    }, (c) => c);
    if (chantier == null) return;

    // Les plans partent UN PAR UN, et non en parallèle : sur un réseau de
    // chantier, plusieurs envois simultanés de fichiers lourds se gênent et
    // finissent en délai dépassé.
    final echecs = <String>[];
    for (final plan in state.plans) {
      final result = await uploaderPlan(
        chantierId: chantier.id,
        cheminFichier: plan.chemin,
        nom: plan.nom,
      );
      if (isClosed) return;
      result.fold((_) => echecs.add(plan.nom), (_) {});
    }

    emit(state.copyWith(
      status: EnvoiPlanStatus.succes,
      demande: chantier,
      plansEnEchec: echecs,
    ));
  }
}
