import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivie_chantier_mobile/core/services/locale_controller.dart';

void main() {
  group('LocaleController', () {
    test('démarre en français si aucune préférence n\'est enregistrée', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final controller = LocaleController(prefs: prefs);

      expect(controller.value, const Locale('fr'));
    });

    test('démarre sur la langue déjà persistée', () async {
      SharedPreferences.setMockInitialValues({'sc_langue': 'en'});
      final prefs = await SharedPreferences.getInstance();

      final controller = LocaleController(prefs: prefs);

      expect(controller.value, const Locale('en'));
    });

    test('une valeur persistée hors des langues supportées retombe sur le français', () async {
      SharedPreferences.setMockInitialValues({'sc_langue': 'it'});
      final prefs = await SharedPreferences.getInstance();

      final controller = LocaleController(prefs: prefs);

      expect(controller.value, const Locale('fr'));
    });

    test('changer() met à jour la valeur ET la persiste', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(prefs: prefs);

      await controller.changer('de');

      expect(controller.value, const Locale('de'));
      expect(prefs.getString('sc_langue'), 'de');
    });

    test('changer() ignore un code non supporté', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(prefs: prefs);

      await controller.changer('it');

      expect(controller.value, const Locale('fr'), reason: 'inchangé — "it" n\'est pas une langue supportée');
    });

    test('changer() notifie les auditeurs (ValueListenableBuilder de MaterialApp)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(prefs: prefs);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.changer('es');

      expect(notifications, 1);
    });

    group('synchroniserDepuisCompte', () {
      test('aligne la langue locale sur celle du compte à la connexion', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final controller = LocaleController(prefs: prefs);

        await controller.synchroniserDepuisCompte('de');

        expect(controller.value, const Locale('de'));
      });

      test('ne fait rien si le compte n\'a pas de langue enregistrée', () async {
        SharedPreferences.setMockInitialValues({'sc_langue': 'es'});
        final prefs = await SharedPreferences.getInstance();
        final controller = LocaleController(prefs: prefs);

        await controller.synchroniserDepuisCompte(null);

        expect(controller.value, const Locale('es'), reason: 'la préférence locale existante doit survivre');
      });

      test('ne fait rien si déjà synchronisé (pas de réécriture inutile du stockage)', () async {
        SharedPreferences.setMockInitialValues({'sc_langue': 'en'});
        final prefs = await SharedPreferences.getInstance();
        final controller = LocaleController(prefs: prefs);
        var notifications = 0;
        controller.addListener(() => notifications++);

        await controller.synchroniserDepuisCompte('en');

        expect(notifications, 0);
      });
    });
  });
}
