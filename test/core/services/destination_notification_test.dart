import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/services/destination_notification.dart';

/// La charge utile vient de FCM, donc d'un réseau : elle doit TOUJOURS mener
/// quelque part. Une alerte malformée qui ferait planter l'ouverture de
/// l'application serait pire que l'ancien comportement (tout renvoyer vers la
/// liste des notifications).
void main() {
  group('DestinationNotification.resoudre', () {
    test('une réserve mène à sa fiche', () {
      final route = DestinationNotification.resoudre({
        'type': 'reserve_creee',
        'donnees': '{"reserveId":"abc","chantierId":"xyz"}',
      });
      expect(route, '/reserves/abc');
    });

    test('la réserve prime sur le chantier — du plus précis au plus général', () {
      final route = DestinationNotification.resoudre({
        'donnees': '{"chantierId":"xyz","reserveId":"abc"}',
      });
      expect(route, '/reserves/abc');
    });

    test('un chantier seul mène à sa fiche', () {
      final route = DestinationNotification.resoudre({
        'type': 'chantier_maj',
        'donnees': '{"chantierId":"xyz"}',
      });
      expect(route, '/chantiers/xyz');
    });

    test('une alerte de document mène à la médiathèque du chantier', () {
      final route = DestinationNotification.resoudre({
        'type': 'document_ajoute',
        'donnees': '{"chantierId":"xyz"}',
      });
      expect(route, '/chantiers/xyz/documents');
    });

    test('un plan mène à la visionneuse', () {
      final route = DestinationNotification.resoudre({
        'donnees': '{"planId":"p1"}',
      });
      expect(route, '/plans/p1');
    });

    test('accepte un bloc déjà décodé — cas des alertes locales', () {
      final route = DestinationNotification.resoudre({
        'donnees': {'reserveId': 'abc'},
      });
      expect(route, '/reserves/abc');
    });

    group('charges utiles dégradées — repli sur les notifications', () {
      test('bloc absent', () {
        expect(DestinationNotification.resoudre({}), '/notifications');
      });

      test('JSON illisible', () {
        expect(
          DestinationNotification.resoudre({'donnees': '{ceci n est pas du json'}),
          '/notifications',
        );
      });

      test('bloc vide', () {
        expect(DestinationNotification.resoudre({'donnees': ''}), '/notifications');
      });

      test('identifiant vide — une route /reserves/ ne mènerait nulle part', () {
        expect(
          DestinationNotification.resoudre({'donnees': '{"reserveId":"   "}'}),
          '/notifications',
        );
      });

      test('JSON valide mais qui n\'est pas un objet', () {
        expect(DestinationNotification.resoudre({'donnees': '[1,2,3]'}), '/notifications');
      });
    });
  });
}
