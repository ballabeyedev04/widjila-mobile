import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/couleurs_avatar.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/partenaire.dart';
import '../cubit/partenaires_cubit.dart';
import 'intervenants_list_page.dart'
    show iconeTypePartenaire, libelleStatutPartenaire, toneTypePartenaire;

/// Ouvre la fiche détaillée d'un intervenant.
///
/// Reprend le format des feuilles de l'équipe — `DraggableScrollableSheet`,
/// poignée, titre + croix, blocs d'information, action en bas — pour que
/// consulter un membre et consulter une entreprise se ressemblent : une seule
/// grammaire à apprendre pour les deux annuaires.
///
/// [peutGerer] reflète `requireRole(...)` sur `PUT /partenaires/:id` : quand
/// il est faux, la fiche reste consultable mais l'action de bascule cède la
/// place à une note explicative, plutôt que de laisser découvrir un 403.
Future<void> ouvrirDetailPartenaire(
  BuildContext context,
  Partenaire partenaire, {
  required bool peutGerer,
}) {
  final cubit = context.read<PartenairesCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _DetailPartenaireSheet(partenaireInitial: partenaire, peutGerer: peutGerer),
    ),
  );
}

class _DetailPartenaireSheet extends StatelessWidget {
  final Partenaire partenaireInitial;
  final bool peutGerer;

  const _DetailPartenaireSheet({required this.partenaireInitial, required this.peutGerer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<PartenairesCubit, PartenairesState>(
      builder: (context, state) {
        // Relu depuis l'état à chaque reconstruction : après une bascule, la
        // fiche doit refléter la nouvelle valeur sans être rouverte.
        final partenaire = state.items.firstWhere(
          (p) => p.id == partenaireInitial.id,
          orElse: () => partenaireInitial,
        );
        final enCours = state.partenaireEnCoursDeMaj == partenaire.id;

        return DraggableScrollableSheet(
          initialChildSize: 0.74,
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
                              l10n.partenaireDetailTitre,
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
                          _EnTeteIdentite(partenaire: partenaire),
                          if (!partenaire.actif) ...[
                            const SizedBox(height: 18),
                            _Bandeau(
                              icone: Icons.inventory_2_outlined,
                              couleur: AppColors.neutral,
                              texte: l10n.partenaireDetailBandeauArchive,
                            ),
                          ],
                          const SizedBox(height: 22),
                          _TitreSection(l10n.partenaireDetailSectionCoordonnees, icone: Icons.alternate_email_rounded),
                          _Bloc(
                            children: [
                              _Ligne(
                                icone: Icons.person_outline_rounded,
                                libelle: l10n.partenaireFormResponsable,
                                valeur: partenaire.contact,
                              ),
                              _Ligne(
                                icone: Icons.mail_outline_rounded,
                                libelle: l10n.partenaireFormEmail,
                                valeur: partenaire.email,
                              ),
                              _Ligne(
                                icone: Icons.phone_outlined,
                                libelle: l10n.partenaireFormTelephone,
                                valeur: partenaire.telephone,
                              ),
                              _Ligne(
                                icone: Icons.location_on_outlined,
                                libelle: l10n.partenaireFormAdresse,
                                valeur: partenaire.adresse,
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _TitreSection(l10n.partenaireDetailSectionEntreprise, icone: Icons.business_rounded),
                          _Bloc(
                            children: [
                              _Ligne(
                                icone: iconeTypePartenaire(partenaire.type),
                                libelle: l10n.partenaireFormType,
                                valeur: partenaire.type.label(l10n),
                                accent: toneTypePartenaire(partenaire.type).fg,
                              ),
                              _Ligne(
                                icone: Icons.account_tree_outlined,
                                libelle: l10n.partenaireDetailRattachement,
                                // Un partenaire sans `chantierId` appartient à
                                // l'annuaire de l'organisation entière — ce
                                // n'est pas une donnée manquante, et l'écrire
                                // évite une ligne « Non renseigné » trompeuse.
                                valeur: partenaire.chantierId == null
                                    ? l10n.partenaireDetailOrganisation
                                    : l10n.partenaireDetailChantierDedie,
                              ),
                              if (partenaire.notes != null && partenaire.notes!.isNotEmpty)
                                _Ligne(
                                  icone: Icons.sticky_note_2_outlined,
                                  libelle: l10n.partenaireDetailNotes,
                                  valeur: partenaire.notes,
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          if (peutGerer)
                            _BoutonStatut(partenaire: partenaire, enCours: enCours)
                          else
                            _Bandeau(
                              icone: Icons.info_outline_rounded,
                              couleur: AppColors.info,
                              texte: l10n.partenaireDetailLectureSeule,
                            ),
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

/// Avatar, nom et pastilles — reprend exactement le vocabulaire visuel de la
/// carte de la liste, pour que l'ouverture de la fiche se lise comme un
/// agrandissement et non comme un autre écran.
class _EnTeteIdentite extends StatelessWidget {
  final Partenaire partenaire;
  const _EnTeteIdentite({required this.partenaire});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final couleur = partenaire.actif ? couleurAvatar(partenaire.id) : AppColors.neutral;

    return Column(
      children: [
        SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            clipBehavior: Clip.none,
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
                    partenaire.initiales,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 28),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 7, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Icon(
                    iconeTypePartenaire(partenaire.type),
                    size: 17,
                    color: toneTypePartenaire(partenaire.type).fg,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          partenaire.nom,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            StatusBadge(label: partenaire.type.label(l10n), tone: toneTypePartenaire(partenaire.type)),
            StatusBadge(
              label: libelleStatutPartenaire(l10n, partenaire.actif),
              tone: partenaire.actif ? BadgeTone.success : BadgeTone.neutral,
            ),
          ],
        ),
      ],
    );
  }
}

/// Intertitre de section — même dessin que dans le formulaire d'ajout, pour
/// que la fiche et le formulaire se répondent section par section.
class _TitreSection extends StatelessWidget {
  final String texte;
  final IconData icone;

  const _TitreSection(this.texte, {required this.icone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icone, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            texte.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: AppColors.border.withValues(alpha: 0.7))),
        ],
      ),
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

class _Bandeau extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final String texte;

  const _Bandeau({required this.icone, required this.couleur, required this.texte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icone, size: 18, color: couleur),
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

/// Bouton d'activation / archivage.
///
/// Une seule action, dont le LIBELLÉ, la COULEUR et l'ICÔNE basculent selon
/// l'état courant — plutôt que deux boutons dont un serait toujours inutile.
/// Le vert rend l'intervenant à l'annuaire courant, le rouge l'en retire.
class _BoutonStatut extends StatelessWidget {
  final Partenaire partenaire;
  final bool enCours;

  const _BoutonStatut({required this.partenaire, required this.enCours});

  Future<void> _agir(BuildContext context) async {
    final l10n = context.l10n;
    final activer = !partenaire.actif;

    // Archiver retire l'intervenant des listes de sélection : on confirme, et
    // on explique ce que ça implique RÉELLEMENT (la fiche reste, c'est
    // réversible) — sans quoi l'utilisateur hésite entre archiver et
    // supprimer.
    if (!activer) {
      final confirme = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.partenaireDetailDesactiver),
          content: Text(
            l10n.partenaireDetailDesactiverConfirm,
            style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.partenaireDetailDesactiver),
            ),
          ],
        ),
      );
      if (confirme != true || !context.mounted) return;
    }

    final cubit = context.read<PartenairesCubit>();
    final ok = await cubit.basculerStatut(partenaire.id, activer: activer);
    if (!context.mounted) return;

    if (ok) {
      AppAlert.success(
        context,
        message: activer ? l10n.partenaireDetailActiveMessage : l10n.partenaireDetailDesactiveMessage,
      );
    } else {
      AppAlert.error(context, message: cubit.state.statutErreur ?? l10n.commonUneErreurSurvenue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final activer = !partenaire.actif;
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
            : Icon(activer ? Icons.check_circle_outline_rounded : Icons.inventory_2_outlined, size: 20),
        label: Text(
          activer ? l10n.partenaireDetailActiver : l10n.partenaireDetailDesactiver,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
