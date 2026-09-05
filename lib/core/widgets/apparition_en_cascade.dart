import 'package:flutter/material.dart';

/// Fait apparaître un élément de liste en fondu, légèrement remonté, avec un
/// décalage proportionnel à son [rang].
///
/// ## Pourquoi
///
/// Une liste qui surgit d'un bloc ne dit rien : on ne sait pas si elle vient
/// d'arriver ou si elle était déjà là. En décalant chaque ligne de quelques
/// dizaines de millisecondes, le regard suit naturellement le sens de lecture
/// et comprend qu'il s'agit d'un contenu qui SE POSE.
///
/// ## Les trois réglages, et pourquoi ces valeurs
///
///  - **décalage de 45 ms par ligne** : en dessous, l'effet ne se lit plus ;
///    au-dessus, la liste se remplit au compte-gouttes ;
///  - **plafond à [_rangMax]** : sans lui, la vingtième ligne attendrait près
///    d'une seconde. Une longue liste doit finir d'apparaître aussi vite
///    qu'une courte, quitte à ce que les dernières lignes arrivent ensemble ;
///  - **glissement de 14 px seulement** : l'intention est de suggérer que
///    l'élément se pose, pas de le faire voler à travers l'écran.
///
/// ## Pourquoi un contrôleur plutôt qu'un `Future.delayed`
///
/// Un minuteur qui appelle `setState` survit à la disposition du widget : sur
/// une liste qu'on fait défiler vite, les lignes recyclées déclenchent des
/// réveils sur des états déjà jetés. Un `AnimationController` unique, dont la
/// première partie de course est un simple palier ([Interval]), se libère avec
/// le widget et ne peut rien réveiller.
///
/// L'animation ne joue qu'à la PREMIÈRE construction : une ligne déjà à
/// l'écran qui se reconstruit (changement de filtre, mise à jour d'un statut)
/// ne doit pas repartir en fondu.
class ApparitionEnCascade extends StatefulWidget {
  /// Position de l'élément dans sa liste — c'est elle qui échelonne l'entrée.
  final int rang;

  final Widget child;

  /// Durée de l'apparition d'UN élément, palier d'attente exclu.
  final Duration duree;

  const ApparitionEnCascade({
    super.key,
    required this.rang,
    required this.child,
    this.duree = const Duration(milliseconds: 260),
  });

  /// Au-delà, toutes les lignes partent ensemble — voir la note ci-dessus.
  static const int _rangMax = 8;

  /// Attente ajoutée par rang.
  static const Duration _pas = Duration(milliseconds: 45);

  @override
  State<ApparitionEnCascade> createState() => _ApparitionEnCascadeState();
}

class _ApparitionEnCascadeState extends State<ApparitionEnCascade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controleur;
  late final Animation<double> _courbe;

  @override
  void initState() {
    super.initState();

    final rang = widget.rang.clamp(0, ApparitionEnCascade._rangMax);
    final attente = ApparitionEnCascade._pas * rang;
    final total = attente + widget.duree;

    _controleur = AnimationController(vsync: this, duration: total);

    // Le palier d'attente est porté par l'intervalle : le contrôleur avance
    // dès la première image, mais la courbe reste à zéro tant que le tour de
    // cette ligne n'est pas venu.
    final debut = total.inMicroseconds == 0
        ? 0.0
        : attente.inMicroseconds / total.inMicroseconds;
    _courbe = CurvedAnimation(
      parent: _controleur,
      curve: Interval(debut, 1.0, curve: Curves.easeOutCubic),
    );

    _controleur.forward();
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _courbe,
      child: SlideTransition(
        position: Tween<Offset>(
          // Exprimé en fraction de la HAUTEUR de l'enfant : une carte haute se
          // déplace un peu plus qu'une ligne fine, ce qui garde la même
          // impression de vitesse quelle que soit la liste.
          begin: const Offset(0, 0.16),
          end: Offset.zero,
        ).animate(_courbe),
        child: widget.child,
      ),
    );
  }
}
