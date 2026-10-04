import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/abonnement.dart';

/// Le parcours « Premium sur devis », côté mobile.
///
/// Trois moments dans une seule section, parce qu'ils racontent une seule
/// histoire et qu'un relevé de chantier ne doit pas naviguer entre trois
/// écrans pour la suivre :
///
///   — la DEMANDE (volumes, durée souhaitée, besoins) ;
///   — le DEVIS reçu : montants, durée, limites, « Accepter » / « Refuser » ;
///   — le PAIEMENT, qui ouvre la page sécurisée de Stripe dans le navigateur.
///
/// Rien n'est décidé ici : `peutEtreAccepte` et `peutEtrePaye` viennent du
/// SERVEUR, qui seul connaît la validité et l'état du règlement. Les
/// recalculer afficherait des boutons qui finiraient en refus.
///
/// Cette section n'existe PAS sur iOS : elle mène à un paiement hors achat
/// intégré, ce que l'App Store interdit (voir `ReglesStore`). L'appelant s'en
/// charge — la section, elle, ne connaît pas la boutique.
class SectionDevis extends StatelessWidget {
  final List<Devis> devis;
  final bool enCours;
  final String? erreur;
  final VoidCallback onDemander;
  final void Function(Devis) onAccepter;
  final void Function(Devis) onRefuser;
  final void Function(Devis) onPayer;

  const SectionDevis({
    super.key,
    required this.devis,
    required this.enCours,
    required this.erreur,
    required this.onDemander,
    required this.onAccepter,
    required this.onRefuser,
    required this.onPayer,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Une demande en cours : le serveur refuserait la seconde, et proposer le
    // bouton reviendrait à promettre ce qu'on refuse ensuite.
    final demandeEnCours = devis.any(
      (d) => d.statut == StatutDevis.brouillon || d.statut == StatutDevis.envoye,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.devisTitre,
          style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),

        if (erreur != null) ...[
          _Bandeau(texte: erreur!, erreur: true),
          const SizedBox(height: 10),
        ],

        if (!demandeEnCours)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enCours ? null : onDemander,
              icon: const Icon(Icons.request_quote_outlined, size: 18),
              label: Text(l10n.devisDemander),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

        for (final d in devis) ...[
          const SizedBox(height: 12),
          _CarteDevis(
            devis: d,
            enCours: enCours,
            onAccepter: () => onAccepter(d),
            onRefuser: () => onRefuser(d),
            onPayer: () => onPayer(d),
          ),
        ],
      ],
    );
  }
}

/// Un devis : son numéro, son état, et ce qu'il engage.
class _CarteDevis extends StatelessWidget {
  final Devis devis;
  final bool enCours;
  final VoidCallback onAccepter;
  final VoidCallback onRefuser;
  final VoidCallback onPayer;

  const _CarteDevis({
    required this.devis,
    required this.enCours,
    required this.onAccepter,
    required this.onRefuser,
    required this.onPayer,
  });

  /// Couleur de l'état — vert quand c'est acquis, orange quand on attend le
  /// client, neutre quand il n'y a rien à faire.
  static (String, Color) _etat(StatutDevis statut, AppLocalizations l10n) => switch (statut) {
        StatutDevis.brouillon => (l10n.devisStatutBrouillon, AppColors.textSecondary),
        StatutDevis.envoye => (l10n.devisStatutEnvoye, AppColors.warning),
        StatutDevis.accepte => (l10n.devisStatutAccepte, AppColors.success),
        StatutDevis.refuse => (l10n.devisStatutRefuse, AppColors.danger),
        StatutDevis.expire => (l10n.devisStatutExpire, AppColors.textSecondary),
        StatutDevis.inconnu => (l10n.devisStatutBrouillon, AppColors.textSecondary),
      };

  String _montant(double? valeur) =>
      valeur == null ? '—' : '${valeur.toStringAsFixed(0)} ${devis.devise}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (libelle, couleur) = _etat(devis.statut, l10n);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 17, color: AppColors.textSecondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  devis.numero,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  libelle,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: couleur),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (!devis.chiffre)
            // Demande reçue, pas encore chiffrée. On le dit, sans annoncer un
            // délai qu'on ne tiendrait peut-être pas.
            Text(
              l10n.devisEnPreparation,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            )
          else ...[
            _Ligne(libelle: l10n.devisMontantHt, valeur: _montant(devis.montantHt)),
            if (devis.tauxTva > 0)
              _Ligne(
                libelle: l10n.devisTva(devis.tauxTva.toStringAsFixed(0)),
                valeur: _montant(devis.montantTva),
              ),
            _Ligne(
              libelle: l10n.devisMontantTtc,
              valeur: _montant(devis.montantTtc),
              forte: true,
            ),
            if (devis.dureeMois != null)
              _Ligne(libelle: l10n.devisDuree, valeur: l10n.devisDureeMois(devis.dureeMois!)),
            _Ligne(
              libelle: l10n.devisUtilisateurs,
              valeur: devis.limiteUtilisateurs?.toString() ?? l10n.abonnementIllimite,
            ),
            if (devis.limiteChantiers != null)
              _Ligne(libelle: l10n.devisChantiers, valeur: '${devis.limiteChantiers}'),
          ],

          if (devis.conditions != null && devis.conditions!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              devis.conditions!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.45),
            ),
          ],

          if (devis.payeLe != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                Text(
                  l10n.devisRegle,
                  style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success,
                  ),
                ),
              ],
            ),
          ],

          // ── Ce que le SERVEUR autorise, et rien d'autre ──
          if (devis.peutEtreAccepte) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: enCours ? null : onRefuser,
                    child: Text(l10n.devisRefuser),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: enCours ? null : onAccepter,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    child: Text(l10n.devisAccepter),
                  ),
                ),
              ],
            ),
          ],

          if (devis.peutEtrePaye) ...[
            const SizedBox(height: 14),
            Text(
              l10n.devisRedirection,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enCours ? null : onPayer,
                icon: const Icon(Icons.lock_outline_rounded, size: 17),
                label: Text(l10n.devisProcederPaiement),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  final String libelle;
  final String valeur;
  final bool forte;

  const _Ligne({required this.libelle, required this.valeur, this.forte = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              libelle,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            valeur,
            style: TextStyle(
              fontSize: forte ? 15 : 13,
              fontWeight: forte ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bandeau extends StatelessWidget {
  final String texte;
  final bool erreur;

  const _Bandeau({required this.texte, this.erreur = false});

  @override
  Widget build(BuildContext context) {
    final couleur = erreur ? AppColors.danger : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            erreur ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: couleur,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
