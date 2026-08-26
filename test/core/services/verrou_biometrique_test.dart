import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivie_chantier_mobile/core/services/verrou_biometrique.dart';

/// Mémoire de la proposition d'activation.
///
/// Ce drapeau est ce qui empêche le dialogue d'ouverture (voir
/// `AppShell._proposerVerrouSiPertinent`) de reposer la même question à
/// chaque lancement. Une régression ici ne casse rien de visible tout de
/// suite : elle transforme simplement l'application en harceleur.
void main() {
  late SharedPreferences prefs;
  late VerrouBiometrique verrou;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    verrou = VerrouBiometrique(prefs: prefs);
  });

  test('la proposition n’a pas été faite sur une installation neuve', () {
    expect(verrou.propositionFaite, isFalse);
  });

  test('marquerPropositionFaite est persistant', () async {
    await verrou.marquerPropositionFaite();
    expect(verrou.propositionFaite, isTrue);

    // Relu depuis le stockage, pas depuis l'instance : c'est ce qui compte
    // au lancement suivant de l'application.
    final autreInstance = VerrouBiometrique(prefs: await SharedPreferences.getInstance());
    expect(autreInstance.propositionFaite, isTrue);
  });

  test('le verrou est inactif par défaut', () {
    // Un verrou qu'on n'a pas demandé et qu'on ne sait pas retirer
    // transformerait une application de travail en piège.
    expect(verrou.actif, isFalse);
  });

  test('proposition et activation sont deux états indépendants', () async {
    // « Plus tard » marque la proposition SANS activer le verrou : les deux
    // clés ne doivent jamais être confondues.
    await verrou.marquerPropositionFaite();
    expect(verrou.propositionFaite, isTrue);
    expect(verrou.actif, isFalse);
  });
}
