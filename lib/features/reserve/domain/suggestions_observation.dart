/// Logique PURE du champ « Observation » de la création d'une réserve :
/// suggestions tirées de l'historique, et ajout d'une dictée au texte déjà
/// saisi. Sans Flutter ni réseau — testable tel quel.
library;

/// Nombre de suggestions affichées sous le champ : au-delà, la liste masque
/// le formulaire au lieu de l'aider.
const int suggestionsObservationMax = 4;

/// Saisie minimale avant de proposer quoi que ce soit : une lettre seule
/// correspondrait à la moitié de l'historique.
const int saisieMinimaleSuggestion = 2;

/// Longueur au-delà de laquelle une observation n'est plus une formule
/// réutilisable — même borne que le serveur (`observations.service.js`).
const int longueurMaxSuggestion = 300;

const Map<String, String> _sansAccent = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae', 'ß': 'ss',
};

/// Forme de comparaison : minuscules, sans accents, espaces réduits.
/// « Coins  CASSÉS » et « coins cassés » sont la même observation.
String normaliserObservation(String texte) {
  final minuscules = texte.toLowerCase();
  final tampon = StringBuffer();
  for (final rune in minuscules.runes) {
    final c = String.fromCharCode(rune);
    tampon.write(_sansAccent[c] ?? c);
  }
  return tampon.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// La saisie correspond-elle à l'observation (déjà normalisées) ?
///
/// Vrai si l'observation COMMENCE par la saisie (« coi » → « coins casse »),
/// ou si chaque mot saisi est le DÉBUT d'un mot de l'observation
/// (« cas » → « coins casse »). Même règle que le serveur.
bool correspondObservation(String observation, String saisie) {
  if (saisie.isEmpty) return true;
  if (observation.startsWith(saisie)) return true;
  final mots = observation.split(' ');
  return saisie.split(' ').every((fragment) => mots.any((mot) => mot.startsWith(fragment)));
}

/// Séparateurs de phrase : une suggestion ne remplace que la phrase EN COURS,
/// jamais ce qui a été écrit avant.
final RegExp _finDePhrase = RegExp(r'(\n|[.!?;]\s)');

/// Découpe le texte en ce qui précède la phrase en cours, et la phrase en cours.
({String avant, String fragment}) fragmentEnCours(String texte) {
  var coupure = 0;
  for (final m in _finDePhrase.allMatches(texte)) {
    coupure = m.end;
  }
  return (avant: texte.substring(0, coupure), fragment: texte.substring(coupure));
}

/// Suggestions pertinentes pour [saisie], tirées de [historique] (déjà classé,
/// la plus pertinente d'abord).
///
/// Vide si la saisie est trop courte, si rien ne correspond, ou si la seule
/// correspondance est déjà exactement ce qui est tapé. Sans doublon.
List<String> suggestionsObservation(
  List<String> historique,
  String saisie, {
  int max = suggestionsObservationMax,
}) {
  final cible = normaliserObservation(saisie);
  if (cible.length < saisieMinimaleSuggestion) return const [];

  final vues = <String>{};
  final debut = <String>[];
  final ailleurs = <String>[];
  for (final brut in historique) {
    final texte = brut.trim();
    if (texte.isEmpty || texte.length > longueurMaxSuggestion) continue;
    final cle = normaliserObservation(texte);
    if (cle == cible || !vues.add(cle)) continue;
    if (cle.startsWith(cible)) {
      debut.add(texte);
    } else if (correspondObservation(cle, cible)) {
      ailleurs.add(texte);
    }
  }
  return [...debut, ...ailleurs].take(max).toList();
}

/// Remplace la phrase en cours de [texte] par [suggestion] ; ce qui précède
/// est conservé tel quel.
String remplacerFragment(String texte, String suggestion) {
  final decoupe = fragmentEnCours(texte);
  return '${decoupe.avant}$suggestion';
}

/// Ajoute les mots dictés à la suite du texte déjà présent — sans jamais
/// l'écraser : « client VIP » + « livraison demain » → « client VIP
/// livraison demain ».
String joindreDictee(String base, String mots) {
  final dicte = mots.trim();
  if (dicte.isEmpty) return base;
  if (base.trim().isEmpty) return dicte;
  // Un retour à la ligne volontaire est conservé ; sinon, un espace.
  if (base.endsWith('\n')) return '$base$dicte';
  return '${base.trimRight()} $dicte';
}

/// Insère [observation] en tête d'[historique], sans doublon, dans la limite
/// de [max] entrées. Les observations vides ou trop longues sont ignorées.
List<String> memoriserObservation(List<String> historique, String observation, {int max = 200}) {
  final texte = observation.trim();
  if (texte.isEmpty || texte.length > longueurMaxSuggestion) return historique;
  final cle = normaliserObservation(texte);
  return [
    texte,
    ...historique.where((h) => normaliserObservation(h) != cle),
  ].take(max).toList();
}
