import 'package:flutter/material.dart';

/// Bouton d'action principal — affiche un indicateur de chargement à la
/// place du libellé pendant un appel réseau (`enCours: true`), sans jamais
/// changer la taille du bouton ni désactiver le reste de l'écran.
///
/// ## Le débordement fermé ici
///
/// Le libellé était un `Text` nu dans un `Row` : rien ne lui disait de se
/// contraindre. Sur un téléphone de 320 points, « Alles synchronisieren »
/// précédé de son icône dépassait de 34 points — mesuré par le balayage des
/// formats sur l'écran des tâches en attente.
///
/// Le défaut valait pour TOUS les boutons de l'application, pas seulement
/// celui-là : c'est le composant partagé qui manquait de contrainte, et les
/// libellés allemands sont systématiquement les plus longs des quatre langues.
///
/// La correction est ici plutôt que dans chaque écran — un appelant qui doit
/// se souvenir d'envelopper son libellé finit toujours par oublier.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool enCours;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enCours = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: enCours ? null : onPressed,
      child: enCours
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Row(
              // `min` conservé : le bouton reste centré sur son contenu quand
              // la place ne manque pas, et ne s'étire pas à la largeur d'un
              // parent illimité.
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                // `Flexible` et non `Expanded` : `Expanded` forcerait le
                // libellé à prendre toute la largeur disponible, ce qui
                // décentrerait l'icône sur un bouton pleine largeur. `Flexible`
                // ne borne que le CAS OÙ ça déborde, et laisse le reste
                // inchangé.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    // Un libellé tronqué reste lisible et cliquable ; un
                    // libellé qui déborde peint par-dessus ce qui l'entoure et
                    // rend la bande jaune et noire du débordement.
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }
}
