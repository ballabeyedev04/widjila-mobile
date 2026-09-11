import 'dart:async';

import 'package:uuid/uuid.dart';

/// Identifiant de corrélation d'une requête HTTP — en-tête `X-Request-Id`.
///
/// Le serveur le reprend tel quel (s'il respecte son format), l'écrit sur
/// chaque ligne de journal produite par la requête et le renvoie dans le corps
/// de toute erreur (`requestId`). Un rapport Crashlytics ou une capture
/// d'écran d'erreur désigne ainsi UNE requête précise dans les journaux
/// serveur — au lieu d'un croisement approximatif d'heure et de route.
///
/// Une action de synchronisation hors ligne s'exécute dans une zone portant
/// son propre identifiant ([cleZoneIdOperation]) : la requête prend alors
/// l'identifiant de l'action. Le même identifiant se lit dans la file
/// d'attente du téléphone et dans le journal serveur — y compris pour chaque
/// nouvelle tentative de la même action.
const cleZoneIdOperation = #idOperationSync;

/// Format accepté par le serveur (`requestId.middleware.js`).
final _formatValide = RegExp(r'^[A-Za-z0-9_.:-]{8,128}$');

const _uuid = Uuid();

/// Identifiant de l'opération de synchronisation en cours, sinon un nouvel
/// identifiant aléatoire.
String identifiantRequete() {
  final deZone = Zone.current[cleZoneIdOperation];
  if (deZone is String && _formatValide.hasMatch(deZone)) return deZone;
  return _uuid.v4();
}
