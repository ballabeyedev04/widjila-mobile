import 'package:flutter/material.dart';

/// Monogramme « W » de Widjila, DESSINÉ et non chargé depuis un fichier.
///
/// L'image `assets/images/logo-widjila.png` ne convient pas ici : elle est
/// encodée sans couche alpha (PNG type 2, RVB opaque) et porte donc un fond
/// blanc. Posée sur l'aplat orange de l'écran d'accueil, elle y découperait
/// un rectangle blanc. Un tracé vectoriel règle le problème à la source : il
/// prend la couleur qu'on lui donne, reste net à toutes les tailles et ne
/// coûte aucun octet d'asset.
class MonogrammeW extends StatelessWidget {
  /// Côté du carré occupé par le monogramme.
  final double taille;

  /// Couleur des deux jambages.
  final Color couleur;

  /// Petite touche posée en haut du jambage droit — le seul accent coloré de
  /// la marque. Nulle pour un monogramme d'une seule teinte.
  final Color? accent;

  const MonogrammeW({
    super.key,
    this.taille = 132,
    this.couleur = Colors.white,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: taille,
      height: taille * 0.78,
      child: CustomPaint(
        painter: _PeintreW(couleur: couleur, accent: accent),
        // Le monogramme est décoratif : le nom de la marque est écrit juste
        // en dessous en toutes lettres, un lecteur d'écran le lira là.
        isComplex: false,
      ),
    );
  }
}

class _PeintreW extends CustomPainter {
  final Color couleur;
  final Color? accent;

  _PeintreW({required this.couleur, this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final l = size.width;
    final h = size.height;

    // Épaisseur proportionnelle : le trait garde le même rapport au
    // monogramme quelle que soit la taille demandée.
    final epaisseur = l * 0.185;

    final trait = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseur
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Marges pour que les extrémités arrondies ne soient pas rognées.
    final m = epaisseur / 2;
    final hautG = Offset(m, m);
    final basG = Offset(l * 0.30, h - m);
    final milieu = Offset(l * 0.50, h * 0.42);
    final basD = Offset(l * 0.70, h - m);
    final hautD = Offset(l - m, m);

    // Un W en deux V distincts plutôt qu'un tracé continu : les jointures
    // basses restent bien arrondies et le sommet central garde sa pointe.
    canvas.drawPath(Path()..moveTo(hautG.dx, hautG.dy)..lineTo(basG.dx, basG.dy)..lineTo(milieu.dx, milieu.dy), trait);
    canvas.drawPath(Path()..moveTo(milieu.dx, milieu.dy)..lineTo(basD.dx, basD.dy)..lineTo(hautD.dx, hautD.dy), trait);

    if (accent == null) return;

    // Touche d'accent : un court segment posé dans l'axe du jambage droit,
    // depuis son sommet vers l'intérieur.
    final vers = Offset(basD.dx - hautD.dx, basD.dy - hautD.dy);
    final longueur = vers.distance;
    if (longueur == 0) return;
    final unite = Offset(vers.dx / longueur, vers.dy / longueur);
    final fin = hautD + unite * (longueur * 0.34);

    canvas.drawLine(
      hautD,
      fin,
      Paint()
        ..color = accent!
        ..style = PaintingStyle.stroke
        ..strokeWidth = epaisseur * 0.92
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PeintreW ancien) => ancien.couleur != couleur || ancien.accent != accent;
}
