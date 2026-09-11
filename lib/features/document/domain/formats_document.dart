/// Formats acceptés par la médiathèque d'un chantier, et leurs plafonds.
///
/// MIROIR de `backend/src/middlewares/upload.middleware.js` (`MIME_DOCUMENT`,
/// `EXTENSIONS_DOCUMENT`) et de `uploadConfig` (`backend/src/config/security.js`).
/// Le serveur reste seul juge — il contrôle le CONTENU réel du fichier. Ces
/// listes servent à refuser tout de suite ce qu'il refuserait de toute façon,
/// avant d'avoir envoyé plusieurs méga-octets pour rien.
abstract final class FormatsDocument {
  static const Map<String, String> _mimeParExtension = {
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'dwg': 'application/acad',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    '3gp': 'video/3gpp',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
  };

  /// Extensions proposées par l'onglet « Documents ». Photos et vidéos ont
  /// leurs propres onglets, alimentés par l'appareil photo et la galerie.
  static const extensionsDocuments = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'dwg'];

  static const _extensionsVideo = {'mp4', 'm4v', '3gp', 'mov', 'webm'};

  /// 5 Mo pour un document ou une photo, 100 Mo pour une vidéo.
  static const tailleMaxDocument = 5 * 1024 * 1024;
  static const tailleMaxVideo = 100 * 1024 * 1024;

  /// Extension en minuscules, sans le point — `''` si le nom n'en a pas.
  static String extension(String nomOuChemin) {
    final base = nomOuChemin.split('/').last.split(r'\').last;
    final i = base.lastIndexOf('.');
    if (i <= 0 || i == base.length - 1) return '';
    return base.substring(i + 1).toLowerCase();
  }

  static bool estDocumentAccepte(String nom) => extensionsDocuments.contains(extension(nom));

  /// Pièces jointes d'une réserve : les documents, plus les photos — un PV
  /// photographié, un croquis — que le serveur accepte sur la même route.
  static const extensionsPiecesJointes = [...extensionsDocuments, 'jpg', 'jpeg', 'png', 'webp'];

  static bool estPieceJointeAcceptee(String nom) => extensionsPiecesJointes.contains(extension(nom));

  static bool estVideo(String nom) => _extensionsVideo.contains(extension(nom));

  static int tailleMax(String nom) => estVideo(nom) ? tailleMaxVideo : tailleMaxDocument;

  /// Type MIME annoncé à l'envoi. Le serveur le confronte au contenu réel ;
  /// un format inconnu part en type générique, et c'est alors l'extension qui
  /// doit correspondre.
  static String typeMime(String nom) => _mimeParExtension[extension(nom)] ?? 'application/octet-stream';
}
