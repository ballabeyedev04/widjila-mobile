import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../document/domain/entities/document.dart';
import '../../../document/presentation/pages/document_viewer_page.dart';
import '../../domain/entities/configuration_rapport.dart';
import '../../domain/entities/etat_rapport.dart';
import '../../domain/entities/modele_rapport.dart';
import '../../domain/entities/rapport.dart';
import '../../domain/entities/suivi_rapport.dart';
import '../cubit/rapport_detail_cubit.dart';
import '../widgets/feuille_envoi_rapport.dart';
import '../widgets/feuille_partage_rapport.dart';

/// Le détail d'un rapport — ce qu'on en FAIT une fois configuré :
/// le voir, le télécharger (PDF ou Excel), l'envoyer (§ 13), le partager par
/// lien (§ 14), le régénérer — en nouvelle version s'il a été diffusé
/// (§ 18) —, le dupliquer, en tirer un rapport par entreprise (§ 15), et
/// relire son historique.
class RapportDetailPage extends StatelessWidget {
  final String rapportId;
  final String? chantierNom;

  const RapportDetailPage({super.key, required this.rapportId, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    // Même garde que le serveur (`PILOTAGE`) : l'écran n'affiche pas un geste
    // qui serait refusé. Le serveur tranche de toute façon.
    final peutPiloter = context.select((AuthBloc b) => b.state.utilisateur?.role)?.peutPiloter ?? false;

    return BlocProvider(
      create: (_) => RapportDetailCubit(
        rapportId: rapportId,
        getDetail: sl(),
        getHistorique: sl(),
        getPartages: sl(),
        genererRapport: sl(),
        dupliquerRapport: sl(),
        archiverRapport: sl(),
        genererParEntreprise: sl(),
        partagerRapport: sl(),
        revoquerPartage: sl(),
        avecPartages: peutPiloter,
      )..charger(),
      child: _VueDetail(peutPiloter: peutPiloter, chantierNom: chantierNom),
    );
  }
}

String _date(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(l.day)}/${deux(l.month)}/${l.year} ${deux(l.hour)}:${deux(l.minute)}';
}

/// Nom de fichier lisible et sûr — le titre, sans caractère interdit.
String _nomFichier(Rapport r, AppLocalizations l10n, String extension) {
  final base = r.titre(l10n).replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
  return '${base.isEmpty ? 'rapport' : base}-v${r.version}.$extension';
}

class _VueDetail extends StatelessWidget {
  final bool peutPiloter;
  final String? chantierNom;
  const _VueDetail({required this.peutPiloter, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<RapportDetailCubit, RapportDetailState>(
          // L'échec du CHARGEMENT est déjà dit par l'écran d'erreur : le
          // répéter dans une notification afficherait deux fois le même
          // message. Seuls les échecs d'une ACTION passent par ici.
          listenWhen: (a, b) =>
              (b.erreur != null && b.statut == StatutDetailRapport.succes) ||
              b.evenement != EvenementDetailRapport.aucun,
          listener: (context, state) => _surEvenement(context, state),
          builder: (context, state) {
            final cubit = context.read<RapportDetailCubit>();
            return Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(
                    titre: chantierNom ?? l10n.rapportDetailTitre,
                    avecRetour: true,
                    avecCloche: false,
                  ),
                ),
                if (state.occupe) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: switch (state.statut) {
                    StatutDetailRapport.chargement => const LoadingList(),
                    StatutDetailRapport.erreur => ErrorView(
                        message: state.erreur ?? l10n.commonError,
                        onRetry: cubit.charger,
                      ),
                    StatutDetailRapport.succes => RefreshIndicator(
                        onRefresh: cubit.charger,
                        child: ContenuCentre(child: _Corps(state: state, peutPiloter: peutPiloter)),
                      ),
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _surEvenement(BuildContext context, RapportDetailState state) {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    if (state.erreur != null) {
      messenger.showSnackBar(SnackBar(content: Text(AppAlert.messageLisible(l10n, state.erreur!))));
      return;
    }
    switch (state.evenement) {
      case EvenementDetailRapport.genere:
        AppAlert.confirmation(context, messenger: messenger, message: l10n.rapportGenere);
      case EvenementDetailRapport.nouvelleVersion:
        AppAlert.confirmation(context, messenger: messenger, message: l10n.rapportNouvelleVersion);
      case EvenementDetailRapport.archive:
        AppAlert.confirmation(context, messenger: messenger, message: l10n.rapportArchiveOk);
      case EvenementDetailRapport.revoque:
        AppAlert.confirmation(context, messenger: messenger, message: l10n.rapportPartageRevoque);
      case EvenementDetailRapport.duplique:
        AppAlert.confirmation(context, messenger: messenger, message: l10n.rapportDuplique);
        final copie = state.copie;
        // La copie est un brouillon : on l'ouvre directement dans
        // l'assistant, c'est là qu'on la retouche.
        if (copie != null) context.push<Rapport>('/chantiers/${copie.chantierId}/rapports/nouveau', extra: copie);
      case EvenementDetailRapport.parEntreprise:
        final r = state.parEntreprise;
        if (r == null) return;
        AppAlert.confirmation(
          context,
          messenger: messenger,
          duration: const Duration(seconds: 6),
          message: [
            l10n.rapportParEntrepriseResultat(r.nbRapports),
            if (r.reservesSansEntreprise > 0) l10n.rapportParEntrepriseSans(r.reservesSansEntreprise),
          ].join('\n'),
        );
      case EvenementDetailRapport.aucun:
        break;
    }
  }
}

class _Corps extends StatelessWidget {
  final RapportDetailState state;
  final bool peutPiloter;
  const _Corps({required this.state, required this.peutPiloter});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = state.rapport!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Entete(rapport: r),
        const SizedBox(height: 12),
        if (r.etat == EtatRapport.echec && r.erreur != null)
          _Alerte(texte: l10n.rapportEchecMotif(r.erreur!), couleur: AppColors.danger),
        if (!r.estGenere && r.etat != EtatRapport.echec) _Alerte(texte: l10n.rapportNonGenere, couleur: AppColors.textMuted),
        if (r.estDiffuse) _Alerte(texte: l10n.rapportDiffuseAvertissement, couleur: AppColors.primary),
        if (r.etat == EtatRapport.archive) _Alerte(texte: l10n.rapportArchiveInfo, couleur: AppColors.textMuted),
        if (r.estGenere) ...[
          _TitreSection(l10n.rapportSectionFichiers),
          _Action(
            icone: Icons.visibility_outlined,
            libelle: l10n.rapportActionVoirPdf,
            onTap: () => _voir(context, r),
          ),
          _Action(
            icone: Icons.download_rounded,
            libelle: l10n.rapportActionTelechargerPdf,
            onTap: () => _telecharger(context, r, excel: false),
          ),
          if (r.aExcel)
            _Action(
              icone: Icons.table_chart_outlined,
              libelle: l10n.rapportActionTelechargerExcel,
              onTap: () => _telecharger(context, r, excel: true),
            ),
        ],
        if (peutPiloter && r.estGenere) ...[
          _TitreSection(l10n.rapportSectionDiffusion),
          _Action(
            icone: Icons.mail_outline_rounded,
            libelle: l10n.rapportActionEnvoyer,
            onTap: () => afficherFeuilleEnvoiRapport(
              context,
              r.id,
              apresEnvoi: context.read<RapportDetailCubit>().charger,
            ),
          ),
          _Action(
            icone: Icons.link_rounded,
            libelle: l10n.rapportActionPartager,
            onTap: () => _partager(context),
          ),
          _Partages(partages: state.partages),
        ],
        if (peutPiloter) _Actions(rapport: r, occupe: state.occupe),
        _TitreSection(l10n.rapportHistoriqueTitre),
        if (state.historique.isEmpty)
          Text(l10n.rapportHistoriqueVide, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))
        else
          for (final h in state.historique.reversed) _LigneHistorique(entree: h),
      ],
    );
  }

  Future<void> _voir(BuildContext context, Rapport r) {
    final l10n = context.l10n;
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DocumentViewerPage(
        document: ChantierDocument(
          id: r.id,
          chantierId: r.chantierId,
          nomFichier: _nomFichier(r, l10n, 'pdf'),
          fichierUrl: r.fichierUrl,
          mimeType: 'application/pdf',
          taille: r.taillePdf,
        ),
      ),
    ));
  }

  /// Téléchargement par la route JOURNALISÉE du § 9 (`/download`) : le § 18
  /// veut savoir qui a récupéré le document.
  Future<void> _telecharger(BuildContext context, Rapport r, {required bool excel}) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(l10n.documentTelechargementEnCours)));

    final ouverture = sl<OuvertureFichier>();
    final octets = await ouverture.telecharger(url: '/reports/${r.id}/download${excel ? '?format=xlsx' : ''}');
    messenger.hideCurrentSnackBar();

    await octets.fold<Future<void>>(
      (f) async => messenger.showSnackBar(SnackBar(content: Text(AppAlert.messageLisible(l10n, f.errorMessage)))),
      (donnees) async {
        final ok = await ouverture.enregistrer(octets: donnees, nomFichier: _nomFichier(r, l10n, excel ? 'xlsx' : 'pdf'));
        ok.fold(
          (_) => messenger.showSnackBar(SnackBar(content: Text(l10n.documentEnregistrementEchec))),
          (enregistre) {
            if (enregistre) AppAlert.confirmation(context, messenger: messenger, message: l10n.documentEnregistre);
          },
        );
      },
    );
  }

  Future<void> _partager(BuildContext context) {
    final cubit = context.read<RapportDetailCubit>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => FeuillePartageRapport(creer: cubit.partager),
    );
  }
}

class _Entete extends StatelessWidget {
  final Rapport rapport;
  const _Entete({required this.rapport});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = rapport;
    final modele = r.modele;

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
          Text(r.titre(l10n), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (modele != null && (r.nom ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(modele.label(l10n), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PastilleEtat(etat: r.etat),
              _Pastille(texte: l10n.rapportVersion(r.version), couleur: AppColors.textMuted),
              for (final f in r.formats) _Pastille(texte: f.label(l10n), couleur: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 10),
          if (r.genereLe != null)
            Text(l10n.rapportGenereLe(_date(r.genereLe)), style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted))
          else if (r.createdAt != null)
            Text(l10n.rapportCreeLe(_date(r.createdAt)), style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          if (r.nbReserves != null)
            Text(l10n.rapportNbReserves(r.nbReserves!), style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          if (r.entrepriseNom != null)
            Text(l10n.rapportPourEntreprise(r.entrepriseNom!),
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

/// Les gestes de production — réservés au pilotage.
class _Actions extends StatelessWidget {
  final Rapport rapport;
  final bool occupe;
  const _Actions({required this.rapport, required this.occupe});

  Future<bool> _confirmer(BuildContext context, String message) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogue) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogue).pop(false), child: Text(l10n.rapportAnnuler)),
          FilledButton(onPressed: () => Navigator.of(dialogue).pop(true), child: Text(l10n.rapportConfirmer)),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RapportDetailCubit>();
    final r = rapport;
    final archive = r.etat == EtatRapport.archive;

    Future<void> generer() async {
      final nouveau = await cubit.generer();
      // Une nouvelle version est un AUTRE rapport : on bascule dessus, pour
      // ne pas laisser l'utilisateur sur la version archivée.
      if (nouveau != null && nouveau.id != r.id && context.mounted) {
        context.pushReplacement('/chantiers/${nouveau.chantierId}/rapports/${nouveau.id}');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitreSection(l10n.rapportSectionActions),
        if (!archive)
          _Action(
            icone: r.estGenere ? Icons.refresh_rounded : Icons.picture_as_pdf_rounded,
            libelle: r.estGenere ? l10n.rapportActionRegenerer : l10n.rapportActionGenerer,
            onTap: occupe ? null : generer,
          ),
        if (!r.estDiffuse && !archive)
          _Action(
            icone: Icons.tune_rounded,
            libelle: l10n.rapportActionModifier,
            onTap: occupe
                ? null
                : () async {
                    final genere = await context.push<Rapport>(
                      '/chantiers/${r.chantierId}/rapports/nouveau',
                      extra: r,
                    );
                    if (context.mounted) cubit.charger();
                    if (genere != null && genere.id != r.id && context.mounted) {
                      context.pushReplacement('/chantiers/${genere.chantierId}/rapports/${genere.id}');
                    }
                  },
          ),
        _Action(
          icone: Icons.copy_all_rounded,
          libelle: l10n.rapportActionDupliquer,
          onTap: occupe ? null : cubit.dupliquer,
        ),
        _Action(
          icone: Icons.business_rounded,
          libelle: l10n.rapportActionParEntreprise,
          onTap: occupe
              ? null
              : () async {
                  if (await _confirmer(context, l10n.rapportParEntrepriseConfirmer)) {
                    await cubit.genererRapportsParEntreprise();
                  }
                },
        ),
        if (!archive)
          _Action(
            icone: Icons.archive_outlined,
            libelle: l10n.rapportActionArchiver,
            onTap: occupe
                ? null
                : () async {
                    if (await _confirmer(context, l10n.rapportArchiverConfirmer)) await cubit.archiver();
                  },
          ),
      ],
    );
  }
}

class _Partages extends StatelessWidget {
  final List<PartageRapport> partages;
  const _Partages({required this.partages});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RapportDetailCubit>();

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.rapportPartagesTitre,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted),
          ),
          if (partages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(l10n.rapportPartagesVide, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            )
          else
            for (final p in partages)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  p.actif ? Icons.link_rounded : Icons.link_off_rounded,
                  color: p.actif ? AppColors.primary : AppColors.textMuted,
                ),
                title: Text(p.actif ? l10n.rapportPartageActif : l10n.rapportPartageInactif),
                subtitle: Text(
                  [
                    if (p.expireLe != null) l10n.rapportPartageExpireLe(_date(p.expireLe)) else l10n.rapportPartageSansExpiration,
                    l10n.rapportPartageAcces(p.nbAcces),
                    if (p.authentificationRequise) l10n.rapportPartageProtege,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: p.actif
                    ? TextButton(onPressed: () => cubit.revoquer(p.id), child: Text(l10n.rapportPartageRevoquer))
                    : null,
              ),
        ],
      ),
    );
  }
}

class _LigneHistorique extends StatelessWidget {
  final EntreeHistoriqueRapport entree;
  const _LigneHistorique({required this.entree});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 8, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entree.libelle, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(
                  [_date(entree.date), if (entree.acteur != null) entree.acteur!].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PastilleEtat extends StatelessWidget {
  final EtatRapport etat;
  const _PastilleEtat({required this.etat});

  @override
  Widget build(BuildContext context) {
    final couleur = switch (etat) {
      EtatRapport.genere => Colors.green.shade700,
      EtatRapport.envoye => AppColors.primary,
      EtatRapport.echec => AppColors.danger,
      EtatRapport.generation || EtatRapport.enAttente => Colors.orange.shade800,
      EtatRapport.brouillon || EtatRapport.archive => AppColors.textMuted,
    };
    return _Pastille(texte: etat.label(context.l10n), couleur: couleur);
  }
}

class _Pastille extends StatelessWidget {
  final String texte;
  final Color couleur;
  const _Pastille({required this.texte, required this.couleur});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(texte, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: couleur)),
      );
}

class _Alerte extends StatelessWidget {
  final String texte;
  final Color couleur;
  const _Alerte({required this.texte, required this.couleur});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(texte, style: TextStyle(fontSize: 13, color: couleur, height: 1.35)),
      );
}

class _TitreSection extends StatelessWidget {
  final String texte;
  const _TitreSection(this.texte);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(texte, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );
}

class _Action extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final VoidCallback? onTap;
  const _Action({required this.icone, required this.libelle, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        enabled: onTap != null,
        leading: Icon(icone, color: AppColors.primary),
        title: Text(libelle, style: const TextStyle(fontSize: 14)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        onTap: onTap,
      );
}
