import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/document/domain/entities/document.dart';
import 'package:suivie_chantier_mobile/features/document/domain/formats_document.dart';

/// Formats de la médiathèque : ce que l'onglet Documents accepte, ce qui
/// s'affiche dans l'application, et dans quel onglet chaque fichier se range.
void main() {
  group('FormatsDocument', () {
    test('accepte les formats bureautiques et DAO, quelle que soit la casse', () {
      for (final nom in ['DOE.pdf', 'cr.DOCX', 'metre.xlsx', 'ancien.xls', 'planning.ppt', 'RDC.dwg']) {
        expect(FormatsDocument.estDocumentAccepte(nom), isTrue, reason: nom);
      }
    });

    test('refuse ce que le serveur refuserait', () {
      for (final nom in ['setup.exe', 'archive.zip', 'sans-extension', '.pdf']) {
        expect(FormatsDocument.estDocumentAccepte(nom), isFalse, reason: nom);
      }
    });

    test('annonce un type MIME précis, générique pour un inconnu', () {
      expect(FormatsDocument.typeMime('plan.dwg'), 'application/acad');
      expect(
        FormatsDocument.typeMime('CR.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(FormatsDocument.typeMime('video.MOV'), 'video/quicktime');
      expect(FormatsDocument.typeMime('inconnu.xyz'), 'application/octet-stream');
    });

    test('plafond de la vidéo, plafond du document', () {
      expect(FormatsDocument.tailleMax('fissure.mp4'), FormatsDocument.tailleMaxVideo);
      expect(FormatsDocument.tailleMax('DOE.pdf'), FormatsDocument.tailleMaxDocument);
    });
  });

  group('ChantierDocument — nature du fichier', () {
    ChantierDocument doc(String nom, {String? mime}) => ChantierDocument(
          id: '1',
          chantierId: 'c1',
          nomFichier: nom,
          fichierUrl: '/uploads/documents/x',
          mimeType: mime,
        );

    test('un DWG servi en image/vnd.dwg n’est pas rangé parmi les photos', () {
      expect(doc('plan.dwg', mime: 'image/vnd.dwg').estImage, isFalse);
    });

    test('type générique : l’extension décide', () {
      final video = doc('fissure.mp4', mime: 'application/octet-stream');
      expect(video.estVideo, isTrue);
      expect(video.apercuIntegre, isFalse);
    });

    test('PDF et photos s’affichent dans l’application, pas un Word', () {
      expect(doc('DOE.pdf', mime: 'application/pdf').apercuIntegre, isTrue);
      expect(doc('facade.jpg').apercuIntegre, isTrue);
      expect(doc('CR.docx').apercuIntegre, isFalse);
    });
  });
}
