import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/entities/partenaire.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/changer_statut_partenaire.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/creer_partenaire.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/get_partenaires.dart';
import 'package:suivie_chantier_mobile/features/organisation/presentation/cubit/partenaires_cubit.dart';

class MockGetPartenaires extends Mock implements GetPartenaires {}

class MockCreerPartenaire extends Mock implements CreerPartenaire {}

class MockChangerStatutPartenaire extends Mock implements ChangerStatutPartenaire {}

/// Le serveur renvoie un CODE ; l'énumération n'en est qu'une lecture, pour
/// l'icône et la couleur. La fabrique part donc du code, comme la vraie
/// désérialisation — sinon `typeCode` resterait vide et le filtre, qui porte
/// sur lui, ne trouverait jamais rien.
Partenaire _partenaire(
  String id, {
  String nom = 'Sénégal BTP',
  String typeCode = 'sous_traitant',
  String? contact,
  String? email,
  bool actif = true,
}) =>
    Partenaire(
      id: id,
      nom: nom,
      type: PartenaireTypeX.fromString(typeCode),
      typeCode: typeCode,
      contact: contact,
      email: email,
      actif: actif,
    );

void main() {
  late MockGetPartenaires getPartenaires;
  late MockCreerPartenaire creerPartenaireUsecase;
  late MockChangerStatutPartenaire changerStatutPartenaireUsecase;

  setUpAll(() {
    registerFallbackValue(PartenaireType.autre);
  });

  setUp(() {
    getPartenaires = MockGetPartenaires();
    creerPartenaireUsecase = MockCreerPartenaire();
    changerStatutPartenaireUsecase = MockChangerStatutPartenaire();
  });

  PartenairesCubit build() => PartenairesCubit(
        getPartenaires: getPartenaires,
        creerPartenaireUsecase: creerPartenaireUsecase,
        changerStatutPartenaireUsecase: changerStatutPartenaireUsecase,
      );

  blocTest<PartenairesCubit, PartenairesState>(
    'charger() émet chargement puis succès avec la liste des partenaires',
    build: () {
      when(() => getPartenaires()).thenAnswer((_) async => Right([_partenaire('p1'), _partenaire('p2')]));
      return build();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const PartenairesState(status: PartenairesStatus.chargement),
      isA<PartenairesState>()
          .having((s) => s.status, 'status', PartenairesStatus.succes)
          .having((s) => s.items.length, 'items.length', 2),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'charger() émet une erreur quand le back échoue',
    build: () {
      when(() => getPartenaires()).thenAnswer((_) async => const Left(NetworkFailure()));
      return build();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const PartenairesState(status: PartenairesStatus.chargement),
      isA<PartenairesState>()
          .having((s) => s.status, 'status', PartenairesStatus.erreur)
          .having((s) => s.erreur, 'erreur', const NetworkFailure().errorMessage),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'rechercher() met à jour le champ recherche et filtre itemsFiltres par texte',
    build: build,
    seed: () => PartenairesState(items: [
      _partenaire('p1', nom: 'Sénégal BTP'),
      _partenaire('p2', nom: 'Dakar Matériaux'),
    ]),
    act: (cubit) => cubit.rechercher('dakar'),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.recherche, 'recherche', 'dakar')
          .having((s) => s.itemsFiltres.map((p) => p.id).toList(), 'itemsFiltres', ['p2']),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'filtrerParType() met à jour le filtre et itemsFiltres ne garde que le type choisi',
    build: build,
    seed: () => PartenairesState(items: [
      _partenaire('p1', typeCode: 'sous_traitant'),
      _partenaire('p2', typeCode: 'fournisseur'),
    ]),
    act: (cubit) => cubit.filtrerParType('fournisseur'),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.filtreType, 'filtreType', 'fournisseur')
          .having((s) => s.itemsFiltres.map((p) => p.id).toList(), 'itemsFiltres', ['p2']),
    ],
  );

  // Le cas qui justifie tout ce changement : un type créé depuis
  // l'administration n'existe dans AUCUNE énumération Dart. Tant que le filtre
  // comparait des énumérations, ces intervenants étaient introuvables — le
  // référentiel était administrable côté web et sans effet sur mobile.
  blocTest<PartenairesCubit, PartenairesState>(
    'filtrerParType() trouve un type AJOUTÉ par l’administrateur',
    build: build,
    seed: () => PartenairesState(items: [
      _partenaire('p1', typeCode: 'sous_traitant'),
      _partenaire('p2', typeCode: 'coordinateur_sps'),
    ]),
    act: (cubit) => cubit.filtrerParType('coordinateur_sps'),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.itemsFiltres.map((p) => p.id).toList(), 'itemsFiltres', ['p2']),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'deux types inconnus de l’énumération restent distincts',
    build: build,
    seed: () => PartenairesState(items: [
      // Tous deux lus comme `PartenaireType.autre` : les confondre reviendrait
      // à ce qu'un filtre sur l'un ramène l'autre.
      _partenaire('p1', typeCode: 'coordinateur_sps'),
      _partenaire('p2', typeCode: 'geometre'),
    ]),
    act: (cubit) => cubit.filtrerParType('geometre'),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.itemsFiltres.map((p) => p.id).toList(), 'itemsFiltres', ['p2']),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'filtrerParType(null) efface le filtre et itemsFiltres retrouve tous les items',
    build: build,
    seed: () => PartenairesState(
      filtreType: 'fournisseur',
      items: [
        _partenaire('p1', typeCode: 'sous_traitant'),
        _partenaire('p2', typeCode: 'fournisseur'),
      ],
    ),
    act: (cubit) => cubit.filtrerParType(null),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.filtreType, 'filtreType', isNull)
          .having((s) => s.itemsFiltres.length, 'itemsFiltres.length', 2),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'ajouter() succès : le nouveau partenaire est ajouté en tête de liste',
    build: () {
      when(() => creerPartenaireUsecase(
            nom: any(named: 'nom'),
            typeCode: any(named: 'typeCode'),
            email: any(named: 'email'),
            telephone: any(named: 'telephone'),
            contact: any(named: 'contact'),
            adresse: any(named: 'adresse'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => Right(_partenaire('nouveau', nom: 'Thiès Fournitures')));
      return build();
    },
    seed: () => PartenairesState(status: PartenairesStatus.succes, items: [_partenaire('p1')]),
    act: (cubit) => cubit.ajouter(nom: 'Thiès Fournitures', typeCode: 'fournisseur'),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionPartenaireStatus.enCours),
      isA<PartenairesState>()
          .having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionPartenaireStatus.succes)
          .having((s) => s.items.map((p) => p.id).toList(), 'ids', ['nouveau', 'p1']),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'ajouter() échec : l\'erreur de soumission est posée et la liste reste inchangée',
    build: () {
      when(() => creerPartenaireUsecase(
            nom: any(named: 'nom'),
            typeCode: any(named: 'typeCode'),
            email: any(named: 'email'),
            telephone: any(named: 'telephone'),
            contact: any(named: 'contact'),
            adresse: any(named: 'adresse'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Nom déjà utilisé')));
      return build();
    },
    seed: () => PartenairesState(status: PartenairesStatus.succes, items: [_partenaire('p1')]),
    act: (cubit) => cubit.ajouter(nom: 'Thiès Fournitures', typeCode: 'fournisseur'),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionPartenaireStatus.enCours),
      isA<PartenairesState>()
          .having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionPartenaireStatus.erreur)
          .having((s) => s.soumissionErreur, 'soumissionErreur', 'Nom déjà utilisé')
          .having((s) => s.items.map((p) => p.id).toList(), 'ids inchangés', ['p1']),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'reinitialiserSoumission() repasse le statut de soumission à inactif',
    build: build,
    seed: () => const PartenairesState(
      soumissionStatus: SoumissionPartenaireStatus.erreur,
      soumissionErreur: 'Nom déjà utilisé',
    ),
    act: (cubit) => cubit.reinitialiserSoumission(),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionPartenaireStatus.inactif)
          .having((s) => s.soumissionErreur, 'soumissionErreur', isNull),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'filtrerParActivite(false) ne garde que les intervenants archivés',
    build: build,
    seed: () => PartenairesState(items: [
      _partenaire('p1'),
      _partenaire('p2', actif: false),
    ]),
    act: (cubit) => cubit.filtrerParActivite(false),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.filtreActif, 'filtreActif', false)
          .having((s) => s.itemsFiltres.map((p) => p.id).toList(), 'itemsFiltres', ['p2']),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'basculerStatut() succès : la fiche est remplacée EN PLACE, sans recharger la liste',
    build: () {
      when(() => changerStatutPartenaireUsecase(
            partenaireId: any(named: 'partenaireId'),
            actif: any(named: 'actif'),
          )).thenAnswer((_) async => Right(_partenaire('p2', actif: false)));
      return build();
    },
    seed: () => PartenairesState(
      status: PartenairesStatus.succes,
      items: [_partenaire('p1'), _partenaire('p2')],
    ),
    act: (cubit) => cubit.basculerStatut('p2', activer: false),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.partenaireEnCoursDeMaj, 'partenaireEnCoursDeMaj', 'p2'),
      isA<PartenairesState>()
          .having((s) => s.partenaireEnCoursDeMaj, 'partenaireEnCoursDeMaj', isNull)
          // L'ordre est préservé : c'est ce qui garde la position de
          // défilement et la fiche ouverte au même endroit.
          .having((s) => s.items.map((p) => p.id).toList(), 'ordre inchangé', ['p1', 'p2'])
          .having((s) => s.items.last.actif, 'p2 archivé', false),
    ],
    verify: (_) {
      verify(() => changerStatutPartenaireUsecase(partenaireId: 'p2', actif: false)).called(1);
    },
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'basculerStatut() échec : le message est posé et aucune fiche ne change',
    build: () {
      when(() => changerStatutPartenaireUsecase(
            partenaireId: any(named: 'partenaireId'),
            actif: any(named: 'actif'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Droits insuffisants')));
      return build();
    },
    seed: () => PartenairesState(status: PartenairesStatus.succes, items: [_partenaire('p1')]),
    act: (cubit) => cubit.basculerStatut('p1', activer: false),
    expect: () => [
      isA<PartenairesState>().having((s) => s.partenaireEnCoursDeMaj, 'enCours', 'p1'),
      isA<PartenairesState>()
          .having((s) => s.partenaireEnCoursDeMaj, 'enCours', isNull)
          .having((s) => s.statutErreur, 'statutErreur', 'Droits insuffisants')
          .having((s) => s.items.single.actif, 'p1 toujours actif', true),
    ],
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'basculerStatut() ignore un second appel tant que le premier est en vol',
    build: () {
      when(() => changerStatutPartenaireUsecase(
            partenaireId: any(named: 'partenaireId'),
            actif: any(named: 'actif'),
          )).thenAnswer((_) async => Right(_partenaire('p1', actif: false)));
      return build();
    },
    seed: () => PartenairesState(status: PartenairesStatus.succes, items: [_partenaire('p1')]),
    // Deux appuis rapprochés : le verrou doit n'en laisser passer qu'un, sans
    // quoi la seconde requête écraserait le résultat de la première.
    act: (cubit) async {
      final premier = cubit.basculerStatut('p1', activer: false);
      await cubit.basculerStatut('p1', activer: true);
      await premier;
    },
    verify: (_) {
      verify(() => changerStatutPartenaireUsecase(
            partenaireId: any(named: 'partenaireId'),
            actif: any(named: 'actif'),
          )).called(1);
    },
  );

  blocTest<PartenairesCubit, PartenairesState>(
    'reinitialiserFiltres() efface recherche, type et activité d’un coup',
    build: build,
    seed: () => const PartenairesState(
      recherche: 'dakar',
      filtreType: 'fournisseur',
      filtreActif: false,
    ),
    act: (cubit) => cubit.reinitialiserFiltres(),
    expect: () => [
      isA<PartenairesState>()
          .having((s) => s.recherche, 'recherche', '')
          .having((s) => s.filtreType, 'filtreType', isNull)
          .having((s) => s.filtreActif, 'filtreActif', isNull)
          .having((s) => s.filtreEnPlace, 'filtreEnPlace', false),
    ],
  );
}
