import 'dart:math';

// Réexporté : un test qui passe `alea:` n'a besoin que de cet import.
export 'dart:math' show Random;

/// Générateur « aléatoire » à tirage FIXE, pour les tests du délai de relance.
///
/// `SynchronisationService` étale chaque relance entre 50 et 100 % du palier
/// (deuxième audit — éviter qu'après une panne tous les téléphones relancent
/// au même instant). Avec le vrai hasard, un test qui mesure un délai ne peut
/// rien affirmer de précis : il passait ou échouait selon le tirage.
class AleaFixe implements Random {
  /// Valeur rendue par [nextDouble], dans [0, 1).
  final double valeur;

  const AleaFixe(this.valeur) : assert(valeur >= 0 && valeur < 1);

  @override
  double nextDouble() => valeur;

  @override
  int nextInt(int max) => (valeur * max).floor().clamp(0, max - 1);

  @override
  bool nextBool() => valeur >= 0.5;
}
