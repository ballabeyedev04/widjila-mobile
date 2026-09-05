import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/entities/abonnement.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_droits.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_formules.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_historique_abonnement.dart';
import 'package:suivie_chantier_mobile/features/abonnement/presentation/cubit/abonnement_cubit.dart';

class MockGetFormules extends Mock implements GetFormules {}

class MockGetDroits extends Mock implements GetDroits {}

class MockGetHistorique extends Mock implements GetHistoriqueAbonnement {}

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
  late MockGetHistorique getHistorique;

  setUp(() {
    getFormules = MockGetFormules();
    getDroits = MockGetDroits();
    getHistorique = MockGetHistorique();
  });

  AbonnementCubit construire() => AbonnementCubit(
        getFormules: getFormules,
        getDroits: getDroits,
        getHistorique: getHistorique,
      );

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

  group('historique des paiements', () {
    const tPayee = SouscriptionHistorique(
      id: 's1', planCode: 'essentiel', planNom: 'Essentiel',
      prixPaye: 29, devise: 'EUR', periode: 'mois', statut: 'active',
    );
    const tEnAttente = SouscriptionHistorique(
      id: 's2', planCode: 'pro', planNom: 'Pro',
      prixPaye: 79, devise: 'EUR', periode: 'mois', statut: 'en_attente',
    );
    const tExpiree = SouscriptionHistorique(
      id: 's3', planCode: 'essentiel', planNom: 'Essentiel',
      prixPaye: 29, devise: 'EUR', periode: 'mois', statut: 'expiree',
    );

    void stubsNominaux() {
      when(() => getFormules()).thenAnswer((_) async => const Right([tEssentiel]));
      when(() => getDroits()).thenAnswer((_) async => const Right(tDroits));
    }

    blocTest<AbonnementCubit, AbonnementState>(
      'n’est PAS demandé quand le rôle n’y a pas droit',
      build: () {
        stubsNominaux();
        return construire();
      },
      act: (cubit) => cubit.charger(),
      verify: (_) {
        // La route est gardée par GESTION côté serveur. L'appeler pour un
        // autre rôle ne produirait qu'un 403 : une requête perdue et un
        // message d'erreur sur un écran par ailleurs parfaitement utilisable.
        verifyNever(() => getHistorique());
      },
    );

    blocTest<AbonnementCubit, AbonnementState>(
      'est chargé et exposé quand le rôle y a droit',
      build: () {
        stubsNominaux();
        when(() => getHistorique())
            .thenAnswer((_) async => const Right([tPayee, tEnAttente]));
        return construire();
      },
      act: (cubit) => cubit.charger(avecHistorique: true),
      skip: 1,
      expect: () => [
        isA<AbonnementState>()
            .having((s) => s.historique.length, 'lignes', 2)
            .having((s) => s.historiqueDemande, 'historiqueDemande', true),
      ],
      verify: (_) => verify(() => getHistorique()).called(1),
    );

    blocTest<AbonnementCubit, AbonnementState>(
      'une facturation en panne ne fait PAS échouer l’écran',
      build: () {
        stubsNominaux();
        when(() => getHistorique())
            .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Indisponible')));
        return construire();
      },
      act: (cubit) => cubit.charger(avecHistorique: true),
      skip: 1,
      expect: () => [
        isA<AbonnementState>()
            .having((s) => s.status, 'status', AbonnementStatus.succes)
            .having((s) => s.formules.length, 'formules', 1)
            .having((s) => s.historique, 'historique', isEmpty),
      ],
    );

    test('totalPaye ne compte que ce que le SERVEUR reconnaît comme payé', () {
      // `en_attente` est un parcours engagé dont le paiement n'a jamais été
      // confirmé par le webhook. Le compter gonflerait le total d'un montant
      // que personne n'a versé.
      const etat = AbonnementState(historique: [tPayee, tEnAttente, tExpiree]);

      expect(etat.totalPaye, 58);
    });

    test('totalPaye vaut zéro quand rien n’a abouti', () {
      const etat = AbonnementState(historique: [tEnAttente]);
      expect(etat.totalPaye, 0);
    });
  });

  group('SouscriptionHistorique.fromJson', () {
    test('lit la forme servie par l’API', () {
      final ligne = SouscriptionHistorique.fromJson(const {
        'id': 's1',
        'planCode': 'essentiel',
        'planNom': 'Essentiel',
        'prixPaye': 29.9,
        'devise': 'EUR',
        'periode': 'mois',
        'statut': 'active',
        'dateDebut': '2026-01-15T00:00:00.000Z',
        'creeLe': '2026-01-15T10:30:00.000Z',
      });

      expect(ligne.prixPaye, 29.9);
      expect(ligne.statut, 'active');
      expect(ligne.estPayee, isTrue);
      expect(ligne.dateDebut, DateTime.utc(2026, 1, 15));
    });

    test('accepte un prix rendu en CHAÎNE par le pilote SQL', () {
      // Une colonne DECIMAL peut arriver en chaîne selon le pilote. Un cast
      // direct ferait tomber TOUT l'historique sur une seule ligne.
      final ligne = SouscriptionHistorique.fromJson(const {'id': 's1', 'prixPaye': '49.50'});
      expect(ligne.prixPaye, 49.5);
    });

    test('une formule sur devis n’a pas de prix, et ce n’est pas une erreur', () {
      final ligne = SouscriptionHistorique.fromJson(const {'id': 's1', 'prixPaye': null});
      expect(ligne.prixPaye, isNull);
    });

    test('retombe sur des valeurs sûres quand des champs manquent', () {
      final ligne = SouscriptionHistorique.fromJson(const {'id': 's1'});
      expect(ligne.devise, 'EUR');
      expect(ligne.statut, 'en_attente');
      expect(ligne.estPayee, isFalse, reason: 'ne jamais présumer qu’un paiement a abouti');
    });
  });

  group('joursRestants', () {
    test('est lu tel quel depuis les droits servis par le serveur', () {
      // Jamais recalculé localement : l'horloge d'un téléphone de chantier
      // est souvent fausse, et ce chiffre déclenche une décision d'achat.
      final droits = DroitsAbonnement.fromJson(<String, dynamic>{
        'droits': <String, dynamic>{'actif': true, 'source': 'abonnement', 'joursRestants': 12},
        'usage': <String, dynamic>{},
      });
      expect(droits.joursRestants, 12);
    });

    test('reste nul quand le serveur ne le fournit pas', () {
      final droits = DroitsAbonnement.fromJson(
          <String, dynamic>{'droits': <String, dynamic>{}, 'usage': <String, dynamic>{}});
      expect(droits.joursRestants, isNull);
    });
  });
}
