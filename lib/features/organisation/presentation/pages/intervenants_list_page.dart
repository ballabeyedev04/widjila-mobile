import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/couleurs_avatar.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../referentiel/domain/entities/type_referentiel.dart';
import '../../../referentiel/presentation/cubit/types_referentiel_cubit.dart';
import '../../domain/entities/partenaire.dart';
import '../cubit/partenaires_cubit.dart';
import 'ajouter_partenaire_sheet.dart';
import 'detail_partenaire_sheet.dart';

/// Teinte du badge par type d'intervenant.
BadgeTone toneTypePartenaire(PartenaireType type) => switch (type) {
      PartenaireType.client => BadgeTone.neutral,
      PartenaireType.maitreOuvrage => BadgeTone.primary,
      PartenaireType.maitreOeuvre => BadgeTone.success,
      PartenaireType.sousTraitant => BadgeTone.warning,
      PartenaireType.fournisseur => BadgeTone.info,
      PartenaireType.bureauControle => BadgeTone.success,
      PartenaireType.autre => BadgeTone.neutral,
    };

/// Icône par type — donne à chaque famille d'intervenant une silhouette
/// reconnaissable, dans la liste comme dans le sélecteur du formulaire.
IconData iconeTypePartenaire(PartenaireType type) => switch (type) {
      PartenaireType.client => Icons.person_outline_rounded,
      PartenaireType.maitreOuvrage => Icons.account_balance_outlined,
      PartenaireType.maitreOeuvre => Icons.architecture_rounded,
      PartenaireType.sousTraitant => Icons.engineering_outlined,
      PartenaireType.fournisseur => Icons.local_shipping_outlined,
      PartenaireType.bureauControle => Icons.verified_outlined,
      PartenaireType.autre => Icons.more_horiz_rounded,
    };

String libelleStatutPartenaire(AppLocalizations l10n, bool actif) =>
    actif ? l10n.partenaireStatutActif : l10n.partenaireStatutArchive;

/// MIROIR de `requireRole('ChefProjet', 'ConducteurTravaux', 'MaitreOuvrage',
/// 'MaitreOeuvre')` posé sur `POST /organisation/partenaires` et
/// `PUT /partenaires/:id` (partenaire.route.js).
///
/// Volontairement plus large que [UserRoleX.estOperationnel], qui exclut le
/// maître d'ouvrage : lui refuser le bouton ici l'aurait privé d'une action
/// que le serveur lui accorde. Le bureau de contrôle, lui, consulte l'annuaire
/// sans le modifier.
bool peutGererPartenaires(UserRole? role) =>
    role != null && (role.estOperationnel || role == UserRole.maitreOuvrage);

/// Ouvre le formulaire d'ajout d'un intervenant.
///
/// Fonction de bibliothèque plutôt que méthode privée de la vue : le bouton
/// flottant ET le bouton de l'état vide l'appellent, et ils ne vivent pas
/// dans le même widget.
void _ouvrirFormulairePartenaire(BuildContext context) {
  final cubit = context.read<PartenairesCubit>();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(value: cubit, child: const AjouterPartenaireSheet()),
  );
}

/// Écran 8 de la maquette — les entreprises et partenaires du projet.
class IntervenantsListPage extends StatelessWidget {
  const IntervenantsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<PartenairesCubit>()..charger()),
        // Types d'intervenant : le filtre en a besoin pour proposer les types
        // ajoutés depuis l'administration, que l'énumération Dart ignore.
        BlocProvider(
          create: (_) => sl<TypesReferentielCubit>(param1: ReferentielType.intervenant)..charger(),
        ),
      ],
      child: const _IntervenantsView(),
    );
  }
}

class _IntervenantsView extends StatelessWidget {
  const _IntervenantsView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final peutGerer = peutGererPartenaires(context.select((AuthBloc b) => b.state.utilisateur?.role));

    return BlocConsumer<PartenairesCubit, PartenairesState>(
      listenWhen: (a, b) => a.soumissionStatus != b.soumissionStatus,
      listener: (context, state) {
        if (state.soumissionStatus == SoumissionPartenaireStatus.succes) {
          AppAlert.success(context, message: l10n.partenaireAjoutSucces);
          context.read<PartenairesCubit>().reinitialiserSoumission();
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _EnTete(),
                if (state.status == PartenairesStatus.succes) ...[
                  const _BarreRecherche(),
                  _Compteur(affiches: state.itemsFiltres.length, actifs: state.nombreActifs),
                  if (state.filtreType != null || state.filtreActif != null) const _PucesFiltres(),
                ],
                Expanded(child: _Corps(state: state, peutGerer: peutGerer)),
              ],
            ),
          ),
          floatingActionButton: peutGerer
              ? FloatingActionButton.extended(
                  onPressed: () => _ouvrirFormulairePartenaire(context),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shape: const StadiumBorder(),
                  icon: const Icon(Icons.add_business_rounded),
                  label: Text(l10n.commonAdd, style: const TextStyle(fontWeight: FontWeight.w700)),
                )
              : null,
        );
      },
    );
  }
}

/// Barre de titre — flèche de retour et titre, comme l'écran Équipe.
class _EnTete extends StatelessWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
            tooltip: l10n.commonBack,
            // L'écran est atteignable par `go` depuis l'éventail d'actions —
            // il n'y a alors rien à dépiler et `pop()` lèverait une exception.
            // On retombe sur le tableau de bord, destination d'accueil de la
            // coquille.
            onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.dashboard),
          ),
          Expanded(
            child: Text(
              l10n.actionIntervenants,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Champ de recherche + bouton de filtre (type et activité).
class _BarreRecherche extends StatelessWidget {
  const _BarreRecherche();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtreActif = context.select(
      (PartenairesCubit c) => c.state.filtreType != null || c.state.filtreActif != null,
    );

    return ContenuCentre(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => context.read<PartenairesCubit>().rechercher(v),
                decoration: InputDecoration(
                  hintText: l10n.partenaireRechercheHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 21, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: filtreActif ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              child: InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () => ouvrirFiltresPartenaires(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 19,
                        color: filtreActif ? AppColors.primary : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        l10n.equipeFiltrer,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: filtreActif ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Compteur extends StatelessWidget {
  final int affiches;
  final int actifs;

  const _Compteur({required this.affiches, required this.actifs});

  @override
  Widget build(BuildContext context) {
    return ContenuCentre(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            const Icon(Icons.handshake_rounded, size: 19, color: AppColors.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                context.l10n.partenaireCompteur(affiches),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
            ),
            // Rappel du nombre d'actifs : c'est le chiffre qui compte pour
            // l'exploitation, et il reste visible même quand un filtre réduit
            // la liste affichée.
            StatusBadge(label: '$actifs ${context.l10n.partenaireFiltreActifs}', tone: BadgeTone.success),
          ],
        ),
      ),
    );
  }
}

/// Rappel des filtres posés, chacun retirable d'un tap.
///
/// Sans cette ligne, un filtre resté actif explique silencieusement une liste
/// courte — l'utilisateur croit avoir perdu des intervenants.
class _PucesFiltres extends StatelessWidget {
  const _PucesFiltres();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PartenairesCubit>();
    final state = context.watch<PartenairesCubit>().state;

    return ContenuCentre(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (state.filtreType != null)
              _PuceFiltre(
                // L'icône passe par l'énumération : un type ajouté par le
                // client n'en a pas de dédiée et retombe sur la générique.
                icone: iconeTypePartenaire(PartenaireTypeX.fromString(state.filtreType)),
                // Le LIBELLÉ, lui, vient du référentiel : c'est
                // l'administrateur qui le fixe. `libelle()` retombe sur le
                // code si le type a été désactivé depuis.
                libelle: context.watch<TypesReferentielCubit>().state.libelle(state.filtreType),
                onRetrait: () => cubit.filtrerParType(null),
              ),
            if (state.filtreActif != null)
              _PuceFiltre(
                icone: state.filtreActif! ? Icons.check_circle_outline_rounded : Icons.inventory_2_outlined,
                libelle: state.filtreActif! ? l10n.partenaireFiltreActifs : l10n.partenaireFiltreArchives,
                onRetrait: () => cubit.filtrerParActivite(null),
              ),
          ],
        ),
      ),
    );
  }
}

class _PuceFiltre extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final VoidCallback onRetrait;

  const _PuceFiltre({required this.icone, required this.libelle, required this.onRetrait});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onRetrait,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 14, color: AppColors.primaryDark),
              const SizedBox(width: 6),
              Text(
                libelle,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.close_rounded, size: 15, color: AppColors.primaryDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _Corps extends StatelessWidget {
  final PartenairesState state;
  final bool peutGerer;

  const _Corps({required this.state, required this.peutGerer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    switch (state.status) {
      case PartenairesStatus.initial:
      case PartenairesStatus.chargement:
        return const LoadingList(itemHeight: 104);
      case PartenairesStatus.erreur:
        return ErrorView(
          message: state.erreur ?? l10n.commonErrorUnknown,
          onRetry: () => context.read<PartenairesCubit>().charger(),
        );
      case PartenairesStatus.succes:
        final items = state.itemsFiltres;
        if (items.isEmpty) {
          // Distinguer « aucun intervenant » de « aucun résultat » : le
          // premier invite à créer, le second à élargir la recherche.
          return EtatVideIllustre(
            motif: state.filtreEnPlace ? MotifVide.recherche : MotifVide.intervenant,
            titre: state.filtreEnPlace ? l10n.commonNoResults : l10n.partenaireAucun,
            description:
                state.filtreEnPlace ? l10n.planEssayerAutreMotCle : l10n.partenaireAucunDescription,
            // Deux situations, deux actions : un filtre trop étroit s'efface,
            // un annuaire vide se remplit. Proposer « Ajouter » à quelqu'un
            // dont la recherche ne donne rien serait à côté de la question.
            cta: state.filtreEnPlace
                ? BoutonAction(
                    icon: Icons.filter_alt_off_outlined,
                    label: l10n.partenaireFiltreReinitialiser,
                    onTap: () => context.read<PartenairesCubit>().reinitialiserFiltres(),
                  )
                : (peutGerer
                    ? BoutonAction(
                        icon: Icons.add_business_rounded,
                        label: l10n.partenaireFormBouton,
                        onTap: () => _ouvrirFormulairePartenaire(context),
                      )
                    : null),
          );
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => context.read<PartenairesCubit>().charger(),
          child: ContenuCentre(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == items.length) return const _PiedDePage();
                return _CarteIntervenant(partenaire: items[i], peutGerer: peutGerer);
              },
            ),
          ),
        );
    }
  }
}

/// Carte d'un intervenant — même grammaire visuelle que la carte de membre
/// (liseré coloré, avatar à initiales, pastilles, bouton « Détail ») pour que
/// les deux annuaires se lisent de la même façon.
class _CarteIntervenant extends StatelessWidget {
  final Partenaire partenaire;
  final bool peutGerer;

  const _CarteIntervenant({required this.partenaire, required this.peutGerer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Un intervenant archivé s'efface au lieu de disparaître : sa couleur
    // devient neutre et l'ensemble de la carte perd en contraste. Il reste
    // lisible et réactivable, mais ne concurrence plus les actifs du regard.
    final couleur = partenaire.actif ? couleurAvatar(partenaire.id) : AppColors.neutral;
    final opacite = partenaire.actif ? 1.0 : 0.72;

    return Opacity(
      opacity: opacite,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => ouvrirDetailPartenaire(context, partenaire, peutGerer: peutGerer),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border(left: BorderSide(color: couleur, width: 4)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(partenaire: partenaire, couleur: couleur),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partenaire.nom,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (partenaire.email != null && partenaire.email!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _LigneContact(icone: Icons.mail_outline_rounded, texte: partenaire.email!),
                      ],
                      if (partenaire.telephone != null && partenaire.telephone!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _LigneContact(icone: Icons.phone_outlined, texte: partenaire.telephone!),
                      ],
                      if (partenaire.contact != null && partenaire.contact!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _LigneContact(
                          icone: Icons.person_outline_rounded,
                          texte: l10n.partenaireResponsableLigne(partenaire.contact!),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                StatusBadge(
                                  label: partenaire.type.label(l10n),
                                  tone: toneTypePartenaire(partenaire.type),
                                ),
                                StatusBadge(
                                  label: libelleStatutPartenaire(l10n, partenaire.actif),
                                  tone: partenaire.actif ? BadgeTone.success : BadgeTone.neutral,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _BoutonDetail(partenaire: partenaire, peutGerer: peutGerer),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Partenaire partenaire;
  final Color couleur;

  const _Avatar({required this.partenaire, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: couleur,
              boxShadow: [
                BoxShadow(color: couleur.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Center(
              child: Text(
                partenaire.initiales,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ),
          // Pastille du type collée à l'avatar — la famille d'intervenant se
          // lit avant même d'atteindre les pastilles textuelles plus bas.
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 5, offset: const Offset(0, 2)),
                ],
              ),
              child: Icon(
                iconeTypePartenaire(partenaire.type),
                size: 13,
                color: toneTypePartenaire(partenaire.type).fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneContact extends StatelessWidget {
  final IconData icone;
  final String texte;

  const _LigneContact({required this.icone, required this.texte});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 13.5, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _BoutonDetail extends StatelessWidget {
  final Partenaire partenaire;
  final bool peutGerer;

  const _BoutonDetail({required this.partenaire, required this.peutGerer});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => ouvrirDetailPartenaire(context, partenaire, peutGerer: peutGerer),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.visibility_outlined, size: 16),
      label: Text(
        context.l10n.equipeDetailBouton,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PiedDePage extends StatelessWidget {
  const _PiedDePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          Icon(Icons.handshake_outlined, size: 40, color: AppColors.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(
            context.l10n.partenaireSlogan,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

// ── Feuille de filtres ───────────────────────────────────────────────────────

/// Feuille de filtres — activité et type.
///
/// Les choix s'appliquent IMMÉDIATEMENT au cubit partagé : la liste derrière
/// se réordonne pendant qu'on choisit, et le bouton du bas annonce le nombre
/// de résultats avant même de refermer. Un formulaire à valider aurait obligé
/// à fermer, regarder, rouvrir.
Future<void> ouvrirFiltresPartenaires(BuildContext context) {
  final cubit = context.read<PartenairesCubit>();
  // La feuille vit hors de l'arbre de la page : elle n'hérite pas de ses
  // providers, il faut donc lui passer les deux cubits explicitement.
  final typesCubit = context.read<TypesReferentielCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: cubit),
        BlocProvider.value(value: typesCubit),
      ],
      child: const _FeuilleFiltres(),
    ),
  );
}

class _FeuilleFiltres extends StatelessWidget {
  const _FeuilleFiltres();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<PartenairesCubit, PartenairesState>(
      builder: (context, state) {
        final cubit = context.read<PartenairesCubit>();

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: ContenuFormulaire(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 6),
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.equipeFiltrer,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (state.filtreType != null || state.filtreActif != null)
                          TextButton(
                            onPressed: () {
                              cubit.filtrerParType(null);
                              cubit.filtrerParActivite(null);
                            },
                            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                            child: Text(l10n.partenaireFiltreReinitialiser),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      children: [
                        _TitreGroupe(l10n.partenaireFiltreStatut),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _PuceChoix(
                              libelle: l10n.partenaireFiltreTous,
                              selectionne: state.filtreActif == null,
                              onTap: () => cubit.filtrerParActivite(null),
                            ),
                            _PuceChoix(
                              libelle: l10n.partenaireFiltreActifs,
                              icone: Icons.check_circle_outline_rounded,
                              selectionne: state.filtreActif == true,
                              onTap: () => cubit.filtrerParActivite(true),
                            ),
                            _PuceChoix(
                              libelle: l10n.partenaireFiltreArchives,
                              icone: Icons.inventory_2_outlined,
                              selectionne: state.filtreActif == false,
                              onTap: () => cubit.filtrerParActivite(false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _TitreGroupe(l10n.partenaireFiltreType),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _PuceChoix(
                              libelle: l10n.partenaireFiltreTous,
                              selectionne: state.filtreType == null,
                              onTap: () => cubit.filtrerParType(null),
                            ),
                            for (final t in context.watch<TypesReferentielCubit>().state.items)
                              _PuceChoix(
                                libelle: t.nom,
                                icone: iconeTypePartenaire(PartenaireTypeX.fromString(t.code)),
                                selectionne: state.filtreType == t.code,
                                onTap: () => cubit.filtrerParType(t.code),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          l10n.partenaireCompteur(state.itemsFiltres.length),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TitreGroupe extends StatelessWidget {
  final String texte;
  const _TitreGroupe(this.texte);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
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

class _PuceChoix extends StatelessWidget {
  final String libelle;
  final IconData? icone;
  final bool selectionne;
  final VoidCallback onTap;

  const _PuceChoix({
    required this.libelle,
    this.icone,
    required this.selectionne,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final couleurTexte = selectionne ? Colors.white : AppColors.textSecondary;

    return Material(
      color: selectionne ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selectionne ? AppColors.primary : AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icone != null) ...[
                Icon(icone, size: 15, color: couleurTexte),
                const SizedBox(width: 7),
              ],
              Text(
                libelle,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: couleurTexte),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
