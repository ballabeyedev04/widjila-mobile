import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/account/domain/entities/connexion_log_entry.dart';
import 'package:suivie_chantier_mobile/features/account/domain/entities/mfa_provisionnement.dart';
import 'package:suivie_chantier_mobile/features/account/domain/entities/session_active.dart';
import 'package:suivie_chantier_mobile/features/account/domain/repositories/account_repository.dart';
import 'package:suivie_chantier_mobile/features/account/presentation/cubit/settings_cubit.dart';
import 'package:suivie_chantier_mobile/features/account/presentation/cubit/settings_state.dart';

class MockAccountRepository extends Mock implements AccountRepository {}

SessionActive _session(String id) => SessionActive(
      id: id,
      createdAt: DateTime(2026, 1, 1),
      expiresAt: DateTime(2026, 2, 1),
    );

ConnexionLogEntry _connexion(String id) => ConnexionLogEntry(
      id: id,
      succes: true,
      type: 'password',
      ip: '127.0.0.1',
      createdAt: DateTime(2026, 1, 1),
    );

const _provisionnement = MfaProvisionnement(
  secret: 'SECRET123',
  otpauthUrl: 'otpauth://totp/Chantier:user?secret=SECRET123',
  qrDataUrl: 'data:image/png;base64,xxx',
);

void main() {
  late MockAccountRepository repository;

  setUp(() {
    repository = MockAccountRepository();
  });

  SettingsCubit build() => SettingsCubit(repository: repository);

  blocTest<SettingsCubit, SettingsState>(
    'charger() charge le statut MFA, les sessions et l\'historique de connexion en une seule fois',
    build: () {
      when(() => repository.getStatutMfa()).thenAnswer((_) async => const Right(true));
      when(() => repository.getSessions()).thenAnswer((_) async => Right([_session('s1')]));
      when(() => repository.getConnexions()).thenAnswer((_) async => Right([_connexion('c1')]));
      return build();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const SettingsState(status: SettingsStatus.chargement),
      isA<SettingsState>()
          .having((s) => s.status, 'status', SettingsStatus.succes)
          .having((s) => s.erreur, 'erreur', isNull)
          .having((s) => s.mfaActive, 'mfaActive', true)
          .having((s) => s.sessions.map((x) => x.id).toList(), 'sessions', ['s1'])
          .having((s) => s.connexions.map((x) => x.id).toList(), 'connexions', ['c1']),
    ],
  );

  blocTest<SettingsCubit, SettingsState>(
    'charger() émet une erreur si les sessions échouent, sans perdre le statut MFA ni l\'historique de connexion',
    build: () {
      when(() => repository.getStatutMfa()).thenAnswer((_) async => const Right(true));
      when(() => repository.getSessions()).thenAnswer((_) async => const Left(NetworkFailure()));
      when(() => repository.getConnexions()).thenAnswer((_) async => Right([_connexion('c1')]));
      return build();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const SettingsState(status: SettingsStatus.chargement),
      isA<SettingsState>()
          .having((s) => s.status, 'status', SettingsStatus.erreur)
          .having((s) => s.erreur, 'erreur', const NetworkFailure().errorMessage)
          // mfaActive est repris de l'appel réussi : une panne des sessions
          // n'efface pas les autres résultats déjà arrivés.
          .having((s) => s.mfaActive, 'mfaActive', true)
          // sessions échoue : la liste reste celle de l'état précédent
          // (vide par défaut), PAS écrasée par un résultat partiel.
          .having((s) => s.sessions, 'sessions (inchangées)', isEmpty)
          .having((s) => s.connexions.map((x) => x.id).toList(), 'connexions', ['c1']),
    ],
  );

  blocTest<SettingsCubit, SettingsState>(
    'demarrerProvisionnementMfa() puis confirmerActivationMfa() active le MFA et efface le provisionnement',
    build: () {
      when(() => repository.provisionnerMfa()).thenAnswer((_) async => const Right(_provisionnement));
      when(() => repository.activerMfa(secret: 'SECRET123', code: '123456'))
          .thenAnswer((_) async => const Right(null));
      return build();
    },
    act: (cubit) async {
      await cubit.demarrerProvisionnementMfa();
      await cubit.confirmerActivationMfa('123456');
    },
    expect: () => [
      isA<SettingsState>()
          .having((s) => s.mfaActionStatus, 'mfaActionStatus', ActionStatus.enCours)
          .having((s) => s.provisionnement, 'provisionnement', isNull),
      isA<SettingsState>()
          .having((s) => s.mfaActionStatus, 'mfaActionStatus', ActionStatus.inactif)
          .having((s) => s.provisionnement, 'provisionnement', _provisionnement),
      isA<SettingsState>()
          .having((s) => s.mfaActionStatus, 'mfaActionStatus', ActionStatus.enCours)
          .having((s) => s.provisionnement, 'provisionnement', _provisionnement),
      isA<SettingsState>()
          .having((s) => s.mfaActionStatus, 'mfaActionStatus', ActionStatus.succes)
          .having((s) => s.mfaActive, 'mfaActive', true)
          .having((s) => s.provisionnement, 'provisionnement (effacé)', isNull),
    ],
  );

  blocTest<SettingsCubit, SettingsState>(
    'desactiverMfa() désactive le MFA quand le code est valide',
    build: () {
      when(() => repository.desactiverMfa(code: '654321')).thenAnswer((_) async => const Right(null));
      return build();
    },
    seed: () => const SettingsState(mfaActive: true),
    act: (cubit) => cubit.desactiverMfa('654321'),
    expect: () => [
      isA<SettingsState>().having((s) => s.mfaActionStatus, 'mfaActionStatus', ActionStatus.enCours),
      isA<SettingsState>()
          .having((s) => s.mfaActionStatus, 'mfaActionStatus', ActionStatus.succes)
          .having((s) => s.mfaActive, 'mfaActive', false),
    ],
  );

  blocTest<SettingsCubit, SettingsState>(
    'revoquerSession() retire uniquement la session révoquée de la liste',
    build: () {
      when(() => repository.revokerSession('s1')).thenAnswer((_) async => const Right(null));
      return build();
    },
    seed: () => SettingsState(sessions: [_session('s1'), _session('s2')]),
    act: (cubit) => cubit.revoquerSession('s1'),
    expect: () => [
      isA<SettingsState>().having((s) => s.sessionActionStatus, 'sessionActionStatus', ActionStatus.enCours),
      isA<SettingsState>()
          .having((s) => s.sessionActionStatus, 'sessionActionStatus', ActionStatus.succes)
          .having((s) => s.sessions.map((x) => x.id).toList(), 'sessions restantes', ['s2']),
    ],
  );

  group('revoquerToutesSessions()', () {
    bool? resultat;

    setUp(() => resultat = null);

    blocTest<SettingsCubit, SettingsState>(
      'renvoie true et vide la liste des sessions quand le back confirme',
      build: () {
        when(() => repository.revokerToutesSessions()).thenAnswer((_) async => const Right(null));
        return build();
      },
      seed: () => SettingsState(sessions: [_session('s1'), _session('s2')]),
      act: (cubit) async => resultat = await cubit.revoquerToutesSessions(),
      expect: () => [
        isA<SettingsState>().having((s) => s.sessionActionStatus, 'sessionActionStatus', ActionStatus.enCours),
        isA<SettingsState>()
            .having((s) => s.sessionActionStatus, 'sessionActionStatus', ActionStatus.succes)
            .having((s) => s.sessions, 'sessions', isEmpty),
      ],
      verify: (_) => expect(resultat, isTrue),
    );

    blocTest<SettingsCubit, SettingsState>(
      'renvoie false et conserve les sessions ainsi que l\'erreur quand le back échoue',
      build: () {
        when(() => repository.revokerToutesSessions()).thenAnswer((_) async => const Left(NetworkFailure()));
        return build();
      },
      seed: () => SettingsState(sessions: [_session('s1')]),
      act: (cubit) async => resultat = await cubit.revoquerToutesSessions(),
      expect: () => [
        isA<SettingsState>().having((s) => s.sessionActionStatus, 'sessionActionStatus', ActionStatus.enCours),
        isA<SettingsState>()
            .having((s) => s.sessionActionStatus, 'sessionActionStatus', ActionStatus.erreur)
            .having((s) => s.sessionErreur, 'sessionErreur', const NetworkFailure().errorMessage)
            .having((s) => s.sessions.map((x) => x.id).toList(), 'sessions conservées', ['s1']),
      ],
      verify: (_) => expect(resultat, isFalse),
    );
  });

  group('changerLangue()', () {
    bool? resultat;

    setUp(() => resultat = null);

    blocTest<SettingsCubit, SettingsState>(
      'renvoie true quand le back confirme le changement',
      build: () {
        when(() => repository.changerLangue('en')).thenAnswer((_) async => const Right(null));
        return build();
      },
      act: (cubit) async => resultat = await cubit.changerLangue('en'),
      expect: () => [
        isA<SettingsState>().having((s) => s.langueActionStatus, 'langueActionStatus', ActionStatus.enCours),
        isA<SettingsState>().having((s) => s.langueActionStatus, 'langueActionStatus', ActionStatus.succes),
      ],
      verify: (_) => expect(resultat, isTrue),
    );

    blocTest<SettingsCubit, SettingsState>(
      'renvoie false quand le back échoue',
      build: () {
        when(() => repository.changerLangue('en')).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Langue invalide')));
        return build();
      },
      act: (cubit) async => resultat = await cubit.changerLangue('en'),
      expect: () => [
        isA<SettingsState>().having((s) => s.langueActionStatus, 'langueActionStatus', ActionStatus.enCours),
        isA<SettingsState>().having((s) => s.langueActionStatus, 'langueActionStatus', ActionStatus.erreur),
      ],
      verify: (_) => expect(resultat, isFalse),
    );
  });

  group('supprimerCompte()', () {
    bool? resultat;

    setUp(() => resultat = null);

    blocTest<SettingsCubit, SettingsState>(
      'renvoie true quand le back confirme la suppression',
      build: () {
        when(() => repository.supprimerCompte()).thenAnswer((_) async => const Right(null));
        return build();
      },
      act: (cubit) async => resultat = await cubit.supprimerCompte(),
      expect: () => [
        isA<SettingsState>().having((s) => s.suppressionStatus, 'suppressionStatus', ActionStatus.enCours),
        isA<SettingsState>().having((s) => s.suppressionStatus, 'suppressionStatus', ActionStatus.succes),
      ],
      verify: (_) => expect(resultat, isTrue),
    );

    blocTest<SettingsCubit, SettingsState>(
      'renvoie false et pose l\'erreur quand le back échoue',
      build: () {
        when(() => repository.supprimerCompte())
            .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Suppression impossible')));
        return build();
      },
      act: (cubit) async => resultat = await cubit.supprimerCompte(),
      expect: () => [
        isA<SettingsState>().having((s) => s.suppressionStatus, 'suppressionStatus', ActionStatus.enCours),
        isA<SettingsState>()
            .having((s) => s.suppressionStatus, 'suppressionStatus', ActionStatus.erreur)
            .having((s) => s.suppressionErreur, 'suppressionErreur', 'Suppression impossible'),
      ],
      verify: (_) => expect(resultat, isFalse),
    );
  });
}
