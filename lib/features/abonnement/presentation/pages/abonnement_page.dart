import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/env.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/abonnement.dart';
import '../cubit/abonnement_cubit.dart';

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
    return BlocProvider(
      create: (_) => sl<AbonnementCubit>()..charger(),
      child: const _AbonnementView(),
    );
  }
}

class _AbonnementView extends StatelessWidget {
  const _AbonnementView();

  /// Ouvre la page d'abonnement du web — voir l'en-tête pour le raisonnement.
  Future<void> _ouvrirPaiement(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final uri = Uri.tryParse(Env.abonnementUrl);
    if (uri == null) return;

    final ouvert = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
          onPressed: () => context.pop(),
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
              onRetry: () => context.read<AbonnementCubit>().charger(),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => context.read<AbonnementCubit>().charger(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _CarteEtat(droits: state.droits, formule: state.formuleActuelle),
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
