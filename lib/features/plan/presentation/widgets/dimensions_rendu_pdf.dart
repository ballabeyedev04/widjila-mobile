import 'dart:math' as math;

/// Dimensions, en pixels, auxquelles rasteriser une page de plan PDF.
///
/// CORRECTIF (audit performance — mémoire) : la page était rendue à deux fois
/// sa taille en points, SANS plafond. Un plan A0 (2384 × 3370 pt) devenait une
/// image de 4768 × 6740 px, soit environ 128 Mo une fois décodée — pour UNE
/// page, avant même l'affichage. Sur un téléphone de chantier à 3 ou 4 Go, un
/// seul grand format frôlait la fin de mémoire, et deux visionneuses empilées
/// faisaient fermer l'application.
///
/// Le facteur 2 est conservé pour les formats courants (A4, A3, A2 : netteté
/// inchangée au zoom), mais le grand côté est plafonné à [coteMax] pixels :
/// l'A0 tombe à 2897 × 4096 px, environ 47 Mo, et reste sous la taille de
/// texture maximale des GPU mobiles d'entrée de gamme (souvent 4096).
({double largeur, double hauteur}) dimensionsRenduPdf(
  double largeurPt,
  double hauteurPt, {
  double facteur = 2,
  double coteMax = 4096,
}) {
  final grandCote = math.max(largeurPt, hauteurPt) * facteur;
  final echelle = grandCote > coteMax ? coteMax / grandCote * facteur : facteur;
  return (
    largeur: (largeurPt * echelle).floorToDouble(),
    hauteur: (hauteurPt * echelle).floorToDouble(),
  );
}
