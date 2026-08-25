import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/couleurs_avatar.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve_collaboration.dart';
import '../cubit/reserve_detail_cubit.dart';
import '../cubit/reserve_detail_state.dart';

/// Fil de discussion d'une réserve.
///
/// C'est la pièce qui manquait pour que l'application serve à autre chose
/// qu'à constater : jusqu'ici, le modèle `Commentaire` et ses routes
/// existaient côté serveur, l'historique mobile savait même afficher une
/// entrée de type « commentaire » — mais aucun écran ne permettait d'en
/// écrire un. La conversation se faisait donc par téléphone, hors de la
/// trace du chantier.
class SectionCommentaires extends StatefulWidget {
  const SectionCommentaires({super.key});

  @override
  State<SectionCommentaires> createState() => _SectionCommentairesState();
}

class _SectionCommentairesState extends State<SectionCommentaires> {
  final _controleur = TextEditingController();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final message = _controleur.text.trim();
    if (message.isEmpty) return;

    final cubit = context.read<ReserveDetailCubit>();
    final l10n = context.l10n;
    final ok = await cubit.ajouterCommentaire(message);
    if (!mounted || !context.mounted) return;

    if (ok) {
      // Vidé APRÈS confirmation : en cas d'échec réseau, le texte reste dans
      // le champ et l'utilisateur n'a pas à le retaper.
      _controleur.clear();
      AppAlert.success(context, message: l10n.reserveCommentaireAjoute);
    } else {
      AppAlert.error(context, message: cubit.state.erreur ?? l10n.commonUneErreurSurvenue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<ReserveDetailCubit, ReserveDetailState>(
      buildWhen: (a, b) =>
          a.commentaires != b.commentaires ||
          a.commentairesCharges != b.commentairesCharges ||
          a.commentaireStatus != b.commentaireStatus,
      builder: (context, state) {
        final enCours = state.commentaireStatus == ActionReserveStatus.enCours;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!state.commentairesCharges)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
                  ),
                ),
              )
            else if (state.commentaires.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l10n.reserveCommentaireAucun,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                ),
              )
            else
              for (final commentaire in state.commentaires)
                _Bulle(commentaire: commentaire),

            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controleur,
                    minLines: 1,
                    // Jusqu'à 4 lignes visibles : un commentaire de chantier
                    // tient rarement en une ligne, et un champ qui ne grandit
                    // pas oblige à écrire à l'aveugle.
                    maxLines: 4,
                    // Miroir de `ajouterCommentaireSchema` : max(3000).
                    maxLength: 3000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: l10n.reserveCommentaireHint,
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.background,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Le bouton reste visible mais inerte pendant l'envoi : le
                // masquer ferait sauter la mise en page à chaque message.
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: enCours ? null : _envoyer,
                      child: Center(
                        child: enCours
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                              )
                            : Tooltip(
                                message: l10n.reserveCommentaireEnvoyer,
                                child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Un message — pastille d'auteur, nom, date, texte.
class _Bulle extends StatelessWidget {
  final CommentaireReserve commentaire;
  const _Bulle({required this.commentaire});

  @override
  Widget build(BuildContext context) {
    final auteur = commentaire.auteur;
    final couleur = auteur == null ? AppColors.neutral : couleurAvatar(auteur.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: couleur),
            alignment: Alignment.center,
            child: Text(
              auteur?.initiales ?? '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        auteur?.nomComplet ?? '—',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (commentaire.createdAt != null)
                      Text(
                        DateFormat('dd/MM · HH:mm').format(commentaire.createdAt!),
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: Text(
                    commentaire.message,
                    style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
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

/// Liste des intervenants affectés à la réserve, avec retrait au tap.
///
/// Répond à la question centrale du métier — QUI doit lever cette réserve —
/// à laquelle l'application ne savait pas répondre jusqu'ici.
class SectionAffectations extends StatelessWidget {
  /// L'action d'affectation est réservée à RESERVE_INTERVENANTS côté serveur,
  /// le retrait à OPERATIONNEL : on masque plutôt que de laisser découvrir
  /// un 403.
  final bool peutAffecter;
  final bool peutRetirer;
  final VoidCallback onAjouter;

  const SectionAffectations({
    super.key,
    required this.peutAffecter,
    required this.peutRetirer,
    required this.onAjouter,
  });

  Future<void> _retirer(BuildContext context, AffectationReserve affectation) async {
    final l10n = context.l10n;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(affectation.libelle),
        content: Text(
          l10n.reserveAffectationRetirerConfirm,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;

    final cubit = context.read<ReserveDetailCubit>();
    final ok = await cubit.retirerAffectation(affectation.id);
    if (!context.mounted) return;
    if (ok) {
      AppAlert.success(context, message: l10n.reserveAffectationRetiree);
    } else {
      AppAlert.error(context, message: cubit.state.erreur ?? l10n.commonUneErreurSurvenue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<ReserveDetailCubit, ReserveDetailState>(
      buildWhen: (a, b) =>
          a.affectations != b.affectations || a.affectationsChargees != b.affectationsChargees,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!state.affectationsChargees)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
                  ),
                ),
              )
            else if (state.affectations.isEmpty)
              Text(
                l10n.reserveAffectationAucune,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontStyle: FontStyle.italic),
              )
            else
              for (final affectation in state.affectations)
                _LigneAffectation(
                  affectation: affectation,
                  onRetirer: peutRetirer ? () => _retirer(context, affectation) : null,
                ),
            if (peutAffecter) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onAjouter,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                label: Text(
                  l10n.reserveAffectationAjouter,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LigneAffectation extends StatelessWidget {
  final AffectationReserve affectation;
  final VoidCallback? onRetirer;

  const _LigneAffectation({required this.affectation, required this.onRetirer});

  @override
  Widget build(BuildContext context) {
    // Une entreprise et une personne ne se ressemblent pas : icône et couleur
    // les distinguent sans avoir à lire le nom.
    final estEntreprise = affectation.estEntreprise;
    final couleur = estEntreprise
        ? AppColors.info
        : (affectation.utilisateur == null
            ? AppColors.neutral
            : couleurAvatar(affectation.utilisateur!.id));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: estEntreprise ? couleur.withValues(alpha: 0.14) : couleur,
            ),
            alignment: Alignment.center,
            child: estEntreprise
                ? Icon(Icons.business_rounded, size: 17, color: couleur)
                : Text(
                    affectation.utilisateur?.initiales ?? '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  affectation.libelle,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                if (affectation.dateAffectation != null)
                  Text(
                    DateFormat('dd/MM/yyyy').format(affectation.dateAffectation!),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          if (onRetirer != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
              tooltip: context.l10n.commonDelete,
              onPressed: onRetirer,
            ),
        ],
      ),
    );
  }
}
