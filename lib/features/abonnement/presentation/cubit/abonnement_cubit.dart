import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/entities/abonnement.dart';
import '../../domain/usecases/creer_code_transfert_web.dart';
import '../../domain/usecases/get_droits.dart';
import '../../domain/usecases/get_etat_paiement.dart';
import '../../domain/usecases/get_formules.dart';
import '../../domain/usecases/get_historique_abonnement.dart';

enum AbonnementStatus { initial, chargement, succes, erreur }

/// Où en est la VÉRIFICATION d'un paiement, au retour du navigateur.
///
/// Ce n'est pas le statut du paiement lui-même — celui-là appartient au
/// serveur (`EtatPaiement`) — mais ce que l'écran doit montrer pendant et
/// après l'avoir interrogé :
///
///  - [enCours] : « Vérification du paiement… », le serveur est interrogé ;
///  - [confirme] : le serveur porte la formule payée, ACTIVE ;
///  - [enAttente] : le serveur ne l'a pas encore confirmée après les essais —
///    on le dit tel quel, sans promettre ni alarmer ;
///  - [echec] / [annule] : ce que le serveur sait du paiement ;
///  - [reseau] : impossible de joindre le serveur.
enum VerificationPaiement { aucune, enCours, confirme, enAttente, echec, annule, reseau }

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

  /// Vérification du paiement en cours ou son verdict — voir
  /// [VerificationPaiement]. Revient à [VerificationPaiement.aucune] dès que
  /// l'écran l'a montré ([AbonnementCubit.effacerVerification]).
  final VerificationPaiement verification;

  /// Nom de la formule dont le paiement vient d'être confirmé — pour le
  /// message. Nul sinon.
  final String? formuleConfirmee;

  const AbonnementState({
    this.status = AbonnementStatus.initial,
    this.formules = const [],
    this.droits = const DroitsAbonnement(),
    this.historique = const [],
    this.historiqueDemande = false,
    this.erreur,
    this.verification = VerificationPaiement.aucune,
    this.formuleConfirmee,
  });

  AbonnementState copyWith({
    AbonnementStatus? status,
    List<FormuleAbonnement>? formules,
    DroitsAbonnement? droits,
    List<SouscriptionHistorique>? historique,
    bool? historiqueDemande,
    String? erreur,
    VerificationPaiement? verification,
    String? formuleConfirmee,
  }) {
    return AbonnementState(
      status: status ?? this.status,
      formules: formules ?? this.formules,
      droits: droits ?? this.droits,
      historique: historique ?? this.historique,
      historiqueDemande: historiqueDemande ?? this.historiqueDemande,
      erreur: erreur,
      verification: verification ?? this.verification,
      formuleConfirmee: formuleConfirmee ?? this.formuleConfirmee,
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
      [status, formules, droits, historique, historiqueDemande, erreur, verification, formuleConfirmee];
}

/// Écran d'abonnement du mobile.
///
/// Les appels sont INDÉPENDANTS : le catalogue est public, les droits et
/// l'historique demandent une session. Les enchaîner ferait perdre l'affichage
/// des offres à une organisation dont l'essai est terminé — précisément celle
/// qui a besoin de les voir.
class AbonnementCubit extends Cubit<AbonnementState> {
  /// Attentes entre deux interrogations du serveur au retour de Stripe.
  ///
  /// Le webhook arrive en général dans la seconde ; les paliers suivants
  /// couvrent un Stripe lent ou un serveur occupé — une vingtaine de
  /// secondes en tout, après quoi on cesse SANS conclure.
  static const List<Duration> attentesVerification = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 4),
    Duration(seconds: 5),
    Duration(seconds: 7),
  ];

  final GetFormules getFormules;
  final GetDroits getDroits;
  final GetHistoriqueAbonnement getHistorique;
  final CreerCodeTransfertWeb creerCodeTransfertWeb;
  final GetEtatPaiement getEtatPaiement;

  /// Injectable dans les tests : attendre vingt secondes réelles n'y apporte
  /// rien.
  final Future<void> Function(Duration) dormir;

  AbonnementCubit({
    required this.getFormules,
    required this.getDroits,
    required this.getHistorique,
    required this.creerCodeTransfertWeb,
    required this.getEtatPaiement,
    Future<void> Function(Duration)? dormir,
  })  : dormir = dormir ?? Future.delayed,
        super(const AbonnementState());

  /// Code de transfert de session pour la page de paiement du web.
  ///
  /// Hors de l'état de l'écran : c'est une action ponctuelle, dont seul le
  /// bouton qui l'a déclenchée attend le résultat.
  Future<Either<Failure, String>> preparerPaiementWeb() => creerCodeTransfertWeb();

  /// Référence du dernier paiement connu AVANT d'ouvrir le navigateur.
  ///
  /// C'est ce qui permet, au retour, de distinguer le paiement qui vient
  /// d'être engagé de celui d'hier — sans comparer d'horloges, celle d'un
  /// téléphone de chantier étant souvent fausse. Nulle si le serveur n'a pas
  /// répondu : on acceptera alors n'importe quel paiement au retour.
  Future<String?> referenceAvantPaiement() async {
    final res = await getEtatPaiement();
    return res.fold((_) => null, (etat) => etat?.reference);
  }

  /// Vérifie, au retour du navigateur, ce que le SERVEUR sait du paiement.
  ///
  /// Ni le retour dans l'application, ni la page de succès de Stripe ne
  /// prouvent quoi que ce soit : le serveur est interrogé jusqu'à ce que le
  /// webhook ait tranché, ou jusqu'au bout des [attentesVerification]. Les
  /// droits sont rechargés quoi qu'il arrive — c'est avec eux que l'écran se
  /// redessine, et une formule activée doit remplacer l'essai SANS que
  /// l'utilisateur ait à quitter l'écran.
  ///
  /// [formuleCode] : la formule choisie. Un paiement d'une AUTRE formule
  /// (deux onglets, un collègue) n'est pas confondu avec celui-ci.
  /// [referenceAvant] : voir [referenceAvantPaiement].
  Future<void> verifierPaiement({
    required String formuleCode,
    String? referenceAvant,
    bool avecHistorique = false,
  }) async {
    emit(state.copyWith(verification: VerificationPaiement.enCours));

    var verdict = VerificationPaiement.enAttente;
    String? formuleNom;
    var reseau = false;

    for (final attente in attentesVerification) {
      if (attente > Duration.zero) await dormir(attente);
      if (isClosed) return;

      final res = await getEtatPaiement();
      if (isClosed) return;

      final fini = res.fold(
        (echec) {
          reseau = echec is NetworkFailure;
          return false;
        },
        (etat) {
          reseau = false;
          // Aucun paiement engagé, ou toujours celui d'avant : le webhook
          // n'a rien écrit de nouveau, on réessaie.
          if (etat == null) return false;
          if (referenceAvant != null && etat.reference == referenceAvant) return false;
          if (etat.planCode != null && etat.planCode != formuleCode) return false;

          switch (etat.statut) {
            case StatutPaiement.active:
              verdict = VerificationPaiement.confirme;
              formuleNom = etat.planNom;
              return true;
            case StatutPaiement.echec:
              verdict = VerificationPaiement.echec;
              return true;
            case StatutPaiement.annulee:
            case StatutPaiement.expiree:
              verdict = VerificationPaiement.annule;
              return true;
            case StatutPaiement.enAttente:
            case StatutPaiement.inconnu:
              return false;
          }
        },
      );
      if (fini) break;
    }

    if (verdict == VerificationPaiement.enAttente && reseau) verdict = VerificationPaiement.reseau;

    // Les droits d'abord : l'écran doit déjà montrer la nouvelle formule
    // quand le message de confirmation s'affiche.
    await charger(avecHistorique: avecHistorique);
    if (isClosed) return;

    // Le serveur porte la formule payée alors que le paiement n'a pas été
    // retrouvé (référence d'avant inconnue, paiement d'un autre parcours) :
    // les DROITS font foi, c'est bien confirmé.
    if (verdict != VerificationPaiement.confirme
        && state.droits.source == 'abonnement'
        && state.droits.planCode == formuleCode
        && verdict != VerificationPaiement.echec) {
      verdict = VerificationPaiement.confirme;
      formuleNom = state.droits.planNom;
    }

    emit(state.copyWith(
      verification: verdict,
      formuleConfirmee: verdict == VerificationPaiement.confirme ? (formuleNom ?? formuleCode) : null,
    ));
  }

  /// L'écran a montré le verdict : on l'efface pour ne pas le remontrer à la
  /// prochaine reconstruction.
  void effacerVerification() {
    if (state.verification == VerificationPaiement.aucune) return;
    emit(state.copyWith(verification: VerificationPaiement.aucune));
  }

  /// [avecHistorique] : à `true` seulement pour les rôles autorisés à voir la
  /// facturation (`peutGererAbonnement`, miroir du groupe FACTURATION qui garde
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
