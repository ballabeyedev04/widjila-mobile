import 'package:flutter/widgets.dart';

/// Les règles d'adaptation communes à toute l'application.
///
/// ## Pourquoi un fichier, et pas des valeurs recopiées
///
/// Chaque écran qui invente son propre seuil produit une interface qui bascule
/// à une largeur différente de sa voisine : à la rotation d'une tablette, un
/// onglet passe en mise en page large pendant que celui d'à côté reste étroit.
/// Les valeurs vivent donc ici, une seule fois.
///
/// ## Le principe : l'ESPACE DISPONIBLE, jamais l'appareil
///
/// Rien ici ne demande « quel téléphone ? ». Tout se décide sur la place
/// réellement offerte au composant — largeur, hauteur, échelle de police
/// choisie par l'utilisateur. C'est ce qui fait tenir la mise en page sur un
/// appareil qui n'existait pas quand le code a été écrit, comme sur un pliable
/// dont la moitié d'écran ne ressemble à aucun format connu.

/// Seuil au-delà duquel l'application se dispose en « tablette ».
///
/// 700 points logiques : au-dessus de la plupart des téléphones en paysage,
/// en dessous de toutes les tablettes en portrait.
const double seuilTablette = 700;

/// Largeur en dessous de laquelle il faut compter chaque point.
///
/// 360 dp couvre l'essentiel des Android d'entrée de gamme encore en service
/// sur les chantiers. En dessous, on resserre les marges et on renonce aux
/// éléments décoratifs plutôt que de laisser le contenu déborder.
const double seuilEtroit = 360;

/// Hauteur en dessous de laquelle l'écran est COUCHÉ, ou presque.
///
/// C'est la contrainte la plus souvent oubliée : un téléphone en paysage offre
/// 320 à 430 points de haut, soit trois fois moins qu'en portrait. Une colonne
/// dessinée debout n'y tient pas.
const double seuilBasse = 500;

/// Vrai quand l'écran est assez large pour une mise en page tablette.
bool estTablette(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= seuilTablette;

/// Vrai sur les écrans étroits, où chaque point compte.
bool estEtroit(BuildContext context) =>
    MediaQuery.sizeOf(context).width < seuilEtroit;

/// Vrai quand la hauteur manque — téléphone couché, ou clavier ouvert.
bool estBasse(BuildContext context) =>
    MediaQuery.sizeOf(context).height < seuilBasse;

/// Marge horizontale d'un écran, selon la largeur disponible.
///
/// Trois paliers plutôt qu'une valeur unique : 16 points de marge sur un écran
/// de 320 laissent 288 points de contenu, alors que les mêmes 16 points sur une
/// tablette de 1024 collent le texte aux bords.
double margeEcran(BuildContext context) {
  final largeur = MediaQuery.sizeOf(context).width;
  if (largeur < seuilEtroit) return 12;
  if (largeur < seuilTablette) return 16;
  return 24;
}

/// Hauteur maximale d'un panneau posé en bas d'un écran.
///
/// ## Le débordement que cette fonction ferme
///
/// Ces panneaux étaient plafonnés à un POURCENTAGE de la hauteur de l'écran.
/// La règle tient debout, elle s'effondre couché : 34 % d'un téléphone en
/// paysage font 108 points, et le panneau doit encore y loger sa poignée, son
/// bouton d'action et un titre — 105 points de contenu incompressible. Le
/// balayage des formats mesurait le résultat : « RenderFlex overflowed by 3.2
/// pixels ».
///
/// Un pourcentage seul ne peut pas marcher : il ignore que le contenu a une
/// taille minimale, et que cette taille grandit encore si l'utilisateur
/// agrandit les textes dans les réglages de son téléphone.
///
/// La règle devient donc : une PART de l'écran, bornée en bas par ce que le
/// contenu exige réellement, et bornée en haut pour qu'un panneau ne dévore
/// pas le plan sur une grande tablette.
///
/// [contenuIncompressible] : la hauteur des éléments qui ne défilent pas
/// (poignée, bouton), à l'échelle 1. Elle est mise à l'échelle de police du
/// système — un texte agrandi de 30 % agrandit aussi les boutons qui le
/// portent.
double hauteurPanneauBas(
  BuildContext context, {
  double part = 0.34,
  double contenuIncompressible = 80,
  double plafond = 340,
}) {
  final hauteurEcran = MediaQuery.sizeOf(context).height;
  final echelle = MediaQuery.textScalerOf(context);

  // Le plancher : ce que le contenu fixe occupe, plus de quoi laisser
  // apparaître une première ligne de liste — sans quoi le panneau annoncerait
  // un contenu qu'on ne peut pas atteindre.
  final plancher = echelle.scale(contenuIncompressible) + 44;

  // Le plafond ne peut pas dépasser 70 % de l'écran : au-delà, le panneau ne
  // borde plus rien, il remplace la vue.
  final maximum = hauteurEcran * 0.7;

  return (hauteurEcran * part).clamp(plancher.clamp(0, maximum), plafond.clamp(0, maximum));
}

/// Nombre de colonnes d'une grille, déduit de la LARGEUR RÉELLE disponible.
///
/// À préférer à `estTablette` pour les grilles : un composant ne connaît pas
/// la taille de l'écran, il connaît la sienne. Une grille placée dans un volet
/// de tablette a la largeur d'un téléphone, et doit se disposer comme tel.
///
/// Voir aussi `colonnesAdaptatives` dans `liste_chrome.dart`, qui applique
/// cette règle aux listes existantes.
int colonnesPourLargeur(
  double largeurDisponible, {
  double largeurCible = 260,
  int min = 1,
  int max = 4,
}) {
  final colonnes = (largeurDisponible / largeurCible).floor();
  return colonnes.clamp(min, max);
}
