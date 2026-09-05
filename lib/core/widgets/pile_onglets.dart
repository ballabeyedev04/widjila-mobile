import 'package:flutter/material.dart';

/// Empile les onglets en les gardant TOUS vivants, et anime celui qui entre.
///
/// ## Le défaut corrigé
///
/// La coquille rendait un seul onglet à la fois, dans un sous-arbre porteur
/// d'une clé dérivée de la route. Chaque changement d'onglet produisait donc
/// un sous-arbre neuf : les trois écrans d'onglet créent leur cubit avec
/// `..charger()` dans `BlocProvider.create`, si bien qu'un aller-retour
/// Accueil → Réserves → Accueil déclenchait **trois appels réseau**, et
/// perdait au passage la position de défilement et les filtres saisis.
///
/// Sur un chantier en 3G, c'est une attente à chaque va-et-vient.
///
/// ## Pourquoi ce conteneur plutôt que `StatefulShellRoute.indexedStack`
///
/// `indexedStack` conserve bien l'état, mais bascule d'un onglet à l'autre
/// SANS transition : l'application perdrait le fondu qui marque le changement.
/// Ce conteneur fait les deux — il garde les branches montées ET rejoue
/// exactement la même animation qu'avant (fondu + montée de 1,5 %, 220 ms,
/// courbe `easeOutCubic`).
///
/// ## La forme de l'arbre ne change JAMAIS
///
/// Chaque branche est enveloppée des mêmes widgets, en permanence. Insérer un
/// [FadeTransition] seulement pendant l'animation changerait la profondeur du
/// sous-arbre : Flutter apparie les éléments par type ET position, la branche
/// serait donc reconstruite de zéro — et perdrait l'état que ce widget existe
/// précisément pour préserver. Ce qui varie, c'est l'ANIMATION passée, jamais
/// la structure.
///
/// ## Ce que « garder vivant » implique
///
///  - [Offstage] conserve l'état (listes chargées, défilement, filtres) mais
///    retire la branche de la mise en page et du dessin : un onglet caché ne
///    coûte rien à chaque frame ;
///  - [TickerMode] désactivé arrête ses animations. Sans lui, un indicateur de
///    chargement invisible continuerait de tourner et de réveiller le moteur
///    de rendu en continu.
class PileOnglets extends StatefulWidget {
  /// Branche visible.
  final int index;

  /// Une entrée par branche — l'ordre fait foi, il correspond aux onglets.
  final List<Widget> enfants;

  const PileOnglets({super.key, required this.index, required this.enfants});

  @override
  State<PileOnglets> createState() => _PileOngletsState();
}

class _PileOngletsState extends State<PileOnglets> with SingleTickerProviderStateMixin {
  static final _montee = Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero);

  late final AnimationController _controleur = AnimationController(
    vsync: this,
    // Mêmes valeurs que la transition d'origine : passer d'un onglet à l'autre
    // est un geste répété, il ne doit jamais se faire attendre.
    duration: const Duration(milliseconds: 220),
    value: 1, // premier rendu : déjà en place, rien à animer
  );

  // Typée `CurvedAnimation` et non `Animation<double>` : c'est elle qui porte
  // `dispose()`, et une courbe non libérée laisse un écouteur sur le
  // contrôleur — Flutter le signale en mode debug.
  late final CurvedAnimation _entree =
      CurvedAnimation(parent: _controleur, curve: Curves.easeOutCubic);

  /// Branche affichée avant le changement en cours.
  ///
  /// Elle reste VISIBLE pendant l'animation, SOUS l'entrante : sans elle,
  /// l'écran virerait au blanc le temps du fondu.
  int? _indexSortant;

  @override
  void didUpdateWidget(PileOnglets ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.index == widget.index) return;

    setState(() => _indexSortant = ancien.index);
    _controleur.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _indexSortant = null);
    });
  }

  @override
  void dispose() {
    _entree.dispose();
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.enfants.length; i++)
          Offstage(
            // Le sortant reste à l'écran le temps de l'animation.
            offstage: i != widget.index && i != _indexSortant,
            child: TickerMode(
              enabled: i == widget.index,
              child: FadeTransition(
                // Seule la branche ENTRANTE suit l'animation ; les autres sont
                // pleinement opaques et en place. La structure, elle, reste
                // identique pour toutes — voir l'en-tête.
                opacity: i == widget.index ? _entree : kAlwaysCompleteAnimation,
                child: SlideTransition(
                  position: (i == widget.index ? _entree : kAlwaysCompleteAnimation)
                      .drive(_montee),
                  child: widget.enfants[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
