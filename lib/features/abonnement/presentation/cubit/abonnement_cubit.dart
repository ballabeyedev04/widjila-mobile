import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/abonnement.dart';
import '../../domain/usecases/get_droits.dart';
import '../../domain/usecases/get_formules.dart';
import '../../domain/usecases/get_historique_abonnement.dart';

enum AbonnementStatus { initial, chargement, succes, erreur }

class AbonnementState extends Equatable {
  final AbonnementStatus status;
  final List<FormuleAbonnement> formules;
  final DroitsAbonnement droits;

  /// Souscriptions passées, de la plus récente à la plus ancienne.
  ///
  /// Vide tant que l'historique n'a pas été demandé — ce qui est le cas pour
  /// les rôles qui n'y ont pas droit. Ne pas confondre avec « aucun achat » :
  /// c'est [historiqueDemande] qui fait la différence.
  final List<SouscriptionHistorique> historique;

  /// Vrai si l'historique a été RÉCLAMÉ au serveur pendant ce chargement.
  final bool historiqueDemande;

  final String? erreur;

  const AbonnementState({
    this.status = AbonnementStatus.initial,
    this.formules = const [],
    this.droits = const DroitsAbonnement(),
    this.historique = const [],
    this.historiqueDemande = false,
    this.erreur,
  });

  AbonnementState copyWith({
    AbonnementStatus? status,
    List<FormuleAbonnement>? formules,
    DroitsAbonnement? droits,
    List<SouscriptionHistorique>? historique,
    bool? historiqueDemande,
    String? erreur,
  }) {
    return AbonnementState(
      status: status ?? this.status,
      formules: formules ?? this.formules,
      droits: droits ?? this.droits,
      historique: historique ?? this.historique,
      historiqueDemande: historiqueDemande ?? this.historiqueDemande,
      erreur: erreur,
    );
  }

  /// Total réellement dépensé — seules les souscriptions que le SERVEUR
  /// reconnaît comme payées y entrent.
  ///
  /// Une souscription `en_attente` est un parcours engagé dont le paiement
  /// n'a jamais été confirmé : la compter gonflerait le total d'un montant
  /// que personne n'a versé.
  double get totalPaye => historique
      .where((s) => s.estPayee)
      .fold(0, (somme, s) => somme + (s.prixPaye ?? 0));

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
  List<Object?> get props =>
      [status, formules, droits, historique, historiqueDemande, erreur];
}

/// Écran d'abonnement du mobile.
///
/// Les appels sont INDÉPENDANTS : le catalogue est public, les droits et
/// l'historique demandent une session. Les enchaîner ferait perdre l'affichage
/// des offres à une organisation dont l'essai est terminé — précisément celle
/// qui a besoin de les voir.
class AbonnementCubit extends Cubit<AbonnementState> {
  final GetFormules getFormules;
  final GetDroits getDroits;
  final GetHistoriqueAbonnement getHistorique;

  AbonnementCubit({
    required this.getFormules,
    required this.getDroits,
    required this.getHistorique,
  }) : super(const AbonnementState());

  /// [avecHistorique] : à `true` seulement pour les rôles autorisés à voir la
  /// facturation (`peutGererOrganisation`, miroir du groupe GESTION qui garde
  /// la route). Le demander pour les autres ne produirait qu'un 403, une
  /// requête perdue et un message d'erreur trompeur sur un écran par ailleurs
  /// parfaitement utilisable.
  Future<void> charger({bool avecHistorique = false}) async {
    if (state.formules.isEmpty) {
      emit(state.copyWith(status: AbonnementStatus.chargement));
    }

    // Les trois appels partent ENSEMBLE : ils ne dépendent pas les uns des
    // autres, et l'écran n'est complet qu'avec les trois.
    final resultats = await Future.wait([
      getFormules(),
      getDroits(),
      if (avecHistorique) getHistorique(),
    ]);
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

    // Un historique en échec ne fait rien échouer : on garde la liste
    // précédente et l'écran reste utile. Refuser d'afficher la formule en
    // cours parce que la facturation n'a pas répondu serait disproportionné.
    final historique = avecHistorique
        ? resultats[2].fold<List<SouscriptionHistorique>>(
            (_) => state.historique,
            (liste) => liste as List<SouscriptionHistorique>,
          )
        : state.historique;

    emit(state.copyWith(
      status: catalogueEnEchec ? AbonnementStatus.erreur : AbonnementStatus.succes,
      formules: formules,
      droits: droits,
      historique: historique,
      historiqueDemande: avecHistorique,
      erreur: catalogueEnEchec
          ? resultats[0].fold((f) => f.errorMessage, (_) => null)
          : null,
    ));
  }
}
