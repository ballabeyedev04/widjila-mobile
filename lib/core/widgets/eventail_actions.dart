import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Une entrée de l'éventail du bouton « + ».
typedef ActionRapide = ({
  IconData icon,
  String label,
  Color couleur,

  /// L'écran visé appartient-il à un chantier ? Si oui, le sélecteur de
  /// chantier s'intercale avant la navigation.
  bool besoinChantier,

  /// `true` : route de la coquille applicative — la barre du bas reste
  /// affichée, on y va avec `context.go`.
  /// `false` : écran plein hors coquille, empilé avec `context.push`.
  bool dansCoquille,

  /// Construit la route. Reçoit l'identifiant du chantier choisi, ou `null`
  /// quand [besoinChantier] est faux.
  String Function(String? chantierId) route,
});

/// Éventail d'actions rapides déployé par le bouton « + » de la barre.
///
/// Les pastilles s'écartent en arc de cercle autour du bouton, avec un
/// décalage entre chacune : elles sortent l'une après l'autre plutôt que
/// d'apparaître en bloc.
///
/// ## Pourquoi le déplacement passe par la mise en page
///
/// La version précédente ancrait l'éventail sur une bande de 1 px de haut et
/// écartait les pastilles avec un `Transform.translate`, par-dessus les bords
/// (`Clip.none`). Elles étaient bien VISIBLES — mais pas CLIQUABLES.
///
/// Deux mécanismes se liguaient :
///
///  1. `RenderBox.hitTest` abandonne dès que la position sort de `size` : une
///     pastille peinte 100 px au-dessus d'un parent haut d'un pixel n'était
///     jamais atteinte ;
///  2. même avec un parent plein écran, un `Transform` ne suffit pas — il
///     déplace le RENDU, mais l'`Align` et le `Padding` au-dessus éprouvent le
///     tap à la position NON translatée et le rejettent avant que le
///     `Transform` ait son mot à dire.
///
/// Le décalage est donc porté par la mise en page elle-même ([Align] +
/// [Padding], voir [_ItemAction]) : la boîte de chaque pastille se trouve
/// réellement là où on la voit. Les boîtes plein écran ne se gênent pas entre
/// elles, un [Align] ne testant que son enfant et jamais la surface vide
/// autour.
class EventailActions extends StatelessWidget {
  final Animation<double> animation;
  final List<ActionRapide> actions;

  /// Distance entre le bas de l'écran et le centre du bouton déclencheur.
  final double distanceBas;

  /// Décalage horizontal du point d'ancrage par rapport au centre de l'écran.
  /// Nul pour le bouton « + », qui est centré ; positif pour un onglet de
  /// droite, dont l'éventail doit partir de SON bouton et non du milieu de la
  /// barre.
  final double ancrageX;

  /// Angles de déploiement, en degrés trigonométriques (90 = vertical).
  /// Par défaut, un arc symétrique adapté au nombre d'entrées ; un
  /// déclencheur excentré fournit les siens pour rester dans l'écran.
  final List<double>? angles;

  /// Rappelé avec l'action choisie. La fermeture de la feuille est à la charge
  /// de l'appelant.
  final ValueChanged<ActionRapide> onChoix;

  /// Rappelé quand l'utilisateur referme sans choisir (tap sur le fond).
  final VoidCallback onFermeture;

  const EventailActions({
    super.key,
    required this.animation,
    required this.actions,
    required this.distanceBas,
    required this.onChoix,
    required this.onFermeture,
    this.ancrageX = 0,
    this.angles,
  });

  /// Rayon de l'arc. Assez large pour que les pastilles ne se chevauchent pas,
  /// assez court pour rester à portée du pouce.
  static const double _rayon = 118;

  @override
  Widget build(BuildContext context) {
    // Arc du haut : une seule action part à la verticale, deux se répartissent
    // de part et d'autre, trois occupent 140°.
    final anglesUtilises = angles ??
        switch (actions.length) {
          1 => const [90.0],
          2 => const [125.0, 55.0],
          _ => const [150.0, 90.0, 30.0],
        };

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(onTap: onFermeture, behavior: HitTestBehavior.opaque),
          ),
          for (var i = 0; i < actions.length; i++)
            _ItemAction(
              action: actions[i],
              angleDegres: anglesUtilises[i.clamp(0, anglesUtilises.length - 1)],
              rayon: _rayon,
              distanceBas: distanceBas,
              ancrageX: ancrageX,
              onTap: () => onChoix(actions[i]),
              animation: CurvedAnimation(
                parent: animation,
                curve: Interval(i * 0.09, 1.0, curve: Curves.easeOutBack),
                reverseCurve: Interval(0.0, 1.0 - i * 0.09, curve: Curves.easeInCubic),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemAction extends StatelessWidget {
  final ActionRapide action;
  final double angleDegres;
  final double rayon;
  final double distanceBas;
  final double ancrageX;
  final Animation<double> animation;
  final VoidCallback onTap;

  const _ItemAction({
    required this.action,
    required this.angleDegres,
    required this.rayon,
    required this.distanceBas,
    required this.ancrageX,
    required this.animation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radians = angleDegres * math.pi / 180;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          // `easeOutBack` dépasse 1 en fin de course (rebond) : on borne le
          // déplacement mais on laisse l'échelle jouer, c'est elle qui porte
          // le rebond visuel.
          final t = animation.value.clamp(0.0, 1.5);
          // L'ancrage, lui, ne s'anime pas : les pastilles partent dès la
          // première image de sous leur bouton déclencheur.
          final dx = ancrageX + math.cos(radians) * rayon * t;
          final dy = math.sin(radians) * rayon * t;

          // Marges plutôt que translation — voir l'explication détaillée sur
          // [EventailActions]. Avec `Alignment.bottomCenter`, une marge de
          // `2 × dx` d'un côté réduit la zone disponible et re-centre
          // l'enfant : il se décale donc de `dx`, et sa boîte le suit.
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: distanceBas + dy,
                left: dx > 0 ? dx * 2 : 0,
                right: dx < 0 ? -dx * 2 : 0,
              ),
              child: Opacity(
                opacity: animation.value.clamp(0.0, 1.0),
                child: Transform.scale(scale: animation.value.clamp(0.0, 1.0), child: child),
              ),
            ),
          );
        },
        // Pastille ET libellé partagent la même zone tactile : viser un disque
        // de 62 px au pouce est déjà juste, exiger de tomber dessus plutôt que
        // sur son étiquette le serait trop.
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Pastille(icon: action.icon, couleur: action.couleur),
              const SizedBox(height: 9),
              _Etiquette(label: action.label),
            ],
          ),
        ),
      ),
    );
  }
}

/// Disque blanc à ombre teintée par la couleur de l'action — la même famille
/// visuelle que les cartes de l'application (fond blanc, ombre douce), plutôt
/// qu'un aplat de couleur qui jurerait avec le reste.
class _Pastille extends StatelessWidget {
  final IconData icon;
  final Color couleur;

  const _Pastille({required this.icon, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: couleur.withValues(alpha: 0.18), width: 1.5),
        boxShadow: [
          // Ombre colorée : rattache la pastille à son action et la détache du
          // fond assombri, ce qu'une ombre noire ne ferait pas.
          BoxShadow(
            color: couleur.withValues(alpha: 0.32),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: couleur, size: 26),
    );
  }
}

/// Étiquette sous la pastille.
///
/// Blanche à texte sombre, et non l'inverse : sur le fond assombri de
/// l'éventail, les anciennes pastilles noires translucides étaient ternes et
/// se confondaient entre elles. La largeur est bornée pour qu'un libellé long
/// (« Tableau de bord chantier ») passe sur deux lignes au lieu de déborder de
/// l'écran sur les branches latérales de l'arc.
class _Etiquette extends StatelessWidget {
  final String label;
  const _Etiquette({required this.label});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 108),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            height: 1.25,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}
