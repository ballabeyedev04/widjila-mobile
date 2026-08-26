import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../organisation/domain/entities/organisation.dart';
import '../../../organisation/presentation/cubit/mon_organisation_cubit.dart';
import 'modifier_organisation_sheet.dart';
import 'modifier_profil_sheet.dart';

/// Fiche de profil — TOUT ce que le serveur expose sur le compte connecté,
/// plus l'entreprise à laquelle il appartient.
///
/// Deux sources, volontairement distinctes :
///
///  - l'utilisateur vient d'`AuthBloc`, donc déjà en mémoire : la page
///    s'affiche immédiatement, sans écran de chargement ;
///  - l'entreprise vient de `GET /organisation` ([MonOrganisationCubit]), en
///    arrière-plan. Son échec ne masque jamais les informations personnelles —
///    la section disparaît, c'est tout.
///
/// Ce qui est MODIFIABLE ici correspond exactement à ce que le backend
/// accepte : `updateProfilSchema` pour la personne (nom, prénom, téléphone,
/// fonction, photo) et `modifierOrganisationSchema` pour l'entreprise. Le
/// reste — email, rôle, statut, abonnement — est affiché en lecture seule,
/// avec la raison indiquée à l'écran plutôt qu'un champ qui refuserait de
/// s'enregistrer.
class ProfilPage extends StatelessWidget {
  const ProfilPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<MonOrganisationCubit>()..charger(),
      child: const _ProfilVue(),
    );
  }
}

class _ProfilVue extends StatelessWidget {
  const _ProfilVue();

  Future<void> _confirmerDeconnexion(BuildContext context) async {
    final l10n = context.l10n;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.profilDeconnexion),
        content: Text(l10n.profilConfirmerDeconnexion),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.profilDeconnexion),
          ),
        ],
      ),
    );
    if (confirme == true && context.mounted) {
      context.read<AuthBloc>().add(const AuthLogoutRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ContenuCentre(
              child: EnTeteListe(titre: l10n.profilTitre, avecRetour: true),
            ),
            Expanded(
              child: BlocBuilder<AuthBloc, AuthState>(
                buildWhen: (a, b) => a.utilisateur != b.utilisateur,
                builder: (context, state) {
                  final user = state.utilisateur;
                  if (user == null) return const SizedBox.shrink();
                  return ContenuCentre(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      children: [
                        _CarteIdentite(user: user),
                        const SizedBox(height: 16),
                        _SectionPersonnel(user: user),
                        const SizedBox(height: 16),
                        _SectionCompte(user: user),
                        const SizedBox(height: 16),
                        _SectionEntreprise(user: user),
                        const SizedBox(height: 22),
                        OutlinedButton.icon(
                          onPressed: () => _confirmerDeconnexion(context),
                          icon: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 19),
                          label: Text(
                            l10n.profilDeconnexion,
                            style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger, width: 1.4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ EN-TÊTE ═══════════════════════════

/// Bandeau d'identité : photo (ou initiales), nom, rôle, statut.
///
/// Le dégradé reprend celui du sélecteur de chantier — c'est la signature
/// visuelle de l'application, et elle donne à cette fiche le poids d'un écran
/// principal plutôt que d'une page de réglages.
class _CarteIdentite extends StatelessWidget {
  final User user;
  const _CarteIdentite({required this.user});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _Avatar(user: user),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.nomComplet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.9)),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _PastilleClaire(texte: user.role.label(l10n), icone: user.role.icon),
                    _PastilleClaire(
                      texte: _libelleStatut(user.statut, l10n),
                      icone: user.estActif ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final User user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final photo = user.photoProfil;
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: (photo != null && photo.isNotEmpty)
          // `errorBuilder` : les fichiers sont servis par une route
          // AUTHENTIFIÉE (`/uploads/*`), qu'un simple <img> n'atteint pas
          // toujours. On retombe alors sur les initiales plutôt que sur
          // l'icône d'image cassée de Flutter.
          ? Image.network(
              photo,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _Initiales(user: user),
            )
          : _Initiales(user: user),
    );
  }
}

class _Initiales extends StatelessWidget {
  final User user;
  const _Initiales({required this.user});

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          user.initiales,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      );
}

class _PastilleClaire extends StatelessWidget {
  final String texte;
  final IconData icone;
  const _PastilleClaire({required this.texte, required this.icone});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              texte,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      );
}

String _libelleStatut(String statut, AppLocalizations l10n) {
  switch (statut) {
    case 'actif':
      return l10n.membreStatutActif;
    case 'inactif':
      return l10n.membreStatutInactif;
    default:
      return l10n.membreStatutEnAttente;
  }
}

// ═══════════════════════════ SECTIONS ═══════════════════════════

/// Carte de section : titre, action facultative, puis les lignes.
class _Section extends StatelessWidget {
  final String titre;
  final IconData icone;
  final Widget? action;
  final List<Widget> enfants;

  const _Section({
    required this.titre,
    required this.icone,
    required this.enfants,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, action != null ? 8 : 16, 6),
            child: Row(
              children: [
                Icon(icone, size: 17, color: AppColors.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(children: enfants),
          ),
        ],
      ),
    );
  }
}

/// Une information : libellé à gauche, valeur à droite.
///
/// La valeur absente s'affiche « Non renseigné » en gris plutôt que d'être
/// masquée : sur une fiche qu'on vient consulter pour la compléter, un champ
/// vide qui disparaît est un champ qu'on ne pense pas à remplir.
class _Ligne extends StatelessWidget {
  final String libelle;
  final String? valeur;
  final Widget? suffixe;

  const _Ligne({required this.libelle, this.valeur, this.suffixe});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vide = valeur == null || valeur!.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              libelle,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              vide ? l10n.profilNonRenseigne : valeur!,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: vide ? FontWeight.w400 : FontWeight.w600,
                color: vide ? AppColors.textMuted : AppColors.textPrimary,
                fontStyle: vide ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          ?suffixe,
        ],
      ),
    );
  }
}

class _BoutonModifier extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  const _BoutonModifier({required this.onPressed, required this.tooltip});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.edit_outlined, size: 19, color: AppColors.primary),
        tooltip: tooltip,
        onPressed: onPressed,
      );
}

class _SectionPersonnel extends StatelessWidget {
  final User user;
  const _SectionPersonnel({required this.user});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Section(
      titre: l10n.profilSectionPersonnel,
      icone: Icons.person_outline_rounded,
      action: _BoutonModifier(
        tooltip: l10n.profilModifierTitre,
        onPressed: () => ouvrirModificationProfil(context, user),
      ),
      enfants: [
        _Ligne(libelle: l10n.profilPrenom, valeur: user.prenom),
        _Ligne(libelle: l10n.profilNom, valeur: user.nom),
        _Ligne(libelle: l10n.profilTelephone, valeur: user.telephone),
        _Ligne(libelle: l10n.profilFonction, valeur: user.fonction),
      ],
    );
  }
}

class _SectionCompte extends StatelessWidget {
  final User user;
  const _SectionCompte({required this.user});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final derniere = user.dernierConnexion;

    return _Section(
      titre: l10n.profilSectionCompte,
      icone: Icons.shield_outlined,
      enfants: [
        _Ligne(
          libelle: l10n.authChampEmail,
          valeur: user.email,
          suffixe: Icon(
            user.emailVerifie ? Icons.verified_rounded : Icons.error_outline_rounded,
            size: 17,
            color: user.emailVerifie ? AppColors.success : AppColors.warning,
          ),
        ),
        _Ligne(
          libelle: l10n.profilStatut,
          valeur: user.emailVerifie ? l10n.profilEmailVerifie : l10n.profilEmailNonVerifie,
        ),
        _Ligne(libelle: l10n.profilRole, valeur: user.role.label(l10n)),
        _Ligne(libelle: l10n.profilLangue, valeur: user.langue?.toUpperCase()),
        _Ligne(
          libelle: l10n.profilMfa,
          valeur: user.mfaActive ? l10n.profilMfaActive : l10n.profilMfaInactive,
          suffixe: Icon(
            user.mfaActive ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 17,
            color: user.mfaActive ? AppColors.success : AppColors.textMuted,
          ),
        ),
        _Ligne(
          libelle: l10n.profilDerniereConnexion,
          valeur: derniere != null ? DateFormat('dd MMM yyyy · HH:mm').format(derniere) : null,
        ),
        if (user.mdpTemporaire)
          _Bandeau(
            texte: l10n.profilMdpTemporaire,
            couleur: AppColors.warning,
            fond: AppColors.warningBg,
            icone: Icons.key_rounded,
          ),
        _Bandeau(
          texte: l10n.profilEmailNonModifiable,
          couleur: AppColors.textMuted,
          fond: AppColors.neutralBg,
          icone: Icons.lock_outline_rounded,
        ),
      ],
    );
  }
}

class _Bandeau extends StatelessWidget {
  final String texte;
  final Color couleur;
  final Color fond;
  final IconData icone;

  const _Bandeau({
    required this.texte,
    required this.couleur,
    required this.fond,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 15, color: couleur),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texte,
                style: TextStyle(fontSize: 12, color: couleur, height: 1.35),
              ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════ ENTREPRISE ═══════════════════════════

class _SectionEntreprise extends StatelessWidget {
  final User user;
  const _SectionEntreprise({required this.user});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Un compte sans organisation n'a rien à montrer ici — inutile d'afficher
    // une carte vide ou un message d'erreur.
    if (user.organisationId == null) return const SizedBox.shrink();

    return BlocBuilder<MonOrganisationCubit, MonOrganisationState>(
      builder: (context, state) {
        final org = state.organisation;

        if (org == null) {
          return _Section(
            titre: l10n.profilSectionEntreprise,
            icone: Icons.business_outlined,
            enfants: [
              if (state.status == MonOrganisationStatus.chargement)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primary),
                    ),
                  ),
                )
              else
                _Bandeau(
                  texte: state.erreur ?? l10n.profilEntrepriseIndisponible,
                  couleur: AppColors.textMuted,
                  fond: AppColors.neutralBg,
                  icone: Icons.info_outline_rounded,
                ),
            ],
          );
        }

        // `PUT /organisation` exige GESTION : proposer le crayon aux autres
        // rôles les enverrait droit sur un 403, formulaire rempli.
        final peutModifier = user.role.peutGererOrganisation;

        return _Section(
          titre: l10n.profilSectionEntreprise,
          icone: Icons.business_outlined,
          action: peutModifier
              ? _BoutonModifier(
                  tooltip: l10n.profilEntrepriseModifier,
                  onPressed: () => ouvrirModificationOrganisation(context, org),
                )
              : null,
          enfants: [
            _Ligne(libelle: l10n.profilEntrepriseNom, valeur: org.nom),
            _Ligne(libelle: l10n.profilEntrepriseRaison, valeur: org.raisonSociale),
            _Ligne(libelle: l10n.profilTelephone, valeur: org.telephone),
            _Ligne(libelle: l10n.authChampEmail, valeur: org.email),
            _Ligne(libelle: l10n.profilEntrepriseAdresse, valeur: org.adresseComplete),
            _Ligne(libelle: l10n.profilEntrepriseSiret, valeur: org.siret),
            _Ligne(libelle: l10n.profilEntrepriseTva, valeur: org.numTva),
            _Ligne(libelle: l10n.profilEntrepriseRccm, valeur: org.rccm),
            _Ligne(libelle: l10n.profilEntrepriseNinea, valeur: org.ninea),
            _Ligne(libelle: l10n.profilEntrepriseAbonnement, valeur: _libelleAbonnement(org, l10n)),
            if (!peutModifier)
              _Bandeau(
                texte: l10n.profilLectureSeule,
                couleur: AppColors.textMuted,
                fond: AppColors.neutralBg,
                icone: Icons.lock_outline_rounded,
              ),
          ],
        );
      },
    );
  }
}

/// Formule d'abonnement, complétée par la date de fin d'essai tant qu'il
/// court — c'est l'information qui manque le plus souvent quand on regarde
/// cette ligne.
String? _libelleAbonnement(Organisation org, AppLocalizations l10n) {
  final formule = org.abonnement;
  if (org.essaiEnCours && org.finEssai != null) {
    final essai = l10n.profilEntrepriseEssai(DateFormat('dd/MM/yyyy').format(org.finEssai!));
    return formule == null || formule.isEmpty ? essai : '$formule · $essai';
  }
  return formule;
}
