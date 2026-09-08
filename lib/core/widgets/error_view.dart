import 'package:flutter/material.dart';
import '../../l10n/l10n_extension.dart';
import '../theme/app_colors.dart';

/// Affiche une [Failure] avec un bouton « Réessayer » — utilisé dans chaque
/// écran de liste/détail en cas d'échec de chargement.
///
/// ## Le débordement fermé ici
///
/// La colonne était centrée mais NON DÉFILABLE. Sur un téléphone couché — 320
/// points de haut — l'icône, le message et le bouton totalisent plus que la
/// place disponible : le balayage des formats mesurait jusqu'à 115 points de
/// débordement. Le bouton « Réessayer » se retrouvait alors sous la bande
/// jaune et noire, donc hors d'atteinte, sur l'écran dont c'est la SEULE
/// sortie.
///
/// Un message d'erreur long — le serveur en renvoie parfois plusieurs lignes
/// (détails de validation Joi) — produisait le même effet en portrait.
///
/// La colonne défile désormais, tout en restant centrée quand la place ne
/// manque pas : c'est le rôle de `ConstrainedBox` + `IntrinsicHeight` sous un
/// `SingleChildScrollView`. Le composant est partagé par une trentaine
/// d'écrans ; la correction vaut donc pour tous.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        // Marge resserrée quand la hauteur manque : 32 points en haut et en bas
        // sur un écran de 320 en consomment un cinquième pour rien.
        final marge = contraintes.maxHeight < 380 ? 16.0 : 32.0;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: marge),
          child: ConstrainedBox(
            // `minHeight` : le contenu reste CENTRÉ tant qu'il tient, et ne
            // remonte en haut que lorsqu'il déborde. Sans cette contrainte, un
            // message court se collerait au bord supérieur.
            constraints: BoxConstraints(minHeight: contraintes.maxHeight - marge * 2),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    // Icône réduite sur un écran court : c'est l'élément le
                    // plus coûteux en hauteur, et le moins porteur de sens.
                    size: contraintes.maxHeight < 380 ? 34 : 48,
                    color: AppColors.danger,
                  ),
                  SizedBox(height: contraintes.maxHeight < 380 ? 10 : 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  if (onRetry != null) ...[
                    SizedBox(height: contraintes.maxHeight < 380 ? 12 : 20),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        context.l10n.commonRetry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
