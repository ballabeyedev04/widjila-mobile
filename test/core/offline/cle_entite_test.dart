import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/offline/cle_entite.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';

/// La clé d'entité d'une action de la file.
///
/// C'est elle qui ORDONNE les actions d'une même réserve : une photo ne doit
/// jamais partir avant la création de sa réserve, un statut jamais avant le
/// précédent. Le calcul est partagé entre la file et la migration de schéma
/// de `BaseLocale` : s'ils divergeaient, une action migrée ne serait plus
/// reconnue comme dépendante de sa réserve.
void main() {
  String cle(TypeAction type, Map<String, dynamic> charge) =>
      cleEntitePour(type: type.code, charge: charge, idAction: 'act-1');

  test('la création est rattachée à SA réserve (clé `id`)', () {
    expect(cle(TypeAction.creerReserve, {'id': 'res-1'}), 'reserve:res-1');
  });

  test('toutes les actions sur une réserve partagent la clé de cette réserve', () {
    for (final type in [
      TypeAction.changerStatutReserve,
      TypeAction.ajouterPhotoReserve,
      TypeAction.modifierReserve,
      TypeAction.supprimerReserve,
    ]) {
      expect(cle(type, {'reserveId': 'res-1'}), 'reserve:res-1', reason: type.code);
    }
  });

  test('création puis photo d’une même réserve : même clé, donc même file ordonnée', () {
    expect(
      cle(TypeAction.creerReserve, {'id': 'res-9'}),
      cle(TypeAction.ajouterPhotoReserve, {'reserveId': 'res-9'}),
    );
  });

  test('un envoi de rapport a son propre espace de clés', () {
    // Un rapport et une réserve de même identifiant ne doivent pas se
    // bloquer l'un l'autre.
    expect(cle(TypeAction.envoyerRapport, {'rapportId': 'x'}), 'rapport:x');
    expect(cle(TypeAction.envoyerRapport, {'rapportId': 'x'}), isNot(cle(TypeAction.changerStatutReserve, {'reserveId': 'x'})));
  });

  test('charge incomplète : isolée sur SA propre clé, reliée à rien', () {
    // Sans identifiant, on ne suppose aucune dépendance — mieux vaut une
    // action seule qu'une action bloquée derrière une autre qui n'a rien à
    // voir.
    expect(cle(TypeAction.changerStatutReserve, {}), 'action:act-1');
    expect(cle(TypeAction.creerReserve, {'reserveId': 'mauvaise-cle'}), 'action:act-1');
  });

  test('chaque type existant a une règle — aucun oublié', () {
    // Un type ajouté sans règle retomberait sur `reserveId` : ce test oblige
    // à y penser en listant les codes attendus.
    expect(TypeAction.values.map((t) => t.code).toSet(), {
      'creerReserve', 'changerStatutReserve', 'ajouterPhotoReserve',
      'envoyerRapport', 'modifierReserve', 'supprimerReserve',
    });
  });
}
