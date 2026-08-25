import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/organisation/data/datasources/organisation_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/organisation/data/repositories/organisation_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/entities/membre.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/entities/partenaire.dart';

class MockOrganisationRemoteDataSource extends Mock implements OrganisationRemoteDataSource {}

Membre _membre(String id) => Membre(
      id: id,
      nom: 'Diop',
      prenom: 'Awa',
      email: '$id@chantier.sn',
      role: UserRole.conducteurTravaux,
    );

Partenaire _partenaire(String id) => Partenaire(id: id, nom: 'Sénégal BTP', type: PartenaireType.sousTraitant);

void main() {
  late MockOrganisationRemoteDataSource remoteDataSource;
  late OrganisationRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    remoteDataSource = MockOrganisationRemoteDataSource();
    repository = OrganisationRepositoryImpl(remoteDataSource);
  });

  group('getMembres', () {
    test('succès : renvoie Right avec la liste des membres du datasource', () async {
      when(() => remoteDataSource.getMembres()).thenAnswer((_) async => [_membre('m1'), _membre('m2')]);

      final resultat = await repository.getMembres();

      expect(resultat.isRight(), isTrue);
      resultat.fold(
        (_) => fail('doit réussir'),
        (membres) => expect(membres.map((m) => m.id).toList(), ['m1', 'm2']),
      );
    });

    test('échec réseau : convertit la NetworkException en Left(NetworkFailure)', () async {
      when(() => remoteDataSource.getMembres()).thenThrow(const NetworkException());

      final resultat = await repository.getMembres();

      expect(resultat.isLeft(), isTrue);
      resultat.fold((f) => expect(f, isA<NetworkFailure>()), (_) => fail('doit échouer'));
    });
  });

  group('creerPartenaire', () {
    test('succès : renvoie Right avec le partenaire créé', () async {
      when(() => remoteDataSource.creerPartenaire(any())).thenAnswer((_) async => _partenaire('p1'));

      final resultat = await repository.creerPartenaire(nom: 'Sénégal BTP', type: PartenaireType.sousTraitant);

      expect(resultat, Right<Failure, Partenaire>(_partenaire('p1')));
    });

    test('échec serveur : convertit la ServerException en Left(ServerFailure)', () async {
      when(() => remoteDataSource.creerPartenaire(any()))
          .thenThrow(const ServerException(message: 'Nom déjà utilisé', statusCode: 409));

      final resultat = await repository.creerPartenaire(nom: 'Sénégal BTP', type: PartenaireType.sousTraitant);

      expect(resultat.isLeft(), isTrue);
      resultat.fold(
        (f) {
          expect(f, isA<ServerFailure>());
          expect(f.errorMessage, 'Nom déjà utilisé');
        },
        (_) => fail('doit échouer'),
      );
    });
  });

  group('ajouterMembre', () {
    test('succès : renvoie Right avec le résultat (membre + mot de passe temporaire)', () async {
      final attendu = AjouterMembreResult(membre: _membre('nouveau'), motDePasseTemporaire: 'Tmp!2026');
      when(() => remoteDataSource.ajouterMembre(any())).thenAnswer((_) async => attendu);

      final resultat = await repository.ajouterMembre(
        nom: 'Fall',
        prenom: 'Moussa',
        email: 'moussa.fall@chantier.sn',
        role: UserRole.conducteurTravaux,
      );

      expect(resultat, Right<Failure, AjouterMembreResult>(attendu));
    });

    test('échec : convertit l\'exception en Left(Failure) sans ajouter de membre', () async {
      when(() => remoteDataSource.ajouterMembre(any()))
          .thenThrow(const ServerException(message: 'Email déjà utilisé', statusCode: 409));

      final resultat = await repository.ajouterMembre(
        nom: 'Fall',
        prenom: 'Moussa',
        email: 'moussa.fall@chantier.sn',
        role: UserRole.conducteurTravaux,
      );

      expect(resultat.isLeft(), isTrue);
      resultat.fold(
        (f) {
          expect(f, isA<ServerFailure>());
          expect(f.errorMessage, 'Email déjà utilisé');
        },
        (_) => fail('doit échouer'),
      );
    });
  });
}
