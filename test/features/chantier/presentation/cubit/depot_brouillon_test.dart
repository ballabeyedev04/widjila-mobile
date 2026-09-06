import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/creer_structure.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/depot_plans_cubit.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/uploader_plan.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/code_niveau.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/usecases/creer_code_niveau.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/usecases/get_codes_niveau.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';

/// Le dépôt de plans AVANT que le chantier n'existe — le mode « brouillon ».
///
/// ## Le parcours demandé
///
/// L'entreprise dépose son plan global, entre dans ses bâtiments, remplit
/// SOUS-SOLS / ÉTAGES / TOITURE, puis appuie sur « Envoyer » : le formulaire
/// de demande de chantier s'ouvre alors, et les plans sont rattachés à la
/// demande créée.
///
/// L'ordre inverse — formulaire d'abord — était celui de l'application, parce
/// que `POST /chantiers/:chantierId/plans` exige un chantier. La saisie est
/// donc RETENUE, puis rejouée d'un bloc.
///
/// ## Ce que ces tests verrouillent
///
/// 1. En brouillon, rien ne part au serveur — sauf la lecture des codes, qui
///    sont partagés par l'organisation.
/// 2. Ce qui est saisi s'affiche quand même : sans cela l'écran resterait vide
///    et l'utilisateur ne saurait pas ce qu'il a déjà fourni.
/// 3. Le rejeu respecte l'ordre imposé par les dépendances, et traduit les
///    identifiants temporaires en identifiants serveur.
/// 4. Un échec en cours de rejeu est signalé sans TOUT défaire : la demande
///    existe, et l'écran rouvert dessus permet de compléter.

class _MockStructure extends Mock implements GetChantierStructure {}

class _MockPlans extends Mock implements GetPlansChantier {}

class _MockCodes extends Mock implements GetCodesNiveau {}

class _MockCreerCode extends Mock implements CreerCodeNiveau {}

class _MockCreerBatiment extends Mock implements CreerBatiment {}

class _MockCreerEtage extends Mock implements CreerEtage {}

class _MockUploader extends Mock implements UploaderPlan {}

void main() {
  late _MockStructure structure;
  late _MockPlans plans;
  late _MockCodes codes;
  late _MockCreerCode creerCode;
  late _MockCreerBatiment creerBatiment;
  late _MockCreerEtage creerEtage;
  late _MockUploader uploader;

  // `any(named: 'typeNiveau')` porte sur un type non primitif : mocktail exige
  // une valeur de repli pour construire son matcher.
  setUpAll(() => registerFallbackValue(TypeNiveau.etage));

  setUp(() {
    structure = _MockStructure();
    plans = _MockPlans();
    codes = _MockCodes();
    creerCode = _MockCreerCode();
    creerBatiment = _MockCreerBatiment();
    creerEtage = _MockCreerEtage();
    uploader = _MockUploader();

    when(() => codes()).thenAnswer((_) async => Right([
          CodeNiveau(id: 'c1', typeNiveau: TypeNiveau.sousSol, code: 'SS1', standard: true),
        ]));
    when(() => structure(any()))
        .thenAnswer((_) async => const Right(ChantierStructure()));
    when(() => plans(any())).thenAnswer((_) async => const Right(<Plan>[]));
  });

  DepotPlansCubit creer({String? chantierId}) => DepotPlansCubit(
        chantierId: chantierId,
        getStructure: structure,
        getPlans: plans,
        getCodes: codes,
        creerCode: creerCode,
        creerBatiment: creerBatiment,
        creerEtage: creerEtage,
        uploaderPlan: uploader,
      );

  /// Un cubit en brouillon, chargé, avec un bâtiment et un niveau saisis.
  Future<DepotPlansCubit> brouillonRempli() async {
    final cubit = creer();
    await cubit.charger();
    await cubit.deposerPlanGlobal(cheminFichier: '/tmp/global.pdf', nom: 'Plan masse');
    await cubit.ajouterBatiment(nom: 'Bâtiment A');
    await cubit.ajouterNiveau(
      batimentId: cubit.state.batiments.single.id,
      typeNiveau: TypeNiveau.sousSol,
      codeNiveau: 'SS1',
      description: 'Parking',
      cheminFichier: '/tmp/ss1.pdf',
      nomFichier: 'SS1.pdf',
    );
    return cubit;
  }

  group('en brouillon, rien ne part au serveur', () {
    test('le chargement ne demande ni structure ni plans', () async {
      // Il n'y a pas encore de chantier : ces deux appels partiraient avec un
      // identifiant vide et échoueraient, barrant l'écran d'une erreur.
      final cubit = creer();

      await cubit.charger();

      verifyNever(() => structure(any()));
      verifyNever(() => plans(any()));
      expect(cubit.state.status, DepotStatus.pret);
    });

    test('les CODES, eux, sont bien lus', () async {
      // Ils appartiennent à l'organisation, pas au chantier : c'est ce qui
      // permet à l'entreprise d'en créer un que le suivant retrouvera.
      final cubit = creer();

      await cubit.charger();

      verify(() => codes()).called(1);
      expect(cubit.state.codes, hasLength(1));
    });

    test('ajouter un bâtiment ou un niveau ne déclenche aucun appel', () async {
      final cubit = await brouillonRempli();

      // `verifyZeroInteractions` plutôt que `verifyNever` avec des matchers :
      // sur une méthode jamais appelée, les matchers restent enregistrés et
      // viennent perturber l'appel suivant d'un AUTRE mock.
      verifyZeroInteractions(creerBatiment);
      verifyZeroInteractions(creerEtage);
      verifyZeroInteractions(uploader);
      expect(cubit.brouillon, isTrue);
    });
  });

  group('ce qui est saisi est visible', () {
    test('le bâtiment et son niveau apparaissent dans la bonne section', () async {
      final cubit = await brouillonRempli();

      final batiment = cubit.state.batiments.single;
      expect(batiment.nom, 'Bâtiment A');
      expect(batiment.etages.single.codeNiveau, 'SS1');
      expect(batiment.etages.single.typeNiveau, TypeNiveau.sousSol);
      // Le code fait office de nom, comme côté serveur.
      expect(batiment.etages.single.nom, 'SS1');
    });

    test('le niveau servi porte sa pastille — un plan lui est rattaché', () async {
      final cubit = await brouillonRempli();

      final idNiveau = cubit.state.batiments.single.etages.single.id;
      expect(cubit.state.plans.any((p) => p.etage?.id == idNiveau), isTrue);
    });

    test('le plan global est reconnaissable — sans bâtiment ni niveau', () async {
      final cubit = await brouillonRempli();

      final global = cubit.state.plans.where(
        (p) => p.batiment == null && p.etage == null && p.zone == null,
      );
      expect(global, hasLength(1));
      expect(global.single.nom, 'Plan masse');
    });

    test('un second plan global REMPLACE le premier', () async {
      // Deux lignes laisseraient l'utilisateur sans savoir laquelle part.
      final cubit = await brouillonRempli();

      await cubit.deposerPlanGlobal(cheminFichier: '/tmp/autre.pdf', nom: 'Plan masse v2');

      final globaux = cubit.state.plans.where(
        (p) => p.batiment == null && p.etage == null && p.zone == null,
      );
      expect(globaux, hasLength(1));
      expect(globaux.single.nom, 'Plan masse v2');
    });
  });

  group('envoyerVers — le rejeu', () {
    void stubRejeuHeureux() {
      when(() => creerBatiment(any(), nom: any(named: 'nom'), code: any(named: 'code')))
          .thenAnswer((_) async => const Right(BatimentStructure(id: 'bat-reel', nom: 'Bâtiment A')));
      when(() => creerEtage(any(), any(),
              nom: any(named: 'nom'),
              typeNiveau: any(named: 'typeNiveau'),
              codeNiveau: any(named: 'codeNiveau'),
              description: any(named: 'description')))
          .thenAnswer((_) async => const Right(EtageStructure(id: 'etage-reel', nom: 'SS1')));
      when(() => uploader(
            chantierId: any(named: 'chantierId'),
            cheminFichier: any(named: 'cheminFichier'),
            nom: any(named: 'nom'),
            etageId: any(named: 'etageId'),
          )).thenAnswer((_) async => const Right(Plan(
            id: 'p1', chantierId: 'chantier-42', nom: 'Plan', fichierUrl: '/x',
            format: PlanFormat.pdf,
          )));
    }

    test('rien à envoyer tant que rien n’a été saisi', () async {
      final cubit = creer();
      await cubit.charger();

      // Une demande sans le moindre plan n'aurait rien à faire examiner.
      expect(cubit.aQuelqueChoseAEnvoyer, isFalse);
    });

    test('téléverse le plan global, crée le bâtiment, puis le niveau et son plan', () async {
      stubRejeuHeureux();
      final cubit = await brouillonRempli();

      final echec = await cubit.envoyerVers('chantier-42');

      expect(echec, isNull);
      // Le bâtiment part sur le chantier qui vient d'être créé.
      verify(() => creerBatiment('chantier-42', nom: 'Bâtiment A', code: null)).called(1);
      // Le niveau part sur l'identifiant RÉEL du bâtiment, pas sur le
      // temporaire : c'est toute la traduction que fait le rejeu.
      verify(() => creerEtage('chantier-42', 'bat-reel',
          nom: 'SS1',
          typeNiveau: TypeNiveau.sousSol,
          codeNiveau: 'SS1',
          description: 'Parking')).called(1);
      // Deux téléversements : le global, puis celui du niveau.
      //
      // TOUS les arguments en matchers : mocktail refuse qu'on mélange une
      // valeur littérale et un matcher dans le même appel. La valeur attendue
      // se vérifie donc sur ce qui est capturé.
      final chantiersVises = verify(() => uploader(
            chantierId: captureAny(named: 'chantierId'),
            cheminFichier: any(named: 'cheminFichier'),
            nom: any(named: 'nom'),
            etageId: any(named: 'etageId'),
          )).captured;
      expect(chantiersVises, ['chantier-42', 'chantier-42']);
    });

    test('le plan du niveau porte l’identifiant d’étage rendu par le serveur', () async {
      stubRejeuHeureux();
      final cubit = await brouillonRempli();

      await cubit.envoyerVers('chantier-42');

      final appels = verify(() => uploader(
            chantierId: any(named: 'chantierId'),
            cheminFichier: any(named: 'cheminFichier'),
            nom: any(named: 'nom'),
            etageId: captureAny(named: 'etageId'),
          )).captured;
      // Le global n'a pas d'étage, celui du niveau porte l'identifiant réel.
      expect(appels, containsAll(<Object?>[null, 'etage-reel']));
    });

    test('le cubit quitte le brouillon une fois la demande créée', () async {
      stubRejeuHeureux();
      final cubit = await brouillonRempli();

      await cubit.envoyerVers('chantier-42');

      expect(cubit.brouillon, isFalse);
      expect(cubit.chantierId, 'chantier-42');
      // Et l'écran montre désormais l'état RÉEL du serveur.
      verify(() => structure('chantier-42')).called(1);
    });

    test('un échec est renvoyé, et ce qui est passé n’est pas défait', () async {
      stubRejeuHeureux();
      when(() => creerEtage(any(), any(),
              nom: any(named: 'nom'),
              typeNiveau: any(named: 'typeNiveau'),
              codeNiveau: any(named: 'codeNiveau'),
              description: any(named: 'description')))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Niveau refusé')));
      final cubit = await brouillonRempli();

      final echec = await cubit.envoyerVers('chantier-42');

      expect(echec, 'Niveau refusé');
      // Le bâtiment déjà créé RESTE : tout défaire effacerait un travail que
      // rien ne permettrait de retrouver.
      verify(() => creerBatiment('chantier-42', nom: 'Bâtiment A', code: null)).called(1);
      // Et le chantier existe : l'écran rouvert dessus permet de compléter.
      expect(cubit.brouillon, isFalse);
    });

    test('un échec sur le plan global arrête le rejeu avant la structure', () async {
      stubRejeuHeureux();
      when(() => uploader(
            chantierId: any(named: 'chantierId'),
            cheminFichier: any(named: 'cheminFichier'),
            nom: any(named: 'nom'),
            etageId: any(named: 'etageId'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Fichier refusé')));
      final cubit = await brouillonRempli();

      final echec = await cubit.envoyerVers('chantier-42');

      expect(echec, 'Fichier refusé');
      verifyNever(() => creerBatiment(any(), nom: any(named: 'nom'), code: any(named: 'code')));
    });
  });

  group('le mode normal n’est pas touché', () {
    test('avec un chantier, le chargement interroge bien le serveur', () async {
      final cubit = creer(chantierId: 'chantier-7');

      await cubit.charger();

      verify(() => structure('chantier-7')).called(1);
      verify(() => plans('chantier-7')).called(1);
      expect(cubit.brouillon, isFalse);
    });

    test('avec un chantier, un ajout part immédiatement', () async {
      when(() => creerBatiment(any(), nom: any(named: 'nom'), code: any(named: 'code')))
          .thenAnswer((_) async => const Right(BatimentStructure(id: 'b1', nom: 'A')));
      final cubit = creer(chantierId: 'chantier-7');
      await cubit.charger();

      await cubit.ajouterBatiment(nom: 'Bâtiment A');

      verify(() => creerBatiment('chantier-7', nom: 'Bâtiment A', code: null)).called(1);
    });
  });
}
