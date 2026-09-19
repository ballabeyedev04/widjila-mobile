import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve.dart';
import '../cubit/reserve_detail_state.dart';
import 'reserve_statut_badge.dart';
import 'reserve_statut_couleurs.dart';

/// « Historique des changements » — la chronologie des lignes PERSISTÉES par
/// le serveur pour cette réserve, du plus récent au plus ancien.
///
/// Chaque changement de statut se lit d'un coup d'œil : QUEL statut → QUEL
/// nouveau statut (deux badges, la couleur du système de statuts), QUAND (la
/// date SERVEUR, rendue dans le fuseau du téléphone), PAR QUI (le nom
/// complet ; « Système » pour un passage automatique en retard). Les autres
/// lignes — modification, commentaire, affectation — gardent leur place dans
/// la chronologie, plus discrètes : ce sont des faits, pas des décisions.
///
/// Rien ici n'est déduit du statut courant : une réserve « levée » sans
/// ligne d'historique montre l'état vide, pas un parcours inventé.
class SectionHistoriqueChangements extends StatelessWidget {
  final List<ReserveHistoriqueEntry> entrees;
  final ActionReserveStatus status;
  final VoidCallback onReessayer;

  const SectionHistoriqueChangements({
    super.key,
    required this.entrees,
    required this.status,
    required this.onReessayer,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    switch (status) {
      case ActionReserveStatus.inactif:
      case ActionReserveStatus.enCours:
        return const _SqueletteTimeline();
      case ActionReserveStatus.erreur:
        return _Message(
          icone: Icons.cloud_off_rounded,
          texte: l10n.historiqueChangementsErreur,
          action: TextButton.icon(
            onPressed: onReessayer,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.commonRetry),
          ),
        );
      case ActionReserveStatus.succes:
        if (entrees.isEmpty) {
          return _Message(icone: Icons.history_toggle_off_rounded, texte: l10n.historiqueChangementsVide);
        }
        return Column(
          children: [
            for (var i = 0; i < entrees.length; i++)
              _LigneTimeline(
                key: ValueKey(entrees[i].id),
                entree: entrees[i],
                estDerniere: i == entrees.length - 1,
                // La ligne de tête est la DERNIÈRE modification : elle se
                // distingue, l'utilisateur la cherche en premier.
                estRecente: i == 0,
              ),
          ],
        );
    }
  }
}

/// « 18 sept. 2026 • 14:32 » dans la langue et le FUSEAU de l'utilisateur.
/// La date vient du serveur en UTC ; sans `toLocal()`, l'heure affichée
/// serait celle de Greenwich, décalée d'une ou deux heures selon la saison.
String formaterDateHistorique(BuildContext context, DateTime date) {
  final locale = Localizations.localeOf(context).toString();
  final locale_ = date.toLocal();
  final jour = DateFormat.yMMMd(locale).format(locale_);
  final heure = DateFormat.Hm(locale).format(locale_);
  return '$jour • $heure';
}

class _LigneTimeline extends StatelessWidget {
  final ReserveHistoriqueEntry entree;
  final bool estDerniere;
  final bool estRecente;

  const _LigneTimeline({super.key, required this.entree, required this.estDerniere, required this.estRecente});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final changement = entree.estChangementStatut;
    // La pastille prend la couleur du NOUVEAU statut : la chronologie se lit
    // alors comme une suite de couleurs, sans lire chaque ligne.
    final couleur = changement ? couleurStatutGraphique(entree.nouveauStatut!) : AppColors.textMuted;
    final auteur = entree.utilisateur?.nomComplet;
    final parQui = auteur != null && auteur.isNotEmpty
        ? l10n.reserveDetailModifiePar(auteur)
        : (changement ? l10n.reserveDetailModifiePar(l10n.historiqueSysteme) : null);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Le rail : point + trait ─────────────────────────────────────
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: changement ? 14 : 10,
                  height: changement ? 14 : 10,
                  decoration: BoxDecoration(
                    color: changement ? couleur : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: couleur, width: 2),
                    boxShadow: estRecente
                        ? [BoxShadow(color: couleur.withValues(alpha: 0.35), blurRadius: 8, spreadRadius: 1)]
                        : null,
                  ),
                ),
                if (!estDerniere)
                  Expanded(
                    child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: AppColors.border),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // ── Le contenu ─────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: estDerniere ? 4 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (changement)
                    _Transition(ancien: entree.ancienStatut, nouveau: entree.nouveauStatut!)
                  else
                    Text(
                      entree.libelle(l10n),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  const SizedBox(height: 6),
                  if (entree.createdAt != null)
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            formaterDateHistorique(context, entree.createdAt!),
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  if (parQui != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(parQui, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ),
                      ],
                    ),
                  ],
                  if (entree.motif != null && entree.motif!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        entree.motif!,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// « Ancien → Nouveau », deux badges du système de statuts reliés par une
/// flèche ; « Statut initial → Créée » à la création. Un `Wrap` : deux
/// libellés longs (« Prise en charge → À surveiller ») passent l'un sous
/// l'autre sur un téléphone étroit au lieu d'être tronqués.
class _Transition extends StatelessWidget {
  final ReserveStatut? ancien;
  final ReserveStatut nouveau;
  const _Transition({required this.ancien, required this.nouveau});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        if (ancien != null)
          ReserveStatutBadge(statut: ancien!)
        else
          Text(l10n.historiqueStatutInitial, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.textMuted),
        ReserveStatutBadge(statut: nouveau),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icone;
  final String texte;
  final Widget? action;
  const _Message({required this.icone, required this.texte, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Icon(icone, size: 28, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(
            texte,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
          ),
          if (action != null) ...[const SizedBox(height: 4), action!],
        ],
      ),
    );
  }
}

/// Trois lignes fantômes, le temps que le serveur réponde — même
/// scintillement que les listes de l'application.
class _SqueletteTimeline extends StatelessWidget {
  const _SqueletteTimeline();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.background,
      highlightColor: Colors.white,
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 14, height: 14, decoration: const BoxDecoration(color: AppColors.background, shape: BoxShape.circle)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 20, width: 180, decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(6))),
                        const SizedBox(height: 8),
                        Container(height: 12, width: 120, decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(6))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
