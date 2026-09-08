import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/mfa_page.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/reset_password_page.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/splash_page.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

/// Les cinq écrans d'authentification, à toutes les tailles d'écran.
///
/// ## Pourquoi eux, et pourquoi ensemble
///
/// Ce sont les seuls écrans que TOUT LE MONDE voit, y compris avant d'avoir un
/// compte — et les seuls qu'aucun test ne couvrait. Ils partagent la même
/// forme : un logo, un ou deux champs, un bouton principal, un lien. C'est
/// exactement la disposition qui cède quand la hauteur s'effondre, parce que
/// rien n'y défile tant que le contenu tient debout.
///
/// Ils partagent aussi la même dépendance — un `AuthBloc` — et rien d'autre.
/// Un fichier commun évite d'écrire cinq fois le même échafaudage, et met les
/// cinq écrans sous la même règle : si l'un cède, on le voit au même endroit.
///
/// ## Ce qu'un balayage détecte ici
///
/// `flutter_test` remonte un `RenderFlex overflowed by N pixels` comme une
/// exception. Monter l'écran à chacun des 22 formats et vérifier qu'aucune n'a
/// été levée transforme l'audit visuel — long, subjectif, jamais rejoué — en
/// une mesure automatique.
///
/// Le CLAVIER n'est pas simulé ici : `flutter_test` ne l'ouvre pas. Les écrans
/// remontent leur contenu au-dessus de lui par `MediaQuery.viewInsetsOf`, ce
/// qui reste à vérifier sur appareil.
void main() {
  late _MockAuthBloc auth;

  /// Un bloc muet, arrêté sur [etat].
  ///
  /// `Stream.empty()` : sans flux, aucun écran ne part en navigation pendant
  /// le test — on mesure la MISE EN PAGE, pas le parcours.
  _MockAuthBloc bloc(AuthState etat) {
    final b = _MockAuthBloc();
    whenListen(b, const Stream<AuthState>.empty(), initialState: etat);
    return b;
  }

  setUp(() {
    auth = bloc(const AuthState(status: AuthStatus.nonAuthentifie));
  });

  /// Les cinq écrans, avec l'état d'authentification qui les rend visibles.
  ///
  /// L'écran MFA n'a de sens qu'en attente de code, et le splash qu'en cours
  /// de vérification : les monter dans un autre état testerait une situation
  /// qui n'arrive jamais.
  final ecrans = <String, ({Widget page, AuthState etat})>{
    'Connexion': (
      page: const LoginPage(),
      etat: const AuthState(status: AuthStatus.nonAuthentifie),
    ),
    'Double authentification': (
      page: const MfaPage(),
      etat: const AuthState(status: AuthStatus.mfaRequis),
    ),
    'Mot de passe oublié': (
      page: const ForgotPasswordPage(),
      etat: const AuthState(status: AuthStatus.nonAuthentifie),
    ),
    'Réinitialisation': (
      page: const ResetPasswordPage(emailPrerempli: 'balla@widjila.com'),
      etat: const AuthState(status: AuthStatus.nonAuthentifie),
    ),
    'Démarrage': (
      page: const SplashPage(),
      etat: const AuthState(status: AuthStatus.inconnu),
    ),
  };

  for (final entree in ecrans.entries) {
    group('${entree.key} — balayage des formats', () {
      for (final format in tousLesFormats) {
        testWidgets('sans débordement sur $format', (tester) async {
          auth = bloc(entree.value.etat);

          await pomperPage(
            tester,
            entree.value.page,
            auth: auth,
            taille: format.taille,
          );
          // Pas de `pumpAndSettle` : le splash anime un indicateur circulaire,
          // qui reprogramme une image sans fin. Attendre le repos, ici, serait
          // attendre pour toujours.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(tester.takeException(), isNull,
              reason: 'débordement de mise en page sur $format');
        });
      }
    });
  }
}
