import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/widgets/dimensions_rendu_pdf.dart';

/// Un plan grand format ne doit plus être rasterisé à une taille qui épuise la
/// mémoire du téléphone (voir dimensions_rendu_pdf.dart).
void main() {
  /// Octets d'une image RGBA décodée.
  double octets(({double largeur, double hauteur}) d) => d.largeur * d.hauteur * 4;

  group('dimensionsRenduPdf', () {
    test('un A4 garde le facteur 2 — netteté inchangée', () {
      final d = dimensionsRenduPdf(595, 842);
      expect(d.largeur, 1190);
      expect(d.hauteur, 1684);
    });

    test('un A3 garde le facteur 2', () {
      final d = dimensionsRenduPdf(842, 1191);
      expect(d.hauteur, 2382);
    });

    test('un A0 est plafonné à 4096 px sur son grand côté', () {
      final d = dimensionsRenduPdf(2384, 3370);
      expect(d.hauteur, 4096);
      // Proportions conservées : les repères posés dessus restent au bon endroit.
      expect(d.largeur / d.hauteur, closeTo(2384 / 3370, 0.001));
    });

    test('un A0 passe d’environ 128 Mo à moins de 50 Mo décodé', () {
      const avant = 4768.0 * 6740 * 4;
      final apres = octets(dimensionsRenduPdf(2384, 3370));
      expect(avant / (1024 * 1024), greaterThan(120));
      expect(apres / (1024 * 1024), lessThan(50));
    });

    test('un plan paysage est plafonné sur sa largeur', () {
      final d = dimensionsRenduPdf(3370, 2384);
      expect(d.largeur, 4096);
      expect(d.hauteur, lessThan(4096));
    });

    test('aucune dimension ne dépasse jamais le plafond', () {
      for (final (l, h) in [(100.0, 100.0), (5000.0, 200.0), (14400.0, 14400.0), (1.0, 9000.0)]) {
        final d = dimensionsRenduPdf(l, h);
        expect(d.largeur, lessThanOrEqualTo(4096));
        expect(d.hauteur, lessThanOrEqualTo(4096));
      }
    });
  });
}
