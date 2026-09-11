import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/network/forcer_reseau.dart';
import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/etat_rapport.dart';
import '../../domain/entities/rapport.dart';
import '../../domain/usecases/rapport_usecases.dart';
import '../cubit/rapports_cubit.dart';
import '../widgets/feuille_envoi_rapport.dart';

/// Les rapports d'un chantier.
///
/// « + Nouveau rapport » ouvre le parcours du § 3 du cahier des charges
/// (modèle → filtres → sections → prévisualiser → générer). Une carte ouvre
/// le détail du rapport ; son menu garde les gestes rapides — aperçu,
/// téléchargement, envoi.
class RapportsListPage extends StatelessWidget {
  final String chantierId;
  final String? chantierNom;

  const RapportsListPage({super.key, required this.chantierId, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => RapportsCubit(
        getRapports: sl<GetRapports>(),
        genererRapport: sl<GenererRapport>(),
        supprimerRapport: sl<SupprimerRapport>(),
        chantierId: chantierId,
      )..charger(),
      child: _Vue(chantierId: chantierId, chantierNom: chantierNom),
    );
  }
}

class _Vue extends StatelessWidget {
  final String chantierId;
  final String? chantierNom;
  const _Vue({required this.chantierId, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final peutPiloter = context.select((AuthBloc b) => b.state.utilisateur?.role)?.peutPiloter ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<RapportsCubit, RapportsState>(
          builder: (context, state) {
            return Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(
                    titre: chantierNom ?? l10n.rapportsTitre,
                    avecRetour: true,
                    avecCloche: false,
                  ),
                ),
                Expanded(child: _Corps(state: state, chantierNom: chantierNom)),
              ],
            );
          },
        ),
      ),
      // La production est réservée au pilotage, comme côté serveur.
      floatingActionButton: peutPiloter
          ? Builder(
              builder: (context) => FloatingActionButton.extended(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                onPressed: () => _nouveauRapport(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.rapportNouveau),
              ),
            )
          : null,
    );
  }

  Future<void> _nouveauRapport(BuildContext context) async {
    final cubit = context.read<RapportsCubit>();
    final chemin = Uri(
      path: '/chantiers/$chantierId/rapports/nouveau',
      queryParameters: {'nom': ?chantierNom},
    ).toString();

    final cree = await context.push<Rapport>(chemin);
    if (!context.mounted) return;
    cubit.charger();
    // Le rapport tout juste généré s'ouvre directement : c'est lui qu'on
    // veut voir, envoyer ou partager.
    if (cree != null) context.push('/chantiers/$chantierId/rapports/${cree.id}');
  }
}

/// Ouverture du PDF dans l'application du téléphone.
Future<void> _ouvrir(BuildContext context, Rapport rapport) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  if (!rapport.estGenere) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.rapportNonGenere)));
    return;
  }
  messenger.showSnackBar(SnackBar(content: Text(l10n.documentOuvertureEnCours)));

  final resultat = await sl<OuvertureFichier>().ouvrir(url: rapport.fichierUrl, nomFichier: _nomFichier(rapport));

  messenger.hideCurrentSnackBar();
  resultat.fold(
    (failure) => messenger.showSnackBar(SnackBar(content: Text(AppAlert.messageLisible(l10n, failure.errorMessage)))),
    (issue) {
      if (issue == ResultatOuverture.aucuneApplication) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.documentAucuneApplication)));
      }
    },
  );
}

/// Copie durable du PDF, à l'endroit choisi par l'utilisateur.
Future<void> _telecharger(BuildContext context, Rapport rapport) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  if (!rapport.estGenere) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.rapportNonGenere)));
    return;
  }
  messenger.showSnackBar(SnackBar(content: Text(l10n.documentTelechargementEnCours)));

  final octets = await sl<OuvertureFichier>().telecharger(url: rapport.fichierUrl);

  messenger.hideCurrentSnackBar();
  await octets.fold<Future<void>>(
    (failure) async => messenger.showSnackBar(SnackBar(content: Text(AppAlert.messageLisible(l10n, failure.errorMessage)))),
    (donnees) async {
      final enregistre = await sl<OuvertureFichier>().enregistrer(octets: donnees, nomFichier: _nomFichier(rapport));
      enregistre.fold(
        (_) => messenger.showSnackBar(SnackBar(content: Text(l10n.documentEnregistrementEchec))),
        (ok) {
          if (ok) messenger.showSnackBar(SnackBar(content: Text(l10n.documentEnregistre)));
        },
      );
    },
  );
}

String _nomFichier(Rapport rapport) => 'rapport-${rapport.modele?.name ?? rapport.type.raw}-v${rapport.version}.pdf';

class _Corps extends StatelessWidget {
  final RapportsState state;
  final String? chantierNom;
  const _Corps({required this.state, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RapportsCubit>();
    // Diffuser un rapport à des tiers engage l'organisation : même garde que
    // côté serveur (`PILOTAGE`). Le serveur tranche, l'écran ne fait
    // qu'éviter de proposer un geste qui sera refusé.
    final role = context.select((AuthBloc b) => b.state.utilisateur?.role);
    final peutEnvoyer = role?.peutPiloter ?? false;

    if (state.status == RapportsStatus.chargement && state.items.isEmpty) {
      return const LoadingList();
    }

    if (state.status == RapportsStatus.erreur && state.items.isEmpty) {
      return ErrorView(message: state.erreur ?? l10n.commonError, onRetry: cubit.charger);
    }

    if (state.items.isEmpty) {
      return EtatVideIllustre(
        motif: MotifVide.document,
        titre: l10n.rapportsAucun,
        description: l10n.rapportsAucunMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: forcerReseau(cubit.charger),
      child: ContenuCentre(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) => _CarteRapport(
            rapport: state.items[index],
            peutEnvoyer: peutEnvoyer,
            chantierNom: chantierNom,
          ),
        ),
      ),
    );
  }
}

class _CarteRapport extends StatelessWidget {
  final Rapport rapport;
  final bool peutEnvoyer;
  final String? chantierNom;
  const _CarteRapport({required this.rapport, required this.peutEnvoyer, this.chantierNom});

  Future<void> _ouvrirDetail(BuildContext context) async {
    final cubit = context.read<RapportsCubit>();
    final chemin = Uri(
      path: '/chantiers/${rapport.chantierId}/rapports/${rapport.id}',
      queryParameters: {'nom': ?chantierNom},
    ).toString();
    await context.push(chemin);
    if (context.mounted) cubit.charger();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final details = [
      rapport.etat.label(l10n),
      if (rapport.version > 1) l10n.rapportVersion(rapport.version),
      if ((rapport.genereLe ?? rapport.createdAt) != null) _formaterDate((rapport.genereLe ?? rapport.createdAt)!),
      if (rapport.nbReserves != null) l10n.rapportNbReserves(rapport.nbReserves!),
    ].join(' · ');

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _ouvrirDetail(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (rapport.etat == EtatRapport.echec ? AppColors.danger : AppColors.primary)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  rapport.estGenere ? Icons.picture_as_pdf_rounded : Icons.edit_note_rounded,
                  size: 21,
                  color: rapport.etat == EtatRapport.echec ? AppColors.danger : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Un type inconnu de cette version est affiché tel quel
                      // plutôt que travesti en « Réserves ».
                      rapport.titre(l10n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              // Menu proposé à TOUS : sans lui, un rôle sans droit d'envoi ne
              // pouvait ni télécharger le rapport ni le garder sur son
              // téléphone. Seul l'envoi par e-mail reste réservé au pilotage.
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textMuted),
                onSelected: (choix) {
                  switch (choix) {
                    case 'apercu':
                      _ouvrir(context, rapport);
                    case 'telecharger':
                      _telecharger(context, rapport);
                    default:
                      afficherFeuilleEnvoiRapport(context, rapport.id,
                          apresEnvoi: context.read<RapportsCubit>().charger);
                  }
                },
                itemBuilder: (_) => [
                  _entree('apercu', Icons.visibility_outlined, l10n.rapportPrevisualiser),
                  _entree('telecharger', Icons.download_rounded, l10n.documentActionTelecharger),
                  if (peutEnvoyer) _entree('envoi', Icons.mail_outline_rounded, l10n.rapportEnvoyerMail),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static PopupMenuItem<String> _entree(String valeur, IconData icone, String libelle) => PopupMenuItem(
        value: valeur,
        child: Row(
          children: [
            Icon(icone, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(libelle, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  static String _formaterDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
