import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/account/data/datasources/account_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/account/data/repositories/account_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/account/domain/entities/session_active.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/entities/user.dart';

class MockAccountRemoteDataSource extends Mock implements AccountRemoteDataSource {}

User _user({String? telephone, String? fonction}) => User(
      id: 'u1',
      nom: 'BEYE',
      prenom: 'Balla',
      email: 'balla@example.com',
      telephone: telephone,
      fonction: fonction,
      role: UserRole.chefProjet,
      statut: 'actif',
    );

SessionActive _session(String id) => SessionActive(
      id: id,
      createdAt: DateTime(2026, 1, 1),
      expiresAt: DateTime(2026, 2, 1),
    );

void main() {
  late MockAccountRemoteDataSource remote;
  late AccountRepositoryImpl repository;

  setUp(() {
    remote = MockAccountRemoteDataSource();
    repository = AccountRepositoryImpl(remote);
  });

  group('getSessions', () {
    test('succès : renvoie Right avec la liste des sessions actives', () async {
      when(() => remote.getSessions()).thenAnswer((_) async => [_session('s1'), _session('s2')]);

      final result = await repository.getSessions();

      expect(result, isA<Right>());
      result.fold(
        (_) => fail('doit réussir'),
        (sessions) => expect(sessions.map((s) => s.id).toList(), ['s1', 's2']),
      );
    });

    test('NetworkException : renvoie Left(NetworkFailure)', () async {
      when(() => remote.getSessions()).thenThrow(const NetworkException());

      final result = await repository.getSessions();

      expect(result, const Left(NetworkFailure()));
    });
  });

  group('revokerSession', () {
    test('succès : renvoie Right(null)', () async {
      when(() => remote.revokerSession(any())).thenAnswer((_) async {});

      final result = await repository.revokerSession('s1');

      expect(result, const Right(null));
      verify(() => remote.revokerSession('s1')).called(1);
    });

    test('ServerException : renvoie Left(ServerFailure) avec le message et le code d\'origine', () async {
      when(() => remote.revokerSession(any()))
          .thenThrow(const ServerException(message: 'Session introuvable', statusCode: 404));

      final result = await repository.revokerSession('s1');

      expect(result, const Left(ServerFailure(errorMessage: 'Session introuvable', statusCode: 404)));
    });
  });

  group('changerLangue', () {
    test('succès : renvoie Right(null)', () async {
      when(() => remote.changerLangue(any())).thenAnswer((_) async {});

      final result = await repository.changerLangue('en');

      expect(result, const Right(null));
      verify(() => remote.changerLangue('en')).called(1);
    });

    test('UnauthorizedException : renvoie Left(AuthFailure)', () async {
      when(() => remote.changerLangue(any())).thenThrow(const UnauthorizedException());

      final result = await repository.changerLangue('en');

      expect(result, const Left(AuthFailure()));
    });
  });

  group('supprimerCompte', () {
    test('succès : renvoie Right(null)', () async {
      when(() => remote.supprimerCompte()).thenAnswer((_) async {});

      final result = await repository.supprimerCompte();

      expect(result, const Right(null));
    });

    test('ServerException : renvoie Left(ServerFailure) avec le message et le code d\'origine', () async {
      when(() => remote.supprimerCompte())
          .thenThrow(const ServerException(message: 'Suppression impossible', statusCode: 500));

      final result = await repository.supprimerCompte();

      expect(result, const Left(ServerFailure(errorMessage: 'Suppression impossible', statusCode: 500)));
    });
  });

  group('modifierProfil', () {
    test('succès : renvoie Right avec l\'utilisateur mis à jour', () async {
      when(() => remote.modifierProfil(
            nom: any(named: 'nom'),
            prenom: any(named: 'prenom'),
            telephone: any(named: 'telephone'),
            fonction: any(named: 'fonction'),
            cheminPhoto: any(named: 'cheminPhoto'),
          )).thenAnswer((_) async => _user(telephone: '+221770000000'));

      final resultat = await repository.modifierProfil(telephone: '+221770000000');

      expect(resultat.isRight(), isTrue);
      expect(resultat.getOrElse(() => _user()).telephone, '+221770000000');
    });

    test('transmet la chaîne VIDE telle quelle — c\'est ce qui efface un champ', () async {
      when(() => remote.modifierProfil(
            nom: any(named: 'nom'),
            prenom: any(named: 'prenom'),
            telephone: any(named: 'telephone'),
            fonction: any(named: 'fonction'),
            cheminPhoto: any(named: 'cheminPhoto'),
          )).thenAnswer((_) async => _user());

      await repository.modifierProfil(telephone: '');

      // `''` ne doit surtout pas être normalisé en `null` : côté serveur, le
      // premier efface le numéro, le second laisse l'ancien en place.
      verify(() => remote.modifierProfil(
            nom: null,
            prenom: null,
            telephone: '',
            fonction: null,
            cheminPhoto: null,
          )).called(1);
    });

    test('échec : convertit l\'exception en Left(Failure)', () async {
      when(() => remote.modifierProfil(
            nom: any(named: 'nom'),
            prenom: any(named: 'prenom'),
            telephone: any(named: 'telephone'),
            fonction: any(named: 'fonction'),
            cheminPhoto: any(named: 'cheminPhoto'),
          )).thenThrow(const ServerException(message: 'Cet email est déjà utilisé'));

      final resultat = await repository.modifierProfil(nom: 'Diop');

      expect(resultat.isLeft(), isTrue);
    });
  });

  group('changerMotDePasse', () {
    test('succès : transmet les deux mots de passe au datasource', () async {
      when(() => remote.changerMotDePasse(
            ancienMotDePasse: any(named: 'ancienMotDePasse'),
            nouveauMotDePasse: any(named: 'nouveauMotDePasse'),
          )).thenAnswer((_) async => 2);

      final resultat = await repository.changerMotDePasse(
        ancienMotDePasse: 'Ancien123',
        nouveauMotDePasse: 'Nouveau123',
      );

      // Le compte des AUTRES sessions fermées remonte tel quel : c'est lui qui
      // permet au message de confirmation de dire ce qui s'est réellement
      // passé sur les autres appareils.
      expect(resultat.getOrElse(() => -1), 2);
      verify(() => remote.changerMotDePasse(
            ancienMotDePasse: 'Ancien123',
            nouveauMotDePasse: 'Nouveau123',
          )).called(1);
    });

    test('échec : mot de passe actuel incorrect devient Left(Failure)', () async {
      when(() => remote.changerMotDePasse(
            ancienMotDePasse: any(named: 'ancienMotDePasse'),
            nouveauMotDePasse: any(named: 'nouveauMotDePasse'),
          )).thenThrow(const ServerException(message: 'Mot de passe actuel incorrect.'));

      final resultat = await repository.changerMotDePasse(
        ancienMotDePasse: 'faux',
        nouveauMotDePasse: 'Nouveau123',
      );

      expect(resultat.isLeft(), isTrue);
      expect(
        resultat.fold((f) => f.errorMessage, (_) => null),
        'Mot de passe actuel incorrect.',
      );
    });
  });
}
