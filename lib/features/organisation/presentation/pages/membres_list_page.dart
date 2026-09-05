import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/couleurs_avatar.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/apparition_en_cascade.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/membre.dart';
import '../cubit/membres_cubit.dart';
import '../cubit/membres_state.dart';
import 'ajouter_membre_sheet.dart';
import 'detail_membre_sheet.dart';
import '../../../../core/network/forcer_reseau.dart';
import '../../../../core/routes/retour.dart';

/// Teinte de badge par rôle — même mapping que
/// `admin/src/utils/constants.js#ROLES` (cohérence visuelle web/mobile).
BadgeTone toneRoleMembre(UserRole role) {
  switch (role) {
    case UserRole.chefProjet:
      return BadgeTone.info;
    case UserRole.conducteurTravaux:
      return BadgeTone.warning;
    case UserRole.bureauControle:
      return BadgeTone.success;
    case UserRole.maitreOuvrage:
      return BadgeTone.primary;
    case UserRole.maitreOeuvre:
      return BadgeTone.success;
    case UserRole.pilote:
      return BadgeTone.info;
    case UserRole.entreprise:
    case UserRole.sousTraitant:
    case UserRole.client:
    case UserRole.inconnu:
      return BadgeTone.neutral;
  }
}

BadgeTone toneStatutMembre(String statut) {
  switch (statut) {
    case 'actif':
      return BadgeTone.success;
    case 'inactif':
      return BadgeTone.danger;
    case 'en_attente_validation':
      return BadgeTone.warning;
    default:
      return BadgeTone.neutral;
  }
}

String libelleStatutMembre(AppLocalizations l10n, String statut) {
  switch (statut) {
    case 'actif':
      return l10n.membreStatutActif;
    case 'inactif':
      return l10n.membreStatutInactif;
    case 'en_attente_validation':
      return l10n.membreStatutEnAttenteValidation;
    default:
      return statut;
  }
}

/// Couleur d'avatar d'un membre — la palette est partagée avec l'annuaire des
/// intervenants (voir `core/theme/couleurs_avatar.dart`).
Color couleurAvatarMembre(String id) => couleurAvatar(id);

class MembresListPage extends StatelessWidget {
  const MembresListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<MembresCubit>()..charger(),
      child: const _MembresListView(),
    );
  }
}

class _MembresListView extends StatelessWidget {
  const _MembresListView();

  void _ouvrirFormulaireAjout(BuildContext context) {
    final cubit = context.read<MembresCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => BlocProvider.value(value: cubit, child: const AjouterMembreSheet()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocConsumer<MembresCubit, MembresState>(
      // La confirmation n'est donnée QU'UNE FOIS par ajout réussi — voir
      // `accuserReceptionAjout`.
      listenWhen: (a, b) => a.dernierAjout != b.dernierAjout && b.dernierAjout != null,
      listener: (context, state) {
        final ajout = state.dernierAjout!;
        context.read<MembresCubit>().accuserReceptionAjout();

        // Cas normal : le serveur a envoyé ses identifiants au nouveau membre.
        // Rien à noter, rien à transmettre — un simple accusé suffit.
        //
        // Auparavant, une fenêtre affichait le mot de passe temporaire avec un
        // bouton « J'ai noté ». Le serveur ne le renvoie qu'une fois : la
        // refermer trop vite rendait le compte inutilisable, et il restait de
        // toute façon à le transmettre à l'intéressé par un autre moyen.
        if (ajout.emailEnvoye) {
          AppAlert.success(
            context,
            message: l10n.membreAjouteEmailEnvoye(ajout.membre.nomComplet),
          );
          return;
        }

        // L'envoi a échoué. La fenêtre reprend alors son rôle de filet : c'est
        // la seule et dernière occasion de lire ce mot de passe.
        final motDePasse = ajout.motDePasseTemporaire;
        if (motDePasse != null) {
          _afficherMotDePasseTemporaire(context, ajout.membre, motDePasse);
          return;
        }

        // Ni courriel parti, ni mot de passe à montrer : le créateur en a
        // choisi un lui-même, il le connaît déjà.
        AppAlert.success(context, message: l10n.membreAjouteMessage(ajout.membre.nomComplet));
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _EnTete(),
                if (state.status == MembresStatus.succes) ...[
                  const _BarreRecherche(),
                  _Compteur(nombre: state.membresFiltres.length),
                ],
                Expanded(child: _corps(context, state)),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _ouvrirFormulaireAjout(context),
            backgroundColor: AppColors.primary,
            elevation: 6,
            shape: const CircleBorder(),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        );
      },
    );
  }

  Widget _corps(BuildContext context, MembresState state) {
    final l10n = context.l10n;
    switch (state.status) {
      case MembresStatus.initial:
      case MembresStatus.chargement:
        return const LoadingList();
      case MembresStatus.erreur:
        return ErrorView(
          message: state.erreur ?? l10n.commonErrorUnknown,
          onRetry: () => context.read<MembresCubit>().charger(),
        );
      case MembresStatus.succes:
        final membres = state.membresFiltres;
        if (membres.isEmpty) {
          // Distinguer « l'organisation n'a pas de membre » de « le filtre ne
          // renvoie rien » : la première invite à créer, la seconde à élargir
          // la recherche. Un message unique enverrait la moitié des
          // utilisateurs dans la mauvaise direction.
          final filtreActif = state.recherche.isNotEmpty || state.filtreStatut != null;
          return EtatVideIllustre(
            motif: filtreActif ? MotifVide.recherche : MotifVide.equipe,
            titre: filtreActif ? l10n.commonNoResults : l10n.membreAucun,
            description: filtreActif ? l10n.planEssayerAutreMotCle : l10n.membreAucunDescription,
            // Pas de bouton quand un filtre est en cours : à cet instant
            // l'utilisateur cherche quelqu'un, il ne veut pas en créer un.
            cta: filtreActif
                ? null
                : BoutonAction(
                    icon: Icons.person_add_alt_1_rounded,
                    label: l10n.membreFormBouton,
                    onTap: () => _ouvrirFormulaireAjout(context),
                  ),
          );
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: forcerReseau(() => context.read<MembresCubit>().charger()),
          child: ContenuCentre(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              itemCount: membres.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == membres.length) return const _PiedDePage();
                return ApparitionEnCascade(rang: i, child: _CarteMembre(membre: membres[i]));
              },
            ),
          ),
        );
    }
  }

  void _afficherMotDePasseTemporaire(BuildContext context, Membre membre, String motDePasse) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DialogueMotDePasseTemporaire(membre: membre, motDePasse: motDePasse),
    );
  }
}

/// Barre de titre — flèche de retour, titre, bouton d'ajout en pastille.
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
            onPressed: () => context.retourVers(),
            tooltip: l10n.commonBack,
          ),
          Expanded(
            child: Text(
              l10n.actionEquipe,
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

/// Champ de recherche + bouton de filtre par statut.
class _BarreRecherche extends StatelessWidget {
  const _BarreRecherche();

  Future<void> _ouvrirFiltres(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<MembresCubit>();
    final courant = cubit.state.filtreStatut;

    // La feuille renvoie une CHAÎNE, jamais `null` pour un choix : `null` ne
    // signifie donc que « fermée sans choisir » (glissement, tap hors de la
    // feuille). Sans cette sentinelle, choisir « Tous » et abandonner la
    // feuille produiraient la même valeur et l'abandon réinitialiserait le
    // filtre à l'insu de l'utilisateur.
    const sentinelleTous = '__tous__';

    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            for (final entree in <(String, String)>[
              (sentinelleTous, l10n.equipeFiltreTous),
              ('actif', l10n.membreStatutActif),
              ('inactif', l10n.membreStatutInactif),
              ('en_attente_validation', l10n.membreStatutEnAttenteValidation),
            ])
              ListTile(
                title: Text(entree.$2),
                trailing: (courant ?? sentinelleTous) == entree.$1
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(entree.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choix == null || !context.mounted) return; // abandon : on ne touche à rien
    cubit.filtrerParStatut(choix == sentinelleTous ? null : choix);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtreActif = context.select((MembresCubit c) => c.state.filtreStatut) != null;

    return ContenuCentre(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => context.read<MembresCubit>().rechercher(v),
                decoration: InputDecoration(
                  hintText: l10n.equipeRechercheHint,
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
                onTap: () => _ouvrirFiltres(context),
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
  final int nombre;
  const _Compteur({required this.nombre});

  @override
  Widget build(BuildContext context) {
    return ContenuCentre(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            const Icon(Icons.groups_rounded, size: 19, color: AppColors.primary),
            const SizedBox(width: 9),
            // `Expanded` et non un `Text` nu : la phrase est traduite, et un
            // `Row` ne rétrécit pas son enfant. En allemand, ou avec une
            // taille de police agrandie dans les réglages du téléphone, elle
            // débordait sur la droite — le compteur affichait alors la bande
            // rayée du framework au lieu de son texte.
            Expanded(
              child: Text(
                context.l10n.equipeCompteur(nombre),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'un membre — liseré coloré à gauche, avatar, identité, pastilles,
/// date de dernière connexion et bouton « Détail ».
class _CarteMembre extends StatelessWidget {
  final Membre membre;
  const _CarteMembre({required this.membre});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final couleur = couleurAvatarMembre(membre.id);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => ouvrirDetailMembre(context, membre),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            // Liseré gauche de la couleur de l'avatar : il relie visuellement
            // la carte à son membre et donne à la liste son rythme vertical.
            border: Border(left: BorderSide(color: couleur, width: 4)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    membre.initiales,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            membre.nomComplet,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (membre.dernierConnexion != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('dd/MM/yy').format(membre.dernierConnexion!),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      membre.email,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              StatusBadge(
                                label: membre.fonction?.isNotEmpty == true
                                    ? membre.fonction!
                                    : membre.role.label(l10n),
                                tone: toneRoleMembre(membre.role),
                              ),
                              StatusBadge(
                                label: libelleStatutMembre(l10n, membre.statut),
                                tone: toneStatutMembre(membre.statut),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _BoutonDetail(membre: membre),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoutonDetail extends StatelessWidget {
  final Membre membre;
  const _BoutonDetail({required this.membre});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => ouvrirDetailMembre(context, membre),
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
          Icon(Icons.groups_outlined, size: 40, color: AppColors.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(
            context.l10n.equipeSlogan,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

/// Filet de sécurité : le courriel d'identifiants n'a PAS pu partir.
///
/// En marche normale cette fenêtre ne s'ouvre plus — le nouveau membre reçoit
/// ses identifiants directement. Elle ne reparaît que si l'envoi a échoué
/// (fournisseur indisponible, ou serveur sans clé d'envoi configurée), et
/// c'est alors la dernière occasion de lire ce mot de passe : le serveur ne le
/// conserve qu'en empreinte.
///
/// D'où le `barrierDismissible: false` — on ne referme qu'après l'avoir
/// consciemment noté.
class _DialogueMotDePasseTemporaire extends StatelessWidget {
  final Membre membre;
  final String motDePasse;
  const _DialogueMotDePasseTemporaire({required this.membre, required this.motDePasse});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(l10n.membreDialogueTitre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.membreDialogueEmailEchoue(membre.nomComplet),
            style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.primary100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary200),
            ),
            child: SelectableText(
              motDePasse,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.membreDialogueBouton),
        ),
      ],
    );
  }
}
