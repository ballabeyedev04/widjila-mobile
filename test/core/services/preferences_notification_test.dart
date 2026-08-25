import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivie_chantier_mobile/core/services/preferences_notification.dart';

void main() {
  late PreferencesNotification prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesNotification(prefs: await SharedPreferences.getInstance());
  });

  group('valeurs par défaut', () {
    test('tout est actif au premier lancement', () {
      // Une application de suivi de chantier qui n'alerte de rien tant qu'on
      // n'a pas trouvé le réglage n'aurait pas beaucoup d'intérêt.
      expect(prefs.toutesActives, isTrue);
      for (final f in FamilleAlerte.values) {
        expect(prefs.familleActive(f), isTrue, reason: f.name);
      }
      expect(prefs.doitAfficher('reserve.affectee'), isTrue);
    });
  });

  group('doitAfficher', () {
    test('l\'interrupteur général coupe tout', () async {
      await prefs.definirToutesActives(false);
      expect(prefs.doitAfficher('reserve.affectee'), isFalse);
      expect(prefs.doitAfficher('chantier.affectation'), isFalse);
      expect(prefs.doitAfficher('inspection.convocation'), isFalse);
    });

    test('couper une famille n\'affecte pas les autres', () async {
      await prefs.definirFamille(FamilleAlerte.reserve, false);
      expect(prefs.doitAfficher('reserve.affectee'), isFalse);
      expect(prefs.doitAfficher('reserve.statut'), isFalse);
      expect(prefs.doitAfficher('chantier.affectation'), isTrue);
    });

    test('le filtre porte sur le PRÉFIXE — un type ajouté demain est couvert', () async {
      await prefs.definirFamille(FamilleAlerte.reserve, false);
      // `reserve.commentaire` n'existe pas encore côté serveur. Filtrer sur la
      // liste exacte des types l'aurait laissé passer le jour de son ajout.
      expect(prefs.doitAfficher('reserve.commentaire'), isFalse);
    });

    test('un type INCONNU passe — ne pas taire ce qui n\'a jamais été refusé', () {
      expect(prefs.doitAfficher('facturation.echeance'), isTrue);
      expect(prefs.doitAfficher(''), isTrue);
    });

    test('la casse et les espaces ne changent rien', () async {
      await prefs.definirFamille(FamilleAlerte.inspection, false);
      expect(prefs.doitAfficher('  INSPECTION.convocation '), isFalse);
    });
  });

  test('les réglages sont persistés', () async {
    await prefs.definirFamille(FamilleAlerte.chantier, false);
    final relu = PreferencesNotification(prefs: await SharedPreferences.getInstance());
    expect(relu.familleActive(FamilleAlerte.chantier), isFalse);
  });
}
