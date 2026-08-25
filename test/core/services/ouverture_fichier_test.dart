import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/services/ouverture_fichier.dart';

/// Le nom de fichier vient du SERVEUR et sert à construire un chemin
/// d'écriture. Le traiter comme sûr laisserait un `../` s'échapper du dossier
/// temporaire — d'où ces cas, qui portent tous sur l'assainissement.
void main() {
  group('OuvertureFichier.nomSur', () {
    test('conserve un nom ordinaire', () {
      expect(OuvertureFichier.nomSur('plan-rdc.pdf'), 'plan-rdc.pdf');
    });

    test('ne garde que le dernier segment d\'un chemin POSIX', () {
      expect(OuvertureFichier.nomSur('dossier/sous/plan.pdf'), 'plan.pdf');
    });

    test('ne garde que le dernier segment d\'un chemin Windows', () {
      expect(OuvertureFichier.nomSur(r'C:\Windows\System32\hosts'), 'hosts');
    });

    test('neutralise une remontée de répertoire', () {
      final nom = OuvertureFichier.nomSur('../../../etc/passwd');
      expect(nom, 'passwd');
      expect(nom.contains('..'), isFalse);
      expect(nom.contains('/'), isFalse);
    });

    test('remplace les caractères interdits par le système de fichiers', () {
      expect(OuvertureFichier.nomSur('rapport:final?.pdf'), 'rapport_final_.pdf');
    });

    test('retire les points de tête — un fichier caché n\'est pas voulu ici', () {
      expect(OuvertureFichier.nomSur('...cache'), 'cache');
    });

    test('un nom vide ou entièrement filtré retombe sur un défaut', () {
      expect(OuvertureFichier.nomSur(''), 'document');
      expect(OuvertureFichier.nomSur('/'), 'document');
      expect(OuvertureFichier.nomSur('...'), 'document');
    });

    test('tronque un nom démesuré en gardant la fin — donc l\'extension', () {
      final nomLong = '${'a' * 400}.pdf';
      final nom = OuvertureFichier.nomSur(nomLong);
      expect(nom.length, lessThanOrEqualTo(120));
      // La troncature garde la FIN : perdre l'extension priverait le système
      // du seul indice lui permettant de choisir une application.
      expect(nom.endsWith('.pdf'), isTrue);
    });
  });
}
