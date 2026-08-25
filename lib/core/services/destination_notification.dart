import 'dart:convert';

import '../routes/app_router.dart';

/// Traduit la charge utile d'une alerte push en route de l'application.
///
/// Le backend joint déjà le contexte nécessaire (`notification.model.js` :
/// « Contexte JSON (reserveId, chantierId…) pour la navigation »), et
/// `notification.service.js` le transmet dans le bloc `data` du message FCM.
/// Il n'était simplement jamais lu : toutes les alertes menaient à l'écran
/// Notifications, à charge pour l'utilisateur de retrouver lui-même la réserve
/// dont on venait de lui parler.
///
/// Fonction PURE, sans dépendance à Flutter, pour être testable sans widget
/// ni Firebase.
class DestinationNotification {
  const DestinationNotification._();

  /// Route à ouvrir, ou l'écran Notifications quand la charge utile ne permet
  /// pas de viser plus précisément.
  ///
  /// Ne lève JAMAIS : une alerte malformée doit conduire quelque part, pas
  /// faire planter l'ouverture de l'application.
  static String resoudre(Map<String, dynamic> donneesFcm) {
    final contexte = _contexte(donneesFcm);

    // Ordre du plus précis au plus général : une alerte portant à la fois une
    // réserve et un chantier concerne la réserve.
    final reserveId = _texte(contexte['reserveId']);
    if (reserveId != null) return '/reserves/$reserveId';

    final planId = _texte(contexte['planId']);
    if (planId != null) return '/plans/$planId';

    final chantierId = _texte(contexte['chantierId']);
    if (chantierId != null) {
      // Le type départage ce qu'on ouvre POUR un chantier : une alerte de
      // document mène à la médiathèque, tout le reste à la fiche.
      final type = (_texte(donneesFcm['type']) ?? '').toLowerCase();
      if (type.contains('document')) return '/chantiers/$chantierId/documents';
      return '/chantiers/$chantierId';
    }

    return AppRoutes.notifications;
  }

  /// Extrait le bloc `donnees`, que FCM transmet en CHAÎNE JSON — `data`
  /// n'accepte que des chaînes (voir le commentaire côté back).
  ///
  /// Tolère aussi un objet déjà décodé : les alertes locales, elles, passent
  /// par `jsonDecode` en amont et arrivent sous forme de `Map`.
  static Map<String, dynamic> _contexte(Map<String, dynamic> donneesFcm) {
    final brut = donneesFcm['donnees'];
    if (brut is Map<String, dynamic>) return brut;
    if (brut is String && brut.isNotEmpty) {
      try {
        final decode = jsonDecode(brut);
        if (decode is Map<String, dynamic>) return decode;
      } catch (_) {
        // Charge utile illisible : on retombe sur l'écran Notifications.
      }
    }
    return const {};
  }

  /// `null` pour toute valeur absente ou vide — un identifiant vide
  /// construirait une route `/reserves/` qui ne correspond à rien.
  static String? _texte(Object? valeur) {
    if (valeur == null) return null;
    final texte = valeur.toString().trim();
    return texte.isEmpty ? null : texte;
  }
}
