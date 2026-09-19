import 'package:flutter/material.dart';

/// Enveloppe carte commune du tableau de bord — coins arrondis, ombre douce,
/// jamais de bordure dure. Un seul endroit à ajuster pour que toutes les
/// cartes (KPI, vue d'ensemble, graphiques) restent visuellement cohérentes.
class CarteTableauDeBord extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const CarteTableauDeBord({super.key, required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.045), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: child,
    );
  }
}

/// En-tête d'une carte de graphique : titre et sous-titre, même typographie
/// que « Vue d'ensemble ».
class EnTeteCarte extends StatelessWidget {
  final String titre;
  final String sousTitre;
  const EnTeteCarte({super.key, required this.titre, required this.sousTitre});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF0F172A))),
        Text(sousTitre, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
      ],
    );
  }
}
