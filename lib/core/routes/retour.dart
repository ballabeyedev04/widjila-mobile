import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'app_router.dart';

/// Retour arrière SÛR, quelle que soit la façon dont l'écran a été atteint.
///
/// ## Le défaut que cela corrige
///
/// `context.pop()` ne fait rien quand la pile est vide — et elle l'est plus
/// souvent qu'il n'y paraît dans cette application :
///
///  - les écrans « dans la coquille » (`/equipe`, `/abonnement`, `/chantiers`,
///    `/intervenants`) sont atteints par `context.go()` depuis le menu
///    « Plus », ce qui REMPLACE la destination au lieu de l'empiler
///    (voir `app_shell.dart` : `push` y superposerait deux barres de
///    navigation) ;
///  - les écrans visés par une notification (`/reserves/:id`, `/plans/:id`,
///    `/chantiers/:id`) sont ouverts par `go()` depuis l'extérieur de
///    l'application, sans pile non plus ;
///  - un lien profond (courriel de réinitialisation) ouvre l'écran
///    directement.
///
/// Dans tous ces cas, la flèche de retour ne répondait pas. Pire sur Android :
/// faute de route à dépiler, le bouton retour matériel **ferme
/// l'application** au lieu de revenir en arrière.
///
/// ## La règle
///
/// Dépiler s'il y a quelque chose à dépiler ; sinon rejoindre un écran
/// d'accueil cohérent. Jamais de cul-de-sac.
extension RetourSur on BuildContext {
  /// Revient à l'écran précédent, ou à [repli] si la pile est vide.
  ///
  /// [repli] doit être une destination toujours atteignable pour
  /// l'utilisateur — un onglet de la barre de navigation, typiquement.
  void retourVers([String repli = AppRoutes.dashboard]) {
    if (canPop()) {
      pop();
    } else {
      go(repli);
    }
  }
}
