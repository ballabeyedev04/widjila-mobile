import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Photo de chantier du fond de l'en-tête — VOLONTAIREMENT le même fichier que
/// l'écran de connexion (`auth_chrome.dart#authBackgroundImage`) : l'utilisateur
/// enchaîne les deux écrans en quelques secondes, réutiliser la photo fait
/// lire l'en-tête comme la continuité de la connexion plutôt que comme un
/// second univers graphique.
///
/// Le chemin est redéclaré ici plutôt qu'importé depuis `features/auth` : un
/// widget de `core/` ne doit pas dépendre d'une feature (la dépendance va
/// toujours des features vers le noyau, jamais l'inverse).
const String _photoEntete = 'assets/images/login-hero.jpg';

/// Fond de l'en-tête du tableau de bord.
///
/// Quatre couches superposées :
///
///  1. la photo de chantier ([_photoEntete]), qui donne la texture ;
///  2. un dégradé diagonal orange par-dessus, opaque à ~88 % — assez pour que
///     le texte blanc reste lisible partout, assez transparent pour que la
///     grue et la structure restent perceptibles ;
///  3. une lueur radiale en haut à droite — la « source » de lumière ;
///  4. un assombrissement radial en bas à gauche, qui creuse l'angle opposé.
///
/// Les deux halos sont des dégradés radiaux, pas des disques colorés : un
/// disque, même très peu contrasté, laisse un bord net bien visible sur
/// l'orange. Ici la couleur s'éteint avant d'atteindre le bord, il ne reste
/// qu'une variation de lumière.
///
/// [rayonBas] pilote la découpe du bas. La valeur suit le repli de l'en-tête :
/// une VAGUE tant qu'il est déployé — le bandeau se lit alors comme une forme
/// posée sur la page —, un bord franc une fois replié, pour que la barre
/// épinglée retrouve une limite nette sous la barre d'état.
class EnteteDegrade extends StatelessWidget {
  final double rayonBas;
  final Widget child;

  const EnteteDegrade({super.key, required this.rayonBas, required this.child});

  /// Amplitude maximale de la vague, en pixels. Reprise du repère visuel de la
  /// maquette : assez marquée pour se lire d'un coup d'œil, assez plate pour
  /// ne pas rogner le contenu ancré en bas de l'en-tête.
  static const double _amplitudeVague = 26;

  @override
  Widget build(BuildContext context) {
    // `rayonBas` vaut 0 replié et ~28 déployé (voir `dashboard_page.dart`) :
    // on s'en sert comme facteur d'expansion normalisé, pour que la vague
    // s'aplatisse exactement au même rythme que le reste de l'animation.
    final expansion = (rayonBas / 28).clamp(0.0, 1.0);

    return ClipPath(
      clipper: _VagueEntete(amplitude: _amplitudeVague * expansion),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _photoEntete,
            fit: BoxFit.cover,
            // Cadrage haut : c'est là que se trouvent les grues, la partie la
            // plus reconnaissable de la photo. Un cadrage centré ne montrerait
            // que du ciel sur un en-tête aussi bas.
            alignment: Alignment.topCenter,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryLight.withValues(alpha: 0.88),
                  AppColors.primary.withValues(alpha: 0.90),
                  AppColors.primaryDark.withValues(alpha: 0.94),
                ],
                stops: const [0.0, 0.52, 1.0],
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, -1.15),
                  radius: 1.2,
                  colors: [
                    Colors.white.withValues(alpha: 0.20),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.05, 1.3),
                    radius: 1.1,
                    colors: [
                      AppColors.primaryDarker.withValues(alpha: 0.38),
                      AppColors.primaryDarker.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Découpe le bas de l'en-tête en vague.
///
/// [amplitude] à 0 rend un rectangle franc : c'est ce qui permet à la même
/// découpe de servir l'en-tête déployé ET replié, sans basculer entre deux
/// widgets (une bascule ferait « sauter » la forme en cours d'animation).
class _VagueEntete extends CustomClipper<Path> {
  final double amplitude;

  const _VagueEntete({required this.amplitude});

  @override
  Path getClip(Size size) {
    final base = size.height - amplitude;

    return Path()
      ..lineTo(0, base)
      // Creux à gauche, puis remontée : deux courbes plutôt qu'une seule, pour
      // obtenir la double inflexion de la maquette (une quadratique unique
      // donne un arc de cercle, nettement plus mou).
      ..quadraticBezierTo(size.width * 0.28, base + amplitude * 1.55, size.width * 0.55, base + amplitude * 0.62)
      ..quadraticBezierTo(size.width * 0.80, base - amplitude * 0.30, size.width, base + amplitude * 0.38)
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(_VagueEntete oldClipper) => oldClipper.amplitude != amplitude;
}
