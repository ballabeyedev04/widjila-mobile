import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../widgets/marque_widjila.dart';

/// Écran d'accueil affiché après le splash, pour un visiteur non connecté.
///
/// Il remplace l'arrivée directe sur le formulaire de connexion : un
/// utilisateur qui ouvre l'application pour la première fois y voit d'abord
/// la marque et ses deux portes d'entrée, plutôt qu'un champ email à remplir.
///
/// Le routeur (`app_router.dart`) y envoie tout état `nonAuthentifie` ;
/// « Se connecter » et « Créer un compte » ouvrent ensuite les écrans
/// correspondants, qui gardent chacun leur propre retour.
class BienvenuePage extends StatelessWidget {
  const BienvenuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Container(
        // Dégradé très léger : l'aplat strictement uniforme paraît plat sur
        // un grand écran, celui-ci garde la même couleur de marque tout en
        // donnant de la profondeur au bas de page.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primaryLight, AppColors.primary],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, contraintes) => SingleChildScrollView(
              // Défilable : sur un petit écran en mode police agrandie, la
              // colonne dépasse la hauteur disponible — sans cela les
              // boutons deviendraient inatteignables.
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: contraintes.maxHeight),
                // `IntrinsicHeight` : dans un défilement, la hauteur est
                // NON BORNÉE, et un `Spacer` (donc un `Expanded`) y est
                // illégal — « RenderFlex children have non-zero flex but
                // incoming height constraints are unbounded ». Il redonne à
                // la colonne une hauteur finie, ce qui permet de garder les
                // espaces souples : la marque respire au centre, les boutons
                // restent en bas, et l'ensemble se met à défiler seulement
                // quand la place manque vraiment.
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),
                      const MonogrammeW(taille: 128, couleur: Colors.white, accent: AppColors.primary100),
                      const SizedBox(height: 18),
                      const Text(
                        'Widjila',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        l10n.bienvenueAccroche,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16.5,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                      const Spacer(flex: 4),
                      _BoutonPlein(
                        libelle: l10n.authSeConnecter,
                        onPressed: () => context.go(AppRoutes.login),
                      ),
                      const SizedBox(height: 14),
                      _BoutonContour(
                        libelle: l10n.authCreerUnCompte,
                        onPressed: () => context.go(AppRoutes.register),
                      ),
                      const SizedBox(height: 34),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Action principale : fond blanc plein, texte sombre.
class _BoutonPlein extends StatelessWidget {
  final String libelle;
  final VoidCallback onPressed;

  const _BoutonPlein({required this.libelle, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(libelle, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
    ),
  );
}

/// Action secondaire : simple contour blanc sur l'orange.
class _BoutonContour extends StatelessWidget {
  final String libelle;
  final VoidCallback onPressed;

  const _BoutonContour({required this.libelle, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(libelle, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
    ),
  );
}
