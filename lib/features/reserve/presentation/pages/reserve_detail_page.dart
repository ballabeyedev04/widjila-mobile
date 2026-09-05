import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/fichier_image.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/reserve_statut_policy.dart';
import '../cubit/reserve_detail_cubit.dart';
import '../cubit/reserve_detail_state.dart';
import '../widgets/reserve_collaboration.dart';
import '../widgets/reserve_statut_badge.dart';
import 'affecter_reserve_sheet.dart';
import 'modifier_reserve_sheet.dart';
import 'qr_reserve_sheet.dart';
import '../../../../core/network/forcer_reseau.dart';

class ReserveDetailPage extends StatelessWidget {
  final String reserveId;
  const ReserveDetailPage({super.key, required this.reserveId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ReserveDetailCubit>(param1: reserveId)
        ..charger()
        // Commentaires et affectations en parallèle : deux requêtes de plus
        // ne doivent pas retarder l'affichage de la réserve elle-même.
        ..chargerCollaboration(),
      child: const _ReserveDetailView(),
    );
  }
}

class _ReserveDetailView extends StatelessWidget {
  const _ReserveDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ReserveDetailCubit, ReserveDetailState>(
      listenWhen: (a, b) =>
          (a.erreur != b.erreur && b.erreur != null) || (a.supprimee != b.supprimee && b.supprimee),
      listener: (context, state) {
        // La réserve n'existe plus : l'écran n'a plus rien à montrer, il se
        // referme et la liste appelante se rechargera.
        if (state.supprimee) {
          Navigator.of(context).pop(true);
          AppAlert.success(context, message: context.l10n.reserveSupprimeeMessage);
          return;
        }
        if (state.erreur != null) AppAlert.error(context, message: state.erreur!);
      },
      builder: (context, state) {
        final reserve = state.reserve;

        // Rôle + identité de l'utilisateur courant — nécessaires pour ne
        // proposer que les statuts que le back acceptera réellement (voir
        // reserve_statut_policy.dart, miroir de ReserveService.changerStatut).
        final (role, userId) =
            context.select((AuthBloc b) => (b.state.utilisateur?.role, b.state.utilisateur?.id));
        final statutsDisponibles = reserve == null || role == null
            ? const <ReserveStatut>[]
            : statutsProposables(
                statutActuel: reserve.statut,
                role: role,
                estAssigneAMoi: reserve.assigne?.id != null && reserve.assigne?.id == userId,
              );

        final l10n = context.l10n;
        return Scaffold(
          // Blanc, comme les autres écrans. Le CONTENU repose sur le gris de
          // fond (voir _DetailBody) : des cartes blanches sur une page blanche
          // perdraient tout relief.
          backgroundColor: AppColors.surface,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(
                    titre: reserve?.numeroAffiche(l10n) ?? l10n.reserveDetailTitreDefaut,
                    avecRetour: true,
                    // Écran plein hors coquille : le NotificationsCubit dont
                    // dépend la cloche n'y est pas fourni. Le menu d'actions
                    // prend sa place.
                    avecCloche: false,
                    action: reserve == null
                        ? null
                        : _MenuActions(reserve: reserve, role: role),
                  ),
                ),
                Expanded(
                  child: switch (state.status) {
                    ReserveDetailStatus.chargement =>
                      const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    ReserveDetailStatus.erreur => ErrorView(
                        message: state.erreur ?? l10n.commonErrorUnknown,
                        onRetry: () => context.read<ReserveDetailCubit>().charger(),
                      ),
                    ReserveDetailStatus.succes => _DetailBody(reserve: reserve!),
                  },
                ),
              ],
            ),
          ),
          // Absent si aucun statut n'est proposable (ex: sous-traitant qui ne
          // s'est pas vu assigner cette réserve) plutôt que d'ouvrir une feuille
          // vide sur laquelle il n'y a rien à faire.
          bottomNavigationBar: reserve == null || statutsDisponibles.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: state.actionEnCours
                          ? null
                          : () => _ouvrirChangementStatut(context, statutsDisponibles),
                      icon: const Icon(Icons.published_with_changes_outlined),
                      label: Text(l10n.reserveDetailChangerStatut, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
        );
      },
    );
  }

  void _ouvrirChangementStatut(BuildContext context, List<ReserveStatut> statutsDisponibles) {
    final cubit = context.read<ReserveDetailCubit>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return SafeArea(
          child: ContenuFormulaire(
            child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.published_with_changes_outlined, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(context.l10n.reserveDetailNouveauStatut, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                for (final s in statutsDisponibles)
                  ListTile(
                    leading: ReserveStatutBadge(statut: s),
                    title: Text(s.label(context.l10n), style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _confirmerChangement(context, cubit, s);
                    },
                  ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmerChangement(BuildContext context, ReserveDetailCubit cubit, ReserveStatut nouveauStatut) async {
    final l10n = context.l10n;
    String? motif;
    // Le back exige un motif pour un refus — demandé ici plutôt que de
    // laisser l'appel échouer silencieusement pour l'utilisateur.
    if (nouveauStatut == ReserveStatut.refusee) {
      final controleur = TextEditingController();
      motif = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(l10n.reserveDetailMotifRefusTitre),
          content: TextField(
            controller: controleur,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(hintText: l10n.reserveDetailMotifRefusHint),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.commonCancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.of(dialogContext).pop(controleur.text.trim()),
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
      );
      controleur.dispose();
      if (motif == null || motif.isEmpty) return; // annulé
    }

    final ok = await cubit.changerStatut(nouveauStatut, motif: motif);
    if (ok && context.mounted) {
      AppAlert.success(context, message: l10n.reserveDetailStatutMisAJour(nouveauStatut.label(l10n)));
    }
  }
}

/// Enveloppe carte commune — même langage visuel que le reste de l'app
/// (dashboard, listes) : fond blanc, coins arrondis, ombre douce.
class _Carte extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Carte({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Reserve reserve;
  const _DetailBody({required this.reserve});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final l10n = context.l10n;
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
      color: AppColors.primary,
      onRefresh: forcerReseau(() => context.read<ReserveDetailCubit>().charger()),
      child: ContenuCentre(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  reserve.titre,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              ReserveStatutBadge(statut: reserve.statut),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 15, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(reserve.localisationLabel(l10n), style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _Carte(
            child: Column(
              children: [
                _InfoRow(icon: Icons.calendar_today_outlined, label: l10n.reserveDetailCreeeLe, valeur: reserve.createdAt != null ? df.format(reserve.createdAt!) : '—'),
                if (reserve.createur != null)
                  _InfoRow(icon: Icons.person_outline, label: l10n.reserveDetailSignaleePar, valeur: reserve.createur!.nomComplet),
                _InfoRow(icon: Icons.flag_outlined, label: l10n.reserveDetailPriorite, valeur: reserve.priorite.label(l10n)),
                _InfoRow(icon: Icons.category_outlined, label: l10n.reserveDetailCategorie, valeur: reserve.categorie.label(l10n)),
                if (reserve.dateLimite != null)
                  _InfoRow(icon: Icons.event_outlined, label: l10n.reserveDetailEcheance, valeur: df.format(reserve.dateLimite!)),
                if (reserve.partenaire != null || reserve.entreprise != null)
                  _InfoRow(
                    icon: Icons.business_outlined,
                    label: l10n.roleEntreprise,
                    valeur: (reserve.partenaire ?? reserve.entreprise)!.nom,
                  ),
                if (reserve.assigne != null)
                  _InfoRow(icon: Icons.assignment_ind_outlined, label: l10n.reserveDetailAssigneeA, valeur: reserve.assigne!.nomComplet, dernier: true),
              ],
            ),
          ),

          if (reserve.description != null && reserve.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            _TitreSection(l10n.commonDescription),
            const SizedBox(height: 8),
            _Carte(
              child: Text(reserve.description!, style: const TextStyle(color: AppColors.textSecondary, height: 1.45, fontSize: 13.5)),
            ),
          ],

          if (reserve.statut == ReserveStatut.refusee && reserve.motifRefus != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(child: Text(reserve.motifRefus!, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TitreSection(l10n.reserveDetailPhotosCount(reserve.medias.length)),
              TextButton.icon(
                onPressed: () => _ajouterPhoto(context),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(l10n.commonAdd, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (reserve.medias.isEmpty)
            Container(
              height: 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(l10n.reserveDetailAucunePhoto, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reserve.medias.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  // 3 colonnes fixes convenaient au téléphone mais perdaient 3
                  // minuscules vignettes sur la largeur d'une tablette ; `min: 3`
                  // conserve le rendu téléphone à l'identique et la grille n'en
                  // ajoute qu'à mesure que la largeur (déjà plafonnée par
                  // `ContenuCentre` ci-dessus) le permet.
                  crossAxisCount: colonnesAdaptatives(constraints.maxWidth, min: 3),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, i) {
                  final m = reserve.medias[i];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GestureDetector(
                      onTap: () => _voirPhoto(context, m.url),
                      child: FichierImage(url: m.thumbnailUrl ?? m.url),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 24),
          _TitreSection(l10n.reserveAffectationsTitre),
          const SizedBox(height: 10),
          _Carte(child: _BlocAffectations(reserve: reserve)),

          const SizedBox(height: 24),
          _TitreSection(l10n.reserveCommentairesTitre),
          const SizedBox(height: 10),
          const _Carte(child: SectionCommentaires()),

          if (reserve.historiques.isNotEmpty) ...[
            const SizedBox(height: 24),
            _TitreSection(l10n.reserveDetailHistorique),
            const SizedBox(height: 10),
            _Carte(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: _Timeline(entrees: reserve.historiques.reversed.toList()),
            ),
          ],
        ],
        ),
      ),
      ),
    );
  }

  void _voirPhoto(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          // Le seul endroit qui a besoin des pixels d'origine : on zoome
          // dedans. Partout ailleurs l'image est décodée à sa taille
          // d'affichage (voir FichierImage.pleineResolution).
          child: FichierImage(url: url, fit: BoxFit.contain, pleineResolution: true),
        ),
      ),
    );
  }

  Future<void> _ajouterPhoto(BuildContext context) async {
    final cubit = context.read<ReserveDetailCubit>();
    final l10n = context.l10n;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
              title: Text(l10n.reserveDetailPrendrePhoto),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: Text(l10n.reserveDetailChoisirGalerie),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    // `maxWidth: 1920` — même plafond que la création de réserve
    // (`nouvelle_reserve_sheet.dart`) : sans lui, une photo prise avec
    // l'appareil photo (12 Mpx et plus) part à sa résolution native, souvent
    // 3 à 8 Mo, pour un affichage qui ne dépasse jamais l'écran du
    // téléphone. Le réseau de chantier est aussi celui qui en a le moins
    // besoin.
    final fichier = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1920);
    if (fichier == null || !context.mounted) return;

    final ok = await cubit.ajouterPhoto(fichier.path);
    if (ok && context.mounted) {
      AppAlert.success(context, message: l10n.reserveDetailPhotoAjoutee);
    }
  }
}

/// Menu « ⋮ » — modifier et supprimer.
///
/// Les deux actions sont gardées par des rôles DIFFÉRENTS côté serveur :
/// `PUT /reserves/:id` exige OPERATIONNEL_CONTROLE, `DELETE` exige
/// OPERATIONNEL (plus restrictif). On masque donc chaque entrée séparément
/// plutôt que d'afficher un menu qui reviendrait en 403.
class _MenuActions extends StatelessWidget {
  final Reserve reserve;
  final UserRole? role;

  const _MenuActions({required this.reserve, required this.role});

  /// Duplique la réserve après confirmation.
  ///
  /// Confirmation demandée bien que l'action ne détruise rien : elle CRÉE une
  /// réserve, et une copie involontaire au milieu d'une liste de deux cents
  /// se remarque tard et se nettoie à la main.
  Future<void> _dupliquer(BuildContext context) async {
    final l10n = context.l10n;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.reserveDupliquerTitre),
        content: Text(
          l10n.reserveDupliquerDescription,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.reserveDupliquerTitre),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;

    final cubit = context.read<ReserveDetailCubit>();
    final copie = await cubit.dupliquer();
    if (!context.mounted) return;

    if (copie == null) {
      AppAlert.error(context, message: cubit.state.erreur ?? l10n.commonUneErreurSurvenue);
      return;
    }
    // On REMPLACE l'écran par la copie plutôt que d'empiler : revenir en
    // arrière doit ramener à la liste, pas à l'original qu'on vient de
    // quitter des yeux.
    AppAlert.success(context, message: l10n.reserveDupliqueeMessage);
    context.pushReplacement('/reserves/${copie.id}');
  }

  Future<void> _supprimer(BuildContext context) async {
    final l10n = context.l10n;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.reserveSupprimerTitre),
        content: Text(
          l10n.reserveSupprimerConfirm,
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
    await context.read<ReserveDetailCubit>().supprimer();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final peutModifier = role?.estOperationnelOuControle ?? false;
    final peutSupprimer = role?.estOperationnel ?? false;

    // Le menu reste TOUJOURS présent : le QR code n'est gardé par aucun rôle,
    // il y a donc au minimum une entrée à proposer.

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textPrimary),
      tooltip: l10n.reserveActionsTitre,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (choix) {
        switch (choix) {
          case 'modifier':
            ouvrirModificationReserve(context, reserve);
          case 'qr':
            ouvrirQrReserve(context, reserve);
          case 'dupliquer':
            _dupliquer(context);
          case 'supprimer':
            _supprimer(context);
        }
      },
      itemBuilder: (context) => [
        if (peutModifier)
          PopupMenuItem(
            value: 'modifier',
            child: Row(
              children: [
                const Icon(Icons.edit_outlined, size: 19, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Text(l10n.reserveModifierTitre),
              ],
            ),
          ),
        // Le QR est en LECTURE seule côté serveur (aucun `requireRole` sur
        // `GET /reserves/:id/qr`) : tout le monde peut l'afficher, y compris
        // un sous-traitant venu poser l'étiquette.
        PopupMenuItem(
          value: 'qr',
          child: Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, size: 19, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Text(l10n.reserveQrTitre),
            ],
          ),
        ),
        if (peutModifier)
          PopupMenuItem(
            value: 'dupliquer',
            child: Row(
              children: [
                const Icon(Icons.copy_all_rounded, size: 19, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Text(l10n.reserveDupliquerTitre),
              ],
            ),
          ),
        if (peutSupprimer)
          PopupMenuItem(
            value: 'supprimer',
            child: Row(
              children: [
                const Icon(Icons.delete_outline_rounded, size: 19, color: AppColors.danger),
                const SizedBox(width: 12),
                Text(l10n.reserveSupprimerTitre, style: const TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Section des affectations — branche les gardes de rôle sur le widget
/// partagé, qui ne connaît que des booléens.
class _BlocAffectations extends StatelessWidget {
  final Reserve reserve;
  const _BlocAffectations({required this.reserve});

  @override
  Widget build(BuildContext context) {
    final role = context.select((AuthBloc b) => b.state.utilisateur?.role);
    return SectionAffectations(
      // Miroir de `requireRole(...RESERVE_INTERVENANTS)` sur POST
      // /reserves/:id/affectations et de `...OPERATIONNEL` sur le DELETE.
      peutAffecter: role?.peutIntervenirSurReserves ?? false,
      peutRetirer: role?.estOperationnel ?? false,
      onAjouter: () => ouvrirAffectationReserve(context),
    );
  }
}

class _TitreSection extends StatelessWidget {
  final String texte;
  const _TitreSection(this.texte);

  @override
  Widget build(BuildContext context) {
    return Text(texte, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary));
  }
}

IconData _iconeHistorique(String action) {
  switch (action) {
    case 'creation':
      return Icons.add_circle_outline;
    case 'modification':
      return Icons.edit_outlined;
    case 'statut':
      return Icons.published_with_changes_outlined;
    case 'commentaire':
      return Icons.chat_bubble_outline;
    case 'validation':
      return Icons.check_circle_outline;
    case 'refus':
      return Icons.cancel_outlined;
    case 'suppression':
      return Icons.delete_outline;
    default:
      return Icons.circle_outlined;
  }
}

Color _couleurHistorique(String action) {
  switch (action) {
    case 'validation':
      return AppColors.success;
    case 'refus':
    case 'suppression':
      return AppColors.danger;
    case 'statut':
      return AppColors.warning;
    default:
      return AppColors.primary;
  }
}

/// Écran 9 de la maquette — chronologie verticale : un point coloré par
/// entrée, relié par un trait, la plus récente en tête (l'appelant a déjà
/// inversé la liste).
class _Timeline extends StatelessWidget {
  final List<ReserveHistoriqueEntry> entrees;
  const _Timeline({required this.entrees});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy à HH:mm');
    return Column(
      children: [
        for (var i = 0; i < entrees.length; i++)
          _LigneTimeline(
            entree: entrees[i],
            dateFormattee: entrees[i].createdAt != null ? df.format(entrees[i].createdAt!) : null,
            estDerniere: i == entrees.length - 1,
          ),
      ],
    );
  }
}

class _LigneTimeline extends StatelessWidget {
  final ReserveHistoriqueEntry entree;
  final String? dateFormattee;
  final bool estDerniere;
  const _LigneTimeline({required this.entree, required this.dateFormattee, required this.estDerniere});

  @override
  Widget build(BuildContext context) {
    final couleur = _couleurHistorique(entree.action);
    final l10n = context.l10n;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: couleur.withValues(alpha: 0.14), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(_iconeHistorique(entree.action), size: 15, color: couleur),
              ),
              if (!estDerniere)
                Expanded(
                  child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: AppColors.border),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entree.libelle(l10n), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (dateFormattee != null) dateFormattee!,
                      if (entree.utilisateur != null) l10n.reserveDetailPar(entree.utilisateur!.nomComplet),
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valeur;
  final bool dernier;
  const _InfoRow({required this.icon, required this.label, required this.valeur, this.dernier = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: dernier ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          const Spacer(),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
