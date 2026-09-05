import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/mfa_page.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/reset_password_page.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/splash_page.dart';

import '../../../../helpers/pompe_page.dart';

/// Les écrans d'entrée dans l'application.
///
/// ## Pourquoi ils sont regroupés
///
/// Ces cinq écrans n'affichent aucune donnée métier : ils affichent la
/// PROGRESSION d'une action portée par l'`AuthBloc` — au repos, en cours,
/// en erreur. Ils partagent donc exactement le même montage de test, et les
/// séparer en cinq fichiers n'aurait multiplié que l'échafaudage.
///
/// ## Ce qui est vérifié
///
/// Qu'ils se montent sans lever, dans chacun de ces états. C'est modeste, et
/// c'est précisément ce qui manquait : ce sont les seuls écrans qu'un
/// utilisateur non connecté peut atteindre, donc les seuls dont une panne
/// ferme l'application entière plutôt qu'une fonctionnalité.
///
/// La page de connexion est montée en LECTURE SEULE : aucun test ne la
/// modifie ni ne pilote sa saisie.
void main() {
  /// Un bloc figé sur [etat], qui accepte les événements sans rien faire.
  AuthBloc bloc(AuthState etat) {
    final b = _MockAuthBloc();
    whenListen(b, const Stream<AuthState>.empty(), initialState: etat);
    return b;
  }

  const repos = AuthState(status: AuthStatus.nonAuthentifie);
  const enCours = AuthState(status: AuthStatus.nonAuthentifie, enCours: true);
  const enErreur = AuthState(
    status: AuthStatus.nonAuthentifie,
    erreur: 'Identifiants incorrects.',
  );

  /// Chaque écran, avec son libellé et l'état de départ à lui donner.
  final ecrans = <String, Widget>{
    'connexion': const LoginPage(),
    'mot de passe oublie': const ForgotPasswordPage(),
    'reinitialisation': const ResetPasswordPage(),
    'code MFA': const MfaPage(),
  };

  for (final entree in ecrans.entries) {
    group(entree.key, () {
      testWidgets('se monte au repos', (tester) async {
        await pomperPage(tester, entree.value, auth: bloc(repos));
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
      });

      testWidgets('se monte pendant l envoi', (tester) async {
        await pomperPage(tester, entree.value, auth: bloc(enCours));
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
      });

      testWidgets('se monte avec une erreur du serveur', (tester) async {
        // Le message du serveur n'est jamais reformulé côté mobile : c'est
        // lui qui sait pourquoi il a refusé. L'écran doit donc le porter
        // sans se casser, quelle qu'en soit la longueur.
        await pomperPage(tester, entree.value, auth: bloc(enErreur));
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
      });
    });
  }

  group('demarrage', () {
    testWidgets('demande la verification de session des le montage',
        (tester) async {
      // Sans cet événement, l'application resterait indéfiniment sur son
      // écran de démarrage : c'est lui, et lui seul, qui déclenche la
      // décision « connecté ou non ».
      final b = bloc(const AuthState(status: AuthStatus.inconnu));

      await pomperPage(tester, const SplashPage(), auth: b);
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => b.add(const AuthCheckRequested())).called(1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('l animation d ouverture se joue jusqu au bout sans lever',
        (tester) async {
      final b = bloc(const AuthState(status: AuthStatus.inconnu));

      await pomperPage(tester, const SplashPage(), auth: b);
      // L'animation dure 1100 ms : la pomper au-delà vérifie qu'elle se
      // termine proprement, sans laisser de contrôleur en vol.
      await tester.pump(const Duration(milliseconds: 1400));

      expect(tester.takeException(), isNull);
    });
  });
}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}
