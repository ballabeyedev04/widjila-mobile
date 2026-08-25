import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/membre.dart';
import '../cubit/membres_cubit.dart';
import '../cubit/membres_state.dart';
import 'membres_list_page.dart' show couleurAvatarMembre, toneRoleMembre, toneStatutMembre, libelleStatutMembre;

/// Ouvre la fiche détaillée d'un membre.
///
/// Reprend volontairement le format de [AjouterMembreSheet] —
/// `DraggableScrollableSheet`, poignée, titre + croix — pour que consulter et
/// créer se ressemblent : l'utilisateur reconnaît le contenant et n'a qu'à
/// lire le contenu.
Future<void> ouvrirDetailMembre(BuildContext context, Membre membre) {
  final cubit = context.read<MembresCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _DetailMembreSheet(membreInitial: membre),
    ),
  );
}

class _DetailMembreSheet extends StatelessWidget {
  final Membre membreInitial;
  const _DetailMembreSheet({required this.membreInitial});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // L'identifiant de l'utilisateur CONNECTÉ : le serveur refuse qu'il
    // modifie son propre statut (garde anti auto-promotion dans
    // `OrganisationService.modifierMembre`). On masque donc l'action plutôt
    // que de laisser découvrir le refus après coup.
    final moiId = context.select((AuthBloc b) => b.state.utilisateur?.id);

    return BlocBuilder<MembresCubit, MembresState>(
      builder: (context, state) {
        // Relu depuis l'état à chaque reconstruction : après un changement de
        // statut, la fiche doit refléter la nouvelle valeur sans être rouverte.
        final membre = state.membres.firstWhere(
          (m) => m.id == membreInitial.id,
          orElse: () => membreInitial,
        );
        final estMoi = moiId != null && moiId == membre.id;
        final enCours = state.membreEnCoursDeMaj == membre.id;

        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                  ContenuFormulaire(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.membreDetailTitre,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ContenuFormulaire(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        children: [
                          _EnTeteIdentite(membre: membre),
                          const SizedBox(height: 22),
                          _Bloc(
                            children: [
                              _Ligne(
                                icone: Icons.mail_outline_rounded,
                                libelle: l10n.membreFormEmail,
                                valeur: membre.email,
                              ),
                              _Ligne(
                                icone: Icons.phone_outlined,
                                libelle: l10n.membreFormTelephone,
                                valeur: membre.telephone,
                              ),
                              _Ligne(
                                icone: Icons.work_outline_rounded,
                                libelle: l10n.membreFormFonction,
                                valeur: membre.fonction,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _Bloc(
                            children: [
                              _Ligne(
                                icone: Icons.badge_outlined,
                                libelle: l10n.membreFormRole,
                                valeur: membre.role.label(l10n),
                              ),
                              _Ligne(
                                icone: Icons.verified_user_outlined,
                                libelle: l10n.membreDetailDerniereConnexion,
                                valeur: membre.dernierConnexion != null
                                    ? DateFormat('dd/MM/yyyy à HH:mm').format(membre.dernierConnexion!)
                                    : l10n.membreDetailJamaisConnecte,
                              ),
                              if (membre.mdpTemporaire)
                                _Ligne(
                                  icone: Icons.key_outlined,
                                  libelle: l10n.membreFormMdp,
                                  valeur: l10n.membreDetailMdpTemporaire,
                                  accent: AppColors.warning,
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          if (estMoi)
                            _NoteInfo(texte: l10n.membreDetailSoiMeme)
                          else
                            _BoutonStatut(membre: membre, enCours: enCours),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Avatar, nom, et les deux pastilles (rôle + statut) — reprend exactement le
/// vocabulaire visuel de la carte de la liste, pour que l'ouverture de la
/// fiche se lise comme un agrandissement et non comme un autre écran.
class _EnTeteIdentite extends StatelessWidget {
  final Membre membre;
  const _EnTeteIdentite({required this.membre});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final couleur = couleurAvatarMembre(membre.id);

    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: couleur,
            boxShadow: [
              BoxShadow(color: couleur.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: Center(
            child: Text(
              membre.initiales,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 28),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          membre.nomComplet,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            StatusBadge(label: membre.role.label(l10n), tone: toneRoleMembre(membre.role)),
            StatusBadge(label: libelleStatutMembre(l10n, membre.statut), tone: toneStatutMembre(membre.statut)),
          ],
        ),
      ],
    );
  }
}

/// Carte blanche regroupant des lignes d'information.
class _Bloc extends StatelessWidget {
  final List<Widget> children;
  const _Bloc({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(children: children),
    );
  }
}

class _Ligne extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final String? valeur;
  final Color? accent;

  const _Ligne({required this.icone, required this.libelle, this.valeur, this.accent});

  @override
  Widget build(BuildContext context) {
    final vide = valeur == null || valeur!.isEmpty;
    final couleur = accent ?? AppColors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icone, size: 17, color: couleur),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  libelle,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  vide ? context.l10n.membreDetailNonRenseigne : valeur!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    // Un champ vide reste visible mais s'efface : l'absence
                    // d'information est elle-même une information.
                    color: vide ? AppColors.textMuted : AppColors.textPrimary,
                    fontStyle: vide ? FontStyle.italic : FontStyle.normal,
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

class _NoteInfo extends StatelessWidget {
  final String texte;
  const _NoteInfo({required this.texte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton d'activation / désactivation.
///
/// Une seule action, dont le LIBELLÉ, la COULEUR et l'ICÔNE basculent selon
/// le statut courant — plutôt que deux boutons dont un serait toujours
/// inutile. Le vert engage (rendre l'accès), le rouge retire.
class _BoutonStatut extends StatelessWidget {
  final Membre membre;
  final bool enCours;

  const _BoutonStatut({required this.membre, required this.enCours});

  Future<void> _agir(BuildContext context) async {
    final l10n = context.l10n;
    final activer = !membre.estActif;

    // Désactiver retire un accès : on confirme, et on explique ce que ça
    // implique RÉELLEMENT (l'historique reste) — sans quoi l'utilisateur
    // hésite entre désactiver et supprimer.
    if (!activer) {
      final confirme = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.membreDetailDesactiver),
          content: Text(
            l10n.membreDetailDesactiverConfirm,
            style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.membreDetailDesactiver),
            ),
          ],
        ),
      );
      if (confirme != true || !context.mounted) return;
    }

    final cubit = context.read<MembresCubit>();
    final ok = await cubit.basculerStatut(membre.id, activer: activer);
    if (!context.mounted) return;

    if (ok) {
      AppAlert.success(
        context,
        message: activer ? l10n.membreDetailActiveMessage : l10n.membreDetailDesactiveMessage,
      );
    } else {
      AppAlert.error(context, message: cubit.state.statutErreur ?? l10n.commonUneErreurSurvenue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final activer = !membre.estActif;
    final couleur = activer ? AppColors.success : AppColors.danger;

    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: enCours ? null : () => _agir(context),
        style: FilledButton.styleFrom(
          backgroundColor: couleur,
          disabledBackgroundColor: couleur.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: enCours
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Icon(activer ? Icons.check_circle_outline_rounded : Icons.block_rounded, size: 20),
        label: Text(
          activer ? l10n.membreDetailActiver : l10n.membreDetailDesactiver,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
