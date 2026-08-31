import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/services/locale_controller.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/entities/login_result.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/entities/user.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/usecases/forgot_password.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/usecases/login_user.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/usecases/logout_user.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/usecases/register_user.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/usecases/reset_password.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/usecases/restaurer_session.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/usecases/verifier_mfa.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';

class MockLoginUser extends Mock implements LoginUser {}

class MockVerifierMfa extends Mock implements VerifierMfa {}

class MockLogoutUser extends Mock implements LogoutUser {}

class MockRestaurerSession extends Mock implements RestaurerSession {}

class MockRegisterUser extends Mock implements RegisterUser {}

class MockForgotPassword extends Mock implements ForgotPassword {}

class MockResetPassword extends Mock implements ResetPassword {}

class MockLocaleController extends Mock implements LocaleController {}

const tUser = User(
  id: 'u1',
  nom: 'Beye',
  prenom: 'Balla',
  email: 'balla@widjila.com',
  role: UserRole.chefProjet,
  statut: 'actif',
);

void main() {
  late MockLoginUser loginUser;
  late MockVerifierMfa verifierMfa;
  late MockLogoutUser logoutUser;
  late MockRestaurerSession restaurerSession;
  late MockRegisterUser registerUser;
  late MockForgotPassword forgotPassword;
  late MockResetPassword resetPassword;
  late MockLocaleController localeController;

  AuthBloc buildBloc() => AuthBloc(
        loginUser: loginUser,
        verifierMfa: verifierMfa,
        logoutUser: logoutUser,
        restaurerSession: restaurerSession,
        registerUser: registerUser,
        forgotPassword: forgotPassword,
        resetPassword: resetPassword,
        localeController: localeController,
      );

  setUp(() {
    loginUser = MockLoginUser();
    verifierMfa = MockVerifierMfa();
    logoutUser = MockLogoutUser();
    restaurerSession = MockRestaurerSession();
    registerUser = MockRegisterUser();
    forgotPassword = MockForgotPassword();
    resetPassword = MockResetPassword();
    localeController = MockLocaleController();
    // `unawaited` dans AuthBloc : jamais attendu explicitement par les tests,
    // mais doit renvoyer un Future valide sinon mocktail lève au premier appel.
    when(() => localeController.synchroniserDepuisCompte(any())).thenAnswer((_) async {});
  });

  group('AuthCheckRequested', () {
    // `wait` : _onCheckRequested retient volontairement son émission derrière
    // un plancher de 1200 ms (durée de l'animation du splash, voir
    // `AuthBloc._dureeMinSplash`). Sans cette attente, blocTest rend la main
    // avant le premier `emit` et n'observe aucun état.
    const attenteSplash = Duration(milliseconds: 1500);

    blocTest<AuthBloc, AuthState>(
      'émet authentifie quand une session est restaurée',
      build: () {
        when(() => restaurerSession()).thenAnswer((_) async => tUser);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      wait: attenteSplash,
      expect: () => [const AuthState(status: AuthStatus.authentifie, utilisateur: tUser)],
    );

    blocTest<AuthBloc, AuthState>(
      'émet nonAuthentifie quand aucune session n\'est récupérable',
      build: () {
        when(() => restaurerSession()).thenAnswer((_) async => null);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      wait: attenteSplash,
      expect: () => [const AuthState(status: AuthStatus.nonAuthentifie)],
    );
  });

  group('AuthLoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'émet authentifie directement quand le MFA n\'est pas requis',
      build: () {
        when(() => loginUser(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
            .thenAnswer((_) async => const Right(LoginResult(mfaRequise: false, utilisateur: tUser)));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AuthLoginRequested(identifiant: 'balla@widjila.com', motDePasse: 'x')),
      expect: () => [
        const AuthState(enCours: true),
        const AuthState(status: AuthStatus.authentifie, utilisateur: tUser),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'émet mfaRequis (et PAS authentifie) quand le backend l\'exige',
      build: () {
        when(() => loginUser(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
            .thenAnswer((_) async => const Right(LoginResult(mfaRequise: true, utilisateur: tUser)));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AuthLoginRequested(identifiant: 'balla@widjila.com', motDePasse: 'x')),
      expect: () => [
        const AuthState(enCours: true),
        const AuthState(status: AuthStatus.mfaRequis, utilisateur: tUser),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'émet une erreur et reste nonAuthentifie sur identifiants invalides',
      build: () {
        when(() => loginUser(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
            .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Identifiants invalides')));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AuthLoginRequested(identifiant: 'x', motDePasse: 'x')),
      expect: () => [
        const AuthState(enCours: true),
        const AuthState(erreur: 'Identifiants invalides'),
      ],
      verify: (bloc) => expect(bloc.state.status, AuthStatus.inconnu),
    );
  });

  group('AuthMfaSubmitted', () {
    blocTest<AuthBloc, AuthState>(
      'authentifie après un code valide',
      build: () {
        when(() => verifierMfa(code: any(named: 'code'))).thenAnswer((_) async => const Right(tUser));
        return buildBloc();
      },
      seed: () => const AuthState(status: AuthStatus.mfaRequis, utilisateur: tUser),
      act: (bloc) => bloc.add(const AuthMfaSubmitted(code: '123456')),
      expect: () => [
        const AuthState(status: AuthStatus.mfaRequis, utilisateur: tUser, enCours: true),
        const AuthState(status: AuthStatus.authentifie, utilisateur: tUser),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'reste en mfaRequis (pas authentifie) sur code invalide',
      build: () {
        when(() => verifierMfa(code: any(named: 'code')))
            .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Code invalide')));
        return buildBloc();
      },
      seed: () => const AuthState(status: AuthStatus.mfaRequis, utilisateur: tUser),
      act: (bloc) => bloc.add(const AuthMfaSubmitted(code: '000000')),
      verify: (bloc) => expect(bloc.state.status, AuthStatus.mfaRequis),
    );
  });

  group('AuthSessionExpired', () {
    blocTest<AuthBloc, AuthState>(
      'déconnecte immédiatement SANS appeler logoutUser (pas de round-trip réseau superflu)',
      build: buildBloc,
      seed: () => const AuthState(status: AuthStatus.authentifie, utilisateur: tUser),
      act: (bloc) => bloc.add(const AuthSessionExpired()),
      expect: () => [
        const AuthState(
          status: AuthStatus.nonAuthentifie,
          erreur: 'Votre session a expiré, veuillez vous reconnecter.',
        ),
      ],
      verify: (_) => verifyNever(() => logoutUser()),
    );
  });

  group('AuthLogoutRequested', () {
    blocTest<AuthBloc, AuthState>(
      'appelle logoutUser puis passe nonAuthentifie',
      build: () {
        when(() => logoutUser()).thenAnswer((_) async {});
        return buildBloc();
      },
      seed: () => const AuthState(status: AuthStatus.authentifie, utilisateur: tUser),
      act: (bloc) => bloc.add(const AuthLogoutRequested()),
      expect: () => [const AuthState(status: AuthStatus.nonAuthentifie)],
      verify: (_) => verify(() => logoutUser()).called(1),
    );
  });

  group('AuthRegisterRequested', () {
    blocTest<AuthBloc, AuthState>(
      'NE change PAS le statut de session (register ne connecte pas automatiquement)',
      build: () {
        when(() => registerUser(
              nom: any(named: 'nom'),
              prenom: any(named: 'prenom'),
              email: any(named: 'email'),
              motDePasse: any(named: 'motDePasse'),
              telephone: any(named: 'telephone'),
              fonction: any(named: 'fonction'),
              organisationNom: any(named: 'organisationNom'),
              raisonSociale: any(named: 'raisonSociale'),
              identifiants: any(named: 'identifiants'),
              organisationTelephone: any(named: 'organisationTelephone'),
              organisationEmail: any(named: 'organisationEmail'),
              organisationAdresse: any(named: 'organisationAdresse'),
              organisationVille: any(named: 'organisationVille'),
              organisationPays: any(named: 'organisationPays'),
            )).thenAnswer((_) async => const Right(tUser));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AuthRegisterRequested(
        nom: 'Beye',
        prenom: 'Balla',
        email: 'balla@widjila.com',
        motDePasse: 'Xx123456!',
      )),
      verify: (bloc) {
        expect(bloc.state.status, AuthStatus.inconnu); // inchangé
        expect(bloc.state.messageSucces, isNotNull);
      },
    );
  });
}
