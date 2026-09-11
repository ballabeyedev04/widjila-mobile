/// Entité métier touchée par une action de la file — calcul PARTAGÉ entre
/// `ActionEnAttente.cleEntite` (en mémoire) et la migration de schéma de
/// `BaseLocale` (qui remplit la colonne `cle_entite` des files existantes).
///
/// Un seul calcul : si les deux divergeaient, une action migrée ne serait plus
/// reconnue comme dépendante de sa réserve, et partirait avant sa création.
///
/// Une action dont l'entité est inconnue (charge incomplète) n'est reliée à
/// AUCUNE autre : sans identifiant, on ne suppose pas de dépendance.
String cleEntitePour({required String type, required Map<String, dynamic> charge, required String idAction}) {
  final Object? cible;
  switch (type) {
    case 'creerReserve':
      cible = charge['id'];
    case 'envoyerRapport':
      cible = charge['rapportId'];
    default:
      // Statut, photo, modification, suppression : la réserve visée.
      cible = charge['reserveId'];
  }
  if (cible == null) return 'action:$idAction';
  return type == 'envoyerRapport' ? 'rapport:$cible' : 'reserve:$cible';
}
