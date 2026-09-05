import '../../injection_container.dart';
import 'cache_reponses_get.dart';

/// Enveloppe le rappel d'un `RefreshIndicator` pour qu'il aille VRAIMENT au
/// réseau.
///
/// ## Pourquoi c'est nécessaire
///
/// [CacheReponsesGet] sert les réponses `GET` retenues moins de trente
/// secondes plus tôt. C'est ce qui rend le retour sur un écran instantané —
/// mais ce serait un contresens pour le geste de tirer la liste vers le bas :
/// on demande alors explicitement des nouvelles, et recevoir la même réponse
/// qu'il y a dix secondes donnerait l'impression d'un bouton mort.
///
/// Le cache est donc vidé AVANT le rechargement. Entièrement, et non pour la
/// seule requête concernée : un écran charge souvent plusieurs ressources
/// (liste, compteurs, structure), et n'en rafraîchir qu'une laisserait
/// l'écran à moitié à jour — le pire des deux états, parce qu'il ne se voit
/// pas.
///
/// ```dart
/// RefreshIndicator(
///   onRefresh: forcerReseau(() => context.read<XCubit>().charger()),
///   child: ...,
/// )
/// ```
Future<void> Function() forcerReseau(Future<void> Function() charger) {
  return () async {
    // `maybeGet` : les tests de widgets pompent des écrans sans conteneur
    // d'injection. Un rafraîchissement ne doit pas planter parce qu'il n'y a
    // pas de cache à vider.
    if (sl.isRegistered<CacheReponsesGet>()) sl<CacheReponsesGet>().vider();
    await charger();
  };
}
