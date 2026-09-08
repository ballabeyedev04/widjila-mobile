import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

/// Prend une photo (appareil ou galerie) et rend le FICHIER, jamais `null`
/// par accident.
///
/// ## Le défaut corrigé
///
/// Sur Android, l'appareil photo est une AUTRE application. Pendant qu'elle
/// occupe l'écran, le système est libre de détruire l'activité de Widjila pour
/// récupérer de la mémoire — ce qui arrive d'autant plus vite que l'appareil
/// est modeste et que la scène est lourde (un plan rendu en pleine page, par
/// exemple). Au retour, Flutter redémarre, `pickImage` rend `null` et la photo
/// semble perdue : l'utilisateur voit l'appareil s'ouvrir, prend son cliché,
/// revient au formulaire… et rien.
///
/// La photo n'est pourtant pas perdue : le système la garde en attente, et
/// `retrieveLostData()` la rend. C'est le mécanisme prévu par `image_picker`,
/// documenté comme OBLIGATOIRE sur Android — et qu'aucun des trois écrans qui
/// ouvrent l'appareil n'utilisait.
///
/// ## Ce que cette fonction garantit
///
///  - le cliché est rendu même après une destruction d'activité ;
///  - un ABANDON reste un abandon : si l'utilisateur ferme l'appareil sans
///    déclencher, on rend `null` sans rien inventer ;
///  - une erreur du système (permission refusée, appareil indisponible) est
///    signalée par [PhotoIndisponible], et non par un `null` silencieux que
///    l'appelant confondrait avec un abandon.
///
/// [source] : `ImageSource.camera` ou `ImageSource.gallery`.
///
/// [largeurMax] et [qualite] plafonnent le cliché AVANT qu'il ne quitte le
/// téléphone : un capteur moderne produit 8 Mo par photo, dont l'écran
/// n'affichera jamais que quelques centaines de pixels et dont le réseau d'un
/// chantier ne veut pas.
Future<File?> capturerPhoto(
  ImageSource source, {
  double largeurMax = 1920,
  int qualite = 85,
}) async {
  final picker = ImagePicker();

  XFile? cliche;
  Object? erreur;
  try {
    cliche = await picker.pickImage(
      source: source,
      imageQuality: qualite,
      maxWidth: largeurMax,
    );
  } catch (e) {
    // L'échec n'est pas rendu tout de suite : la reprise ci-dessous peut
    // encore retrouver un cliché, et il vaut mieux la photo que l'erreur.
    erreur = e;
  }

  cliche ??= await _reprendreClicheEnAttente(picker);

  if (cliche != null) return File(cliche.path);
  if (erreur != null) throw PhotoIndisponible(erreur);
  return null; // Abandon volontaire — l'appelant ne fait rien.
}

/// Récupère le cliché qu'Android a mis en attente après avoir détruit
/// l'activité pendant la prise de vue.
///
/// Android UNIQUEMENT : le mécanisme n'existe pas ailleurs, et l'appeler sur
/// iOS ou sur le web n'apporterait qu'un aller-retour de plus par photo.
///
/// Un échec est avalé volontairement : c'est une reprise de secours, elle ne
/// doit jamais remplacer l'erreur d'origine ni masquer un abandon.
Future<XFile?> _reprendreClicheEnAttente(ImagePicker picker) async {
  if (kIsWeb || !Platform.isAndroid) return null;
  try {
    final perdu = await picker.retrieveLostData();
    if (perdu.isEmpty) return null;
    return perdu.file;
  } catch (_) {
    return null;
  }
}

/// L'appareil photo n'a pas pu rendre de cliché — permission refusée,
/// matériel indisponible, ou échec du système.
///
/// Distinct d'un abandon (`null`) : l'appelant doit le DIRE à l'utilisateur,
/// alors qu'un abandon ne mérite aucun message.
class PhotoIndisponible implements Exception {
  final Object cause;
  const PhotoIndisponible(this.cause);

  @override
  String toString() => 'PhotoIndisponible: $cause';
}
