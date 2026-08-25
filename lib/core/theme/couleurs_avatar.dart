import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Palette des avatars (membres, intervenants).
///
/// La couleur est dérivée de l'identifiant — donc STABLE d'un affichage à
/// l'autre, contrairement à un tirage aléatoire ou à un index de liste (qui
/// changerait au moindre tri ou filtre). Une même personne, une même
/// entreprise gardent ainsi toujours leur couleur, ce qui aide à les repérer
/// dans une longue liste.
///
/// Partagée entre l'équipe et les intervenants : les deux écrans se lisent
/// comme deux annuaires du même jeu, ils ne peuvent pas avoir chacun leur
/// palette.
const List<Color> paletteAvatars = [
  AppColors.primary,
  Color(0xFF4F86F7),
  Color(0xFF8B5CF6),
  Color(0xFF34C759),
  Color(0xFFF5A623),
  Color(0xFF00BCD4),
  Color(0xFFE05299),
];

Color couleurAvatar(String id) => paletteAvatars[id.hashCode.abs() % paletteAvatars.length];
