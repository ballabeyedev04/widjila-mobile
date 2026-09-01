import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/services/service_position.dart';

/// Le contrat de [ResultatPosition].
///
/// Le service lui-même parle au GPS de l'appareil et ne se teste pas ici. Ce
/// qui se teste — et ce qui compte pour l'écran — c'est la distinction entre
/// « j'ai une position » et « voici POURQUOI je n'en ai pas » : chaque cause
/// d'échec appelle un message différent, et les confondre enverrait
/// l'utilisateur chercher dans les mauvais réglages.
void main() {
  test('un succès porte les deux coordonnées', () {
    const r = ResultatPosition.succes(14.6928, -17.4467);

    expect(r.reussi, isTrue);
    expect(r.echec, isNull);
    expect(r.latitude, 14.6928);
    expect(r.longitude, -17.4467);
  });

  test('un échec ne porte aucune coordonnée', () {
    // Sinon l'écran écrirait un zéro dans les champs — au large du golfe de
    // Guinée, une position parfaitement valide et parfaitement fausse.
    const r = ResultatPosition.echec(EchecPosition.serviceDesactive);

    expect(r.reussi, isFalse);
    expect(r.latitude, isNull);
    expect(r.longitude, isNull);
  });

  test('les quatre causes d’échec sont distinctes', () {
    // « Activez le GPS » et « autorisez l'application » sont deux gestes
    // opposés : les fondre en un seul cas rendrait le message inutilisable.
    expect(EchecPosition.values, hasLength(4));
    expect(EchecPosition.values.toSet(), hasLength(4));
  });

}
