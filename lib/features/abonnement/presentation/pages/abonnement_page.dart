import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/env.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/config/user_role.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/abonnement.dart';
import '../cubit/abonnement_cubit.dart';
import '../../../../core/network/forcer_reseau.dart';
import '../../../../core/routes/retour.dart';

/// Écran d'abonnement du mobile.
///
/// ── Ce qu'il fait, et ce qu'il ne fait pas ────────────────────────────────
/// Il AFFICHE les offres, la formule en cours et la consommation face aux
/// limites. Il ne DÉCIDE de rien : prix, droits et limites viennent tous du
/// serveur, qui reste seul juge.
///
/// ── Pourquoi le paiement passe par le web ─────────────────────────────────
/// CHOIX ARRÊTÉ PAR LE CLIENT : le mobile n'encaisse pas de carte lui-même, il
/// ouvre la page d'abonnement de l'admin web dans le navigateur, où
/// l'intégration Stripe est déjà en place et testée.
///
/// Ce n'est donc pas un repli à revoir : `flutter_stripe` (module à code
/// natif) n'a pas à être ajouté. Le seul point d'attention reste
/// [Env.abonnementUrl], qui doit pointer sur le domaine de l'INTERFACE
/// (`app.*`) et non sur celui de l'API (`api.*`).
class AbonnementPage extends StatelessWidget {
  const AbonnementPage({super.key});

  @override
  Widget build(BuildContext context) {
    // La facturation est gardée par le groupe GESTION côté serveur
    // (`subscription.route.js`). `peutGererOrganisation` en est le miroir
    // exact : la demander pour un autre rôle ne produirait qu'un 403 et un
    // message d'erreur sur un écran par ailleurs utilisable.
    final voitLaFacturation = context.read<AuthBloc>().state.utilisateur?.role
            .peutGererOrganisation ??
        false;

    return BlocProvider(
      create: (_) => sl<AbonnementCubit>()..charger(avecHistorique: voitLaFacturation),
      child: _AbonnementView(voitLaFacturation: voitLaFacturation),
    );
  }
}

class _AbonnementView extends StatefulWidget {
  final bool voitLaFacturation;

  const _AbonnementView({required this.voitLaFacturation});

  @override
  State<_AbonnementView> createState() => _AbonnementViewState();
}

class _AbonnementViewState extends State<_AbonnementView> with WidgetsBindingObserver {
  /// Vrai entre l'ouverture du navigateur et le retour dans l'application.
  ///
  /// Conditionne le rechargement au retour au premier plan : sans lui, chaque
  /// passage en arrière-plan — notification, appel reçu, changement
  /// d'application — relancerait deux requêtes réseau pour rien.
  bool _paiementLance = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Recharge l'abonnement au retour du navigateur.
  ///
  /// Le paiement est confirmé par le WEBHOOK Stripe, côté serveur : rien ne
  /// prévient l'application. Sans ce rechargement, l'utilisateur qui vient de
  /// payer revenait sur un écran affichant encore son ancienne formule.
  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (etat != AppLifecycleState.resumed || !_paiementLance) return;
    _paiementLance = false;
    if (!mounted) return;
    context.read<AbonnementCubit>().charger(avecHistorique: widget.voitLaFacturation);
  }

  /// Ouvre la page d'abonnement du web — voir l'en-tête pour le raisonnement.
  Future<void> _ouvrirPaiement(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final uri = Uri.tryParse(Env.abonnementUrl);
    if (uri == null) return;

    final ouvert = await launchUrl(uri, mode: LaunchMode.externalApplication);
    // Armé seulement si le navigateur s'est RÉELLEMENT ouvert : un échec
    // d'ouverture ne fait pas quitter l'application, donc aucun retour à
    // guetter.
    _paiementLance = ouvert;

    if (!ouvert) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.abonnementOuvertureImpossible)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.abonnementTitre),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.retourVers(),
        ),
      ),
      body: BlocBuilder<AbonnementCubit, AbonnementState>(
        builder: (context, state) {
          if (state.status == AbonnementStatus.chargement) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (state.status == AbonnementStatus.erreur) {
            return ErrorView(
              message: state.erreur ?? l10n.commonErrorUnknown,
              onRetry: () =>
                  context.read<AbonnementCubit>().charger(avecHistorique: widget.voitLaFacturation),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: forcerReseau(
              () => context.read<AbonnementCubit>().charger(avecHistorique: widget.voitLaFacturation),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _CarteEtat(droits: state.droits, formule: state.formuleActuelle),

                if (widget.voitLaFacturation) ...[
                  const SizedBox(height: 18),
                  _SectionHistorique(lignes: state.historique, totalPaye: state.totalPaye),
                ],

                const SizedBox(height: 18),
                Text(
                  l10n.abonnementNosFormules,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                for (final formule in state.formules) ...[
                  _CarteFormule(
                    formule: formule,
                    actuelle: formule.code == state.droits.planCode,
                    onChoisir: () => _ouvrirPaiement(context),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Formule en cours et consommation face aux limites.
class _CarteEtat extends StatelessWidget {
  final DroitsAbonnement droits;
  final FormuleAbonnement? formule;

  const _CarteEtat({required this.droits, this.formule});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final (titre, couleur) = switch (droits.source) {
      'abonnement' => (droits.planNom ?? l10n.abonnementActif, AppColors.success),
      'essai' => (l10n.abonnementEssaiEnCours, AppColors.warning),
      _ => (l10n.abonnementAucun, AppColors.danger),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: couleur, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.abonnementVotreFormule,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 3),
          Text(
            titre,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: couleur),
          ),

          if (droits.dateFin != null) ...[
            const SizedBox(height: 4),
            Text(
              droits.essaiEnCours
                  ? l10n.abonnementEssaiJusquau(_date(droits.dateFin!))
                  : l10n.abonnementRenouvellement(_date(droits.dateFin!)),
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],

          // Compte à rebours — la valeur vient du SERVEUR (`joursRestants`),
          // jamais d'un calcul local : l'horloge d'un téléphone de chantier
          // est souvent fausse de plusieurs jours, et c'est sur ce chiffre
          // que se prend la décision de renouveler.
          if (droits.joursRestants != null) ...[
            const SizedBox(height: 10),
            _Pastille(
              texte: droits.joursRestants == 0
                  ? l10n.abonnementDernierJour
                  : l10n.abonnementJoursRestants(droits.joursRestants!),
              // Sous une semaine, la pastille passe à la couleur d'alerte :
              // prévenir avant la coupure vaut mieux que la constater.
              couleur: droits.joursRestants! <= 7 ? AppColors.danger : couleur,
            ),
          ],

          const SizedBox(height: 14),
          _LigneUsage(
            libelle: l10n.abonnementUtilisateurs,
            usage: droits.utilisateurs,
            illimiteTexte: l10n.abonnementIllimite,
          ),
          const SizedBox(height: 8),
          _LigneUsage(
            libelle: l10n.abonnementChantiers,
            usage: droits.chantiers,
            illimiteTexte: l10n.abonnementIllimite,
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// « 4 / 5 utilisateurs », avec une barre qui vire au rouge à l'approche du
/// plafond — prévenir avant le refus vaut mieux que le subir.
class _LigneUsage extends StatelessWidget {
  final String libelle;
  final UsageRessource usage;
  final String illimiteTexte;

  const _LigneUsage({required this.libelle, required this.usage, required this.illimiteTexte});

  @override
  Widget build(BuildContext context) {
    final ratio = usage.illimite ? 0.0 : (usage.courant / usage.limite!).clamp(0.0, 1.0);
    final couleur = usage.atteint
        ? AppColors.danger
        : ratio > 0.8
            ? AppColors.warning
            : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(libelle, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            Text(
              usage.illimite ? '${usage.courant} · $illimiteTexte' : '${usage.courant} / ${usage.limite}',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: couleur),
            ),
          ],
        ),
        if (!usage.illimite) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(couleur),
            ),
          ),
        ],
      ],
    );
  }
}

/// Une formule du catalogue.
class _CarteFormule extends StatelessWidget {
  final FormuleAbonnement formule;
  final bool actuelle;
  final VoidCallback onChoisir;

  const _CarteFormule({required this.formule, required this.actuelle, required this.onChoisir});

  /// Libellé d'un code de fonctionnalité, traduit côté client.
  String _libelle(BuildContext context, String code) {
    final l10n = context.l10n;
    return switch (code) {
      'reserves' => l10n.abonnementFReserves,
      'mobile' => l10n.abonnementFMobile,
      'stockage' => l10n.abonnementFStockage,
      'support_prioritaire' => l10n.abonnementFSupport,
      'suivi_equipe' => l10n.abonnementFEquipe,
      'rapports' => l10n.abonnementFRapports,
      'annotations' => l10n.abonnementFAnnotations,
      'api' => l10n.abonnementFApi,
      // Un code ajouté côté serveur mais inconnu ici s'affiche brut plutôt que
      // de disparaître : mieux vaut un libellé technique qu'une offre amputée.
      _ => code,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: actuelle ? AppColors.primary : AppColors.border,
          width: actuelle ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formule.nom,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (actuelle)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l10n.abonnementFormuleActuelle,
                    style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primaryDark,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 6),
          // « Sur devis » n'est pas un montant : l'afficher comme un prix, ou
          // pire comme 0, tromperait sur l'offre.
          Text(
            formule.surDevis
                ? l10n.abonnementSurDevis
                : '${formule.prix?.toStringAsFixed(0)} ${formule.devise}'
                    ' ${formule.periode == 'an' ? l10n.abonnementParAn : l10n.abonnementParMois}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: formule.surDevis ? 18 : 24,
              color: AppColors.primary,
            ),
          ),

          if (formule.description != null) ...[
            const SizedBox(height: 6),
            Text(
              formule.description!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
            ),
          ],

          const SizedBox(height: 12),
          Text(
            formule.limiteUtilisateurs == null
                ? l10n.abonnementUtilisateursIllimites
                : l10n.abonnementUtilisateursMax(formule.limiteUtilisateurs!),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),

          const SizedBox(height: 10),
          for (final code in formule.fonctionnalites)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_rounded, size: 15, color: AppColors.success),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _libelle(context, code),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: actuelle ? AppColors.neutral : AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: actuelle ? null : onChoisir,
              child: Text(
                actuelle
                    ? l10n.abonnementFormuleActuelle
                    : formule.surDevis
                        ? l10n.abonnementNousContacter
                        : l10n.abonnementChoisir,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),

          if (formule.surDevis) ...[
            const SizedBox(height: 8),
            Text(
              'contact@widjila.com · 06 25 75 57 07',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}


/// Petite pastille colorée — compte à rebours, statut d'une souscription.
class _Pastille extends StatelessWidget {
  final String texte;
  final Color couleur;

  const _Pastille({required this.texte, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        // Teinte dérivée de la couleur porteuse plutôt qu'une constante par
        // cas : la pastille suit automatiquement le sens qu'on lui donne.
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: couleur),
      ),
    );
  }
}

/// Historique des paiements — ce que l'organisation a réellement réglé.
///
/// Réservé aux rôles de gestion : la section n'est même pas construite pour
/// les autres (voir `_AbonnementView.widget.voitLaFacturation`).
class _SectionHistorique extends StatelessWidget {
  final List<SouscriptionHistorique> lignes;
  final double totalPaye;

  const _SectionHistorique({required this.lignes, required this.totalPaye});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Devise du total : celle de la dernière ligne PAYÉE. Additionner des
    // montants de devises différentes n'aurait aucun sens ; en pratique une
    // organisation en a une seule.
    final devise = lignes.where((e) => e.estPayee).map((e) => e.devise).firstOrNull ?? 'EUR';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.abonnementHistoriqueTitre,
                style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary,
                ),
              ),
            ),
            if (totalPaye > 0)
              Text(
                '${l10n.abonnementTotalRegle} · ${_montant(totalPaye, devise)}',
                style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (lignes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 30, color: AppColors.textSecondary),
                const SizedBox(height: 8),
                Text(
                  l10n.abonnementHistoriqueVide,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.abonnementHistoriqueVideDescription,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          )
        else
          for (final ligne in lignes) ...[
            _LigneHistorique(ligne: ligne),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  static String _montant(double valeur, String devise) {
    final symbole = switch (devise.toUpperCase()) {
      'EUR' => '€',
      'USD' => r'$',
      'XOF' => 'FCFA',
      _ => devise.toUpperCase(),
    };
    // Deux décimales seulement si elles portent une information : « 49 € »
    // se lit mieux que « 49,00 € », et « 49,90 € » reste exact.
    final texte = valeur == valeur.roundToDouble()
        ? valeur.toStringAsFixed(0)
        : valeur.toStringAsFixed(2).replaceAll('.', ',');
    return symbole == 'FCFA' ? '$texte $symbole' : '$texte $symbole';
  }
}

/// Une souscription passée : formule, montant figé, statut, date.
class _LigneHistorique extends StatelessWidget {
  final SouscriptionHistorique ligne;

  const _LigneHistorique({required this.ligne});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Le libellé et la couleur viennent du STATUT SERVEUR, jamais d'une
    // déduction locale. Une souscription `en_attente` est un paiement que le
    // serveur n'a pas confirmé : l'afficher comme un achat abouti tromperait
    // sur ce qui a réellement été payé.
    final (libelle, couleur) = switch (ligne.statut) {
      'active' => (l10n.abonnementStatutActive, AppColors.success),
      'expiree' => (l10n.abonnementStatutExpiree, AppColors.textSecondary),
      'annulee' => (l10n.abonnementStatutAnnulee, AppColors.textSecondary),
      'echec' => (l10n.abonnementStatutEchec, AppColors.danger),
      _ => (l10n.abonnementStatutEnAttente, AppColors.warning),
    };

    final date = ligne.creeLe ?? ligne.dateDebut;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ligne.planNom ?? ligne.planCode ?? l10n.abonnementTitre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (date != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.abonnementSouscritLe(_date(date)),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                ligne.prixPaye == null
                    ? l10n.abonnementSurDevis
                    : _SectionHistorique._montant(ligne.prixPaye!, ligne.devise),
                style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              _Pastille(texte: libelle, couleur: couleur),
            ],
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
