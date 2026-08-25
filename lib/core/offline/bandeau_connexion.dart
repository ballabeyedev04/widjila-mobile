import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n_extension.dart';
import '../routes/app_router.dart';
import '../theme/app_colors.dart';
import 'detecteur_connexion.dart';
import 'synchronisation_service.dart';

/// Bandeau d'état réseau, affiché au-dessus de TOUTE l'application.
///
/// Posé une seule fois dans le `builder` de `MaterialApp.router` (voir
/// `main.dart`) : il couvre donc chaque page sans qu'aucune n'ait à s'en
/// occuper — y compris les écrans ouverts en plein écran hors de la coquille
/// de navigation.
///
/// ## Trois états, trois messages
///
///  - **hors ligne** (rouge) : rassure autant qu'il alerte — l'application
///    reste utilisable, le travail n'est pas perdu ;
///  - **synchronisation** (orange) : transitoire, pendant l'envoi ;
///  - **reconnecté** (vert) : confirmation brève, puis disparition
///    automatique. Un bandeau vert permanent n'apporterait rien : l'état
///    normal, c'est d'être en ligne.
class BandeauConnexion extends StatefulWidget {
  final SynchronisationService service;
  final Widget child;

  const BandeauConnexion({super.key, required this.service, required this.child});

  @override
  State<BandeauConnexion> createState() => _BandeauConnexionState();
}

class _BandeauConnexionState extends State<BandeauConnexion> {
  /// Le bandeau vert ne reste pas : il confirme puis s'efface.
  static const Duration _dureeConfirmation = Duration(seconds: 3);

  bool _afficherConfirmation = false;
  StatutOffline? _precedent;

  @override
  void initState() {
    super.initState();
    widget.service.statut.addListener(_surChangement);
  }

  @override
  void dispose() {
    widget.service.statut.removeListener(_surChangement);
    super.dispose();
  }

  void _surChangement() {
    final courant = widget.service.statut.value;
    final avant = _precedent;
    _precedent = courant;
    if (avant == null || !mounted) return;

    // Bascule hors ligne → en ligne, avec la file désormais vidée : on
    // confirme brièvement que tout est parti.
    final retourEnLigne = avant.reseau == EtatReseau.horsLigne && courant.reseau == EtatReseau.enLigne;
    final synchroFinie = avant.synchro == EtatSynchro.enCours &&
        courant.synchro == EtatSynchro.termine &&
        courant.enAttente == 0;

    if (retourEnLigne || synchroFinie) {
      setState(() => _afficherConfirmation = true);
      Future.delayed(_dureeConfirmation, () {
        if (mounted) setState(() => _afficherConfirmation = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StatutOffline>(
      valueListenable: widget.service.statut,
      builder: (context, statut, _) {
        return Column(
          children: [
            // `SafeArea(bottom: false)` : le bandeau se glisse sous l'encoche
            // et la barre d'état, jamais dessous.
            SafeArea(
              bottom: false,
              child: _Bandeau(statut: statut, confirmation: _afficherConfirmation),
            ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}

class _Bandeau extends StatelessWidget {
  final StatutOffline statut;
  final bool confirmation;

  const _Bandeau({required this.statut, required this.confirmation});

  @override
  Widget build(BuildContext context) {
    final apparence = _apparence(context, statut, confirmation);

    // `AnimatedSize` + hauteur nulle : le bandeau se replie au lieu de
    // disparaître d'un coup, et ne laisse aucun espace vide quand tout va bien.
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: apparence == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: apparence.fond,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (apparence.enCours)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      else
                        Icon(apparence.icone, color: Colors.white, size: 17),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          apparence.texte,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Bouton d'action optionnel — « Voir toutes les tâches »
                  // sur le seul état d'échec, pour ouvrir l'écran de reprise
                  // manuelle sans que l'utilisateur ait à le chercher ailleurs.
                  if (apparence.actionLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton(
                        onPressed: () => context.push(AppRoutes.tachesSynchronisation),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          apparence.actionLabel!,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  /// `null` = rien à afficher (cas nominal : en ligne, file vide).
  _Apparence? _apparence(BuildContext context, StatutOffline s, bool confirmation) {
    final l10n = context.l10n;

    // Tant que la première vérification n'a pas abouti, on n'affiche rien
    // plutôt qu'un « hors ligne » qui clignoterait au lancement.
    if (s.reseau == EtatReseau.inconnu) return null;

    if (s.estHorsLigne) {
      return _Apparence(
        fond: AppColors.danger,
        icone: Icons.cloud_off_rounded,
        texte: s.aDuTravailEnAttente
            ? l10n.bandeauHorsLigneAvecTravail(s.enAttente)
            : l10n.bandeauHorsLigneSansTravail,
      );
    }

    if (s.synchro == EtatSynchro.enCours) {
      return _Apparence(
        fond: AppColors.primary,
        icone: Icons.sync_rounded,
        enCours: true,
        texte: l10n.bandeauSynchronisationEnCours,
      );
    }

    if (confirmation) {
      return _Apparence(
        fond: AppColors.success,
        icone: Icons.cloud_done_rounded,
        texte: l10n.bandeauConfirmationSucces,
      );
    }

    // Des tâches ont été refusées par le serveur (échec définitif) : la
    // synchronisation automatique ne les reprendra JAMAIS toute seule (voir
    // `FileAttente.aTraiter`), il faut le dire clairement et donner le moyen
    // d'agir — d'où le bouton vers l'écran dédié.
    if (s.enEchec > 0) {
      return _Apparence(
        fond: AppColors.danger,
        icone: Icons.error_outline_rounded,
        texte: '${l10n.bandeauEchecIntro}\n${l10n.bandeauEchecCompteur(s.enEchec)}',
        actionLabel: l10n.bandeauVoirTachesBouton,
      );
    }

    // En ligne mais des actions restent en file (échec métier, ou synchro pas
    // encore déclenchée) : on le signale sans alarmer, en orange.
    if (s.aDuTravailEnAttente) {
      return _Apparence(
        fond: AppColors.warning,
        icone: Icons.cloud_upload_outlined,
        texte: l10n.bandeauEnAttenteEnvoi(s.enAttente),
      );
    }

    return null;
  }
}

@immutable
class _Apparence {
  final Color fond;
  final IconData icone;
  final String texte;
  final bool enCours;

  /// Libellé du bouton d'action affiché sous le message — `null` = pas de
  /// bouton. Seul l'état d'échec en propose un aujourd'hui.
  final String? actionLabel;

  const _Apparence({
    required this.fond,
    required this.icone,
    required this.texte,
    this.enCours = false,
    this.actionLabel,
  });
}
