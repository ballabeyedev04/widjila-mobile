import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/entities/abonnement.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_droits.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_formules.dart';
import 'package:suivie_chantier_mobile/features/abonnement/presentation/cubit/abonnement_cubit.dart';

class MockGetFormules extends Mock implements GetFormules {}

class MockGetDroits extends Mock implements GetDroits {}

const tEssentiel = FormuleAbonnement(
  id: 'a1',
  code: 'essentiel',
  nom: 'Essentiel',
  prix: 29,
  limiteUtilisateurs: 5,
  fonctionnalites: ['reserves', 'mobile'],
);

const tEntreprise = FormuleAbonnement(
  id: 'a3',
  code: 'entreprise',
  nom: 'Entreprise',
  surDevis: true,
  fonctionnalites: ['reserves', 'mobile', 'rapports'],
);

const tDroits = DroitsAbonnement(
  actif: true,
  source: 'abonnement',
  planCode: 'essentiel',
  planNom: 'Essentiel',
  fonctionnalites: ['reserves', 'mobile'],
  utilisateurs: UsageRessource(courant: 4, limite: 5),
  chantiers: UsageRessource(courant: 2, limite: 10),
);

void main() {
  late MockGetFormules getFormules;
  late MockGetDroits getDroits;

  setUp(() {
    getFormules = MockGetFormules();
    getDroits = MockGetDroits();
  });

  AbonnementCubit construire() =>
      AbonnementCubit(getFormules: getFormules, getDroits: getDroits);

  group('chargement', () {
    blocTest<AbonnementCubit, AbonnementState>(
      'expose les formules et les droits quand les deux appels réussissent',
      build: () {
        when(() => getFormules()).thenAnswer((_) async => const Right([tEssentiel, tEntreprise]));
        when(() => getDroits()).thenAnswer((_) async => const Right(tDroits));
        return construire();
      },
      act: (cubit) => cubit.charger(),
      expect: () => [
        const AbonnementState(status: AbonnementStatus.chargement),
        const AbonnementState(
          status: AbonnementStatus.succes,
          formules: [tEssentiel, tEntreprise],
          droits: tDroits,
        ),
      ],
    );

    // Le cas qui compte pour le client : l'essai est terminé, `GET /droits`
    // répond 403, et c'est précisément le moment où il doit voir les offres.
    blocTest<AbonnementCubit, AbonnementState>(
      'affiche quand même le catalogue quand les droits sont refusés',
      build: () {
        when(() => getFormules()).thenAnswer((_) async => const Right([tEssentiel]));
        when(() => getDroits())
            .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Abonnement requis')));
        return construire();
      },
      act: (cubit) => cubit.charger(),
      expect: () => [
        const AbonnementState(status: AbonnementStatus.chargement),
        const AbonnementState(status: AbonnementStatus.succes, formules: [tEssentiel]),
      ],
    );

    blocTest<AbonnementCubit, AbonnementState>(
      'échoue seulement quand le catalogue est indisponible',
      build: () {
        when(() => getFormules())
            .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Réseau indisponible')));
        when(() => getDroits()).thenAnswer((_) async => const Right(tDroits));
        return construire();
      },
      act: (cubit) => cubit.charger(),
      expect: () => [
        const AbonnementState(status: AbonnementStatus.chargement),
        const AbonnementState(
          status: AbonnementStatus.erreur,
          droits: tDroits,
          erreur: 'Réseau indisponible',
        ),
      ],
    );
  });

  group('formuleActuelle', () {
    test('retrouve la formule souscrite par son code', () {
      const etat = AbonnementState(formules: [tEssentiel, tEntreprise], droits: tDroits);
      expect(etat.formuleActuelle, tEssentiel);
    });

    test('reste nulle quand la formule souscrite a quitté le catalogue', () {
      // Une formule retirée de la vente ne doit pas faire disparaître
      // l'historique : l'organisation garde ses droits, l'écran se contente
      // de ne plus surligner de carte.
      const etat = AbonnementState(formules: [tEntreprise], droits: tDroits);
      expect(etat.formuleActuelle, isNull);
    });
  });

  group('DroitsAbonnement.peut', () {
    test('ouvre tout pendant l’essai (fonctionnalites nulle)', () {
      const essai = DroitsAbonnement(actif: true, source: 'essai', essaiEnCours: true);
      expect(essai.peut('rapports'), isTrue);
      expect(essai.peut('api'), isTrue);
    });

    test('n’ouvre rien avec une liste VIDE', () {
      // `null` (toutes) et `[]` (aucune) sont deux choses différentes : les
      // confondre donnerait tout à une organisation sans droits.
      const sansDroit = DroitsAbonnement(actif: true, source: 'abonnement', fonctionnalites: []);
      expect(sansDroit.peut('reserves'), isFalse);
    });

    test('n’ouvre rien quand l’abonnement est inactif', () {
      const inactif = DroitsAbonnement(fonctionnalites: ['reserves']);
      expect(inactif.peut('reserves'), isFalse);
    });

    test('respecte la liste de la formule', () {
      expect(tDroits.peut('reserves'), isTrue);
      expect(tDroits.peut('rapports'), isFalse);
    });
  });

  group('UsageRessource', () {
    test('traite une limite nulle comme illimitée', () {
      const usage = UsageRessource(courant: 120);
      expect(usage.illimite, isTrue);
      expect(usage.atteint, isFalse);
    });

    test('signale le plafond atteint', () {
      expect(const UsageRessource(courant: 5, limite: 5).atteint, isTrue);
      expect(const UsageRessource(courant: 4, limite: 5).atteint, isFalse);
    });

    test('lit la forme servie par l’API', () {
      final usage = UsageRessource.fromJson({'courant': 3, 'limite': null});
      expect(usage.courant, 3);
      expect(usage.illimite, isTrue);
    });
  });

  group('FormuleAbonnement.fromJson', () {
    test('déduit « sur devis » d’un prix absent', () {
      final formule = FormuleAbonnement.fromJson({
        'id': 'a3',
        'code': 'entreprise',
        'nom': 'Entreprise',
        'prix': null,
        'limiteUtilisateurs': null,
        'fonctionnalites': ['reserves'],
      });
      expect(formule.surDevis, isTrue);
      expect(formule.prix, isNull);
      // `null` = illimité, jamais -1.
      expect(formule.limiteUtilisateurs, isNull);
    });

    test('conserve le prix servi par le serveur sans le recalculer', () {
      final formule = FormuleAbonnement.fromJson({
        'id': 'a1',
        'code': 'essentiel',
        'nom': 'Essentiel',
        'prix': 29.5,
        'devise': 'EUR',
        'periode': 'mois',
      });
      expect(formule.prix, 29.5);
      expect(formule.surDevis, isFalse);
    });
  });
}
