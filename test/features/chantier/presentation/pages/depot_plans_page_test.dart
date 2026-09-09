import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/empty_state.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/creer_structure.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/pages/depot_plans_page.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/gerer_plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/uploader_plan.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/code_niveau.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/code_appartement.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/usecases/codes_appartement.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/usecases/creer_code_niveau.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/usecases/get_codes_niveau.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockStructure extends Mock implements GetChantierStructure {}

class _MockPlans extends Mock implements GetPlansChantier {}

class _MockCodes extends Mock implements GetCodesNiveau {}

class _MockCreerCode extends Mock implements CreerCodeNiveau {}

class _MockCodesAppartement extends Mock implements GetCodesAppartement {}

class _MockCreerCodeAppartement extends Mock implements CreerCodeAppartement {}

class _MockCreerBatiment extends Mock implements CreerBatiment {}

class _MockCreerEtage extends Mock implements CreerEtage {}

class _MockUploader extends Mock implements UploaderPlan {}

class _MockCreerZone extends Mock implements CreerZone {}

class _MockModifierZone extends Mock implements ModifierZone {}

class _MockSupprimerZone extends Mock implements SupprimerZone {}

class _MockSupprimerPlan extends Mock implements SupprimerPlan {}

class _MockRemplacerFichier extends Mock implements RemplacerFichierPlan {}

/// L'écran « Envoi de plans ».
///
/// ## Le parcours qu'il sert
///
/// C'est celui de l'ENTREPRISE : elle joint ses plans à sa demande de
/// chantier. L'écran a donc besoin de la structure du chantier pour proposer
/// un niveau de rattachement — mais cette structure peut être vide, et c'est
/// même le cas normal d'une demande fraîchement déposée.
///
/// Un écran qui exigerait une structure complète bloquerait le seul parcours
/// prévu pour l'entreprise, au moment précis où elle en a besoin.
void main() {
  late _MockStructure getStructure;
  late _MockPlans getPlans;
  late _MockCodes getCodes;
  late _MockCodesAppartement codesAppartement;
  late _MockCreerZone creerZone;
  late _MockSupprimerZone supprimerZone;

  void desinscrire() {
    if (sl.isRegistered<GetChantierStructure>()) sl.unregister<GetChantierStructure>();
    if (sl.isRegistered<GetPlansChantier>()) sl.unregister<GetPlansChantier>();
    if (sl.isRegistered<GetCodesNiveau>()) sl.unregister<GetCodesNiveau>();
    if (sl.isRegistered<CreerCodeNiveau>()) sl.unregister<CreerCodeNiveau>();
    if (sl.isRegistered<GetCodesAppartement>()) sl.unregister<GetCodesAppartement>();
    if (sl.isRegistered<CreerCodeAppartement>()) sl.unregister<CreerCodeAppartement>();
    if (sl.isRegistered<CreerBatiment>()) sl.unregister<CreerBatiment>();
    if (sl.isRegistered<CreerEtage>()) sl.unregister<CreerEtage>();
    if (sl.isRegistered<UploaderPlan>()) sl.unregister<UploaderPlan>();
    if (sl.isRegistered<CreerZone>()) sl.unregister<CreerZone>();
    if (sl.isRegistered<ModifierZone>()) sl.unregister<ModifierZone>();
    if (sl.isRegistered<SupprimerZone>()) sl.unregister<SupprimerZone>();
    if (sl.isRegistered<SupprimerPlan>()) sl.unregister<SupprimerPlan>();
    if (sl.isRegistered<RemplacerFichierPlan>()) sl.unregister<RemplacerFichierPlan>();
  }

  setUp(() {
    getStructure = _MockStructure();
    getPlans = _MockPlans();
    getCodes = _MockCodes();
    codesAppartement = _MockCodesAppartement();
    when(() => codesAppartement())
        .thenAnswer((_) async => const Right<Failure, List<CodeAppartement>>([]));
    creerZone = _MockCreerZone();
    supprimerZone = _MockSupprimerZone();

    when(() => getStructure(any())).thenAnswer(
      (_) async => const Right<Failure, ChantierStructure>(ChantierStructure()),
    );
    when(() => getPlans(any()))
        .thenAnswer((_) async => const Right<Failure, List<Plan>>([]));
    when(() => getCodes())
        .thenAnswer((_) async => const Right<Failure, List<CodeNiveau>>([]));

    desinscrire();
    sl.registerLazySingleton<GetChantierStructure>(() => getStructure);
    sl.registerLazySingleton<GetPlansChantier>(() => getPlans);
    sl.registerLazySingleton<GetCodesNiveau>(() => getCodes);
    sl.registerLazySingleton<CreerCodeNiveau>(() => _MockCreerCode());
    sl.registerLazySingleton<GetCodesAppartement>(() => codesAppartement);
    sl.registerLazySingleton<CreerCodeAppartement>(() => _MockCreerCodeAppartement());
    sl.registerLazySingleton<CreerBatiment>(() => _MockCreerBatiment());
    sl.registerLazySingleton<CreerEtage>(() => _MockCreerEtage());
    sl.registerLazySingleton<UploaderPlan>(() => _MockUploader());
    sl.registerLazySingleton<CreerZone>(() => creerZone);
    sl.registerLazySingleton<ModifierZone>(() => _MockModifierZone());
    sl.registerLazySingleton<SupprimerZone>(() => supprimerZone);
    sl.registerLazySingleton<SupprimerPlan>(() => _MockSupprimerPlan());
    sl.registerLazySingleton<RemplacerFichierPlan>(() => _MockRemplacerFichier());
  });

  tearDown(desinscrire);

  const page = DepotPlansPage(chantierId: 'c1', chantierNom: 'Les Cedres');

  testWidgets('un chantier SANS structure n empeche pas le depot', (tester) async {
    // Cas normal d'une demande fraichement deposee : aucun batiment saisi.
    // Exiger une structure ici bloquerait le seul parcours prevu pour
    // l'entreprise.
    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('aucun plan deja depose : un message, pas un ecran blanc',
      (tester) async {
    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une structure existante s affiche sans incident', (tester) async {
    when(() => getStructure(any())).thenAnswer(
      (_) async => const Right<Failure, ChantierStructure>(
        ChantierStructure(
          batiments: [
            BatimentStructure(
              id: 'b1',
              nom: 'Batiment A',
              etages: [EtageStructure(id: 'e1', nom: 'R+2')],
            ),
          ],
        ),
      ),
    );

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('le referentiel des codes en panne ne ferme pas l ecran',
      (tester) async {
    // Les codes de niveau sont une aide a la saisie, pas une condition.
    when(() => getCodes()).thenAnswer(
      (_) async => const Left<Failure, List<CodeNiveau>>(NetworkFailure()),
    );

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('mise en page — balayage des formats', () {
    // L'écran de dépôt est le plus chargé du parcours entreprise : trois
    // sections de niveaux, chacune avec ses tuiles et son bouton d'ajout. En
    // paysage, la hauteur utile tombe à 320 dp pour tout cela.
    for (final format in tousLesFormats) {
      testWidgets('sans débordement sur $format', (tester) async {
        await pomperPage(tester, page, role: UserRole.entreprise, taille: format.taille);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'débordement de mise en page sur $format');
      });
    }
  });

  group('hiérarchie Niveau → Appartements → Plans', () {
    // Le client : « il faut qu'on puisse voir du R+1 avec tous les plans des
    // appartements à l'intérieur. Du R+2 avec tous les plans des appartements
    // à l'intérieur, ainsi de suite. »
    //
    // Avant, un niveau était une ligne morte : une pastille et un nom. Aucun
    // appartement, aucun plan, aucune action.

    const structure = ChantierStructure(
      batiments: [
        BatimentStructure(
          id: 'b1',
          nom: 'Bâtiment A',
          etages: [
            EtageStructure(
              id: 'e1',
              nom: 'R+1',
              zones: [
                ZoneStructure(id: 'z101', nom: 'Appartement 101'),
                ZoneStructure(id: 'z102', nom: 'Appartement 102'),
              ],
            ),
            EtageStructure(id: 'e2', nom: 'R+2', zones: [
              ZoneStructure(id: 'z201', nom: 'Appartement 201'),
            ]),
          ],
        ),
      ],
    );

    Plan planDe(String id, String nom, String zoneId) => Plan(
          id: id,
          chantierId: 'c1',
          nom: nom,
          fichierUrl: '',
          zone: PlanNiveauRef(id: zoneId, nom: 'Appartement'),
        );

    void repondre({List<Plan> plans = const []}) {
      when(() => getStructure(any())).thenAnswer(
        (_) async => const Right<Failure, ChantierStructure>(structure),
      );
      when(() => getPlans(any()))
          .thenAnswer((_) async => Right<Failure, List<Plan>>(plans));
    }

    /// Déplie le bâtiment, puis le niveau demandé.
    Future<void> ouvrir(WidgetTester tester, String niveau) async {
      await tester.tap(find.text('Bâtiment A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(niveau));
      await tester.pumpAndSettle();
    }

    testWidgets('un niveau annonce le NOMBRE de ses appartements', (tester) async {
      repondre();

      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bâtiment A'));
      await tester.pumpAndSettle();

      // Les appartements viennent du serveur : R+1 en a deux, R+2 un seul.
      expect(find.text('2 appartements'), findsOneWidget);
      expect(find.text('1 appartement'), findsOneWidget);
    });

    testWidgets('déplier R+1 montre SES appartements', (tester) async {
      repondre();

      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pumpAndSettle();
      await ouvrir(tester, 'R+1');

      expect(find.text('Appartement 101'), findsOneWidget);
      expect(find.text('Appartement 102'), findsOneWidget);
      // Ceux du R+2 restent chez lui : chaque niveau a SA liste.
      expect(find.text('Appartement 201'), findsNothing);
    });

    testWidgets('un appartement montre TOUS ses plans', (tester) async {
      repondre(plans: [
        planDe('p1', 'Plan 101.jpg', 'z101'),
        planDe('p2', 'Plan 101 bis.jpg', 'z101'),
        planDe('p3', 'Plan 102.jpg', 'z102'),
      ]);

      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pumpAndSettle();
      await ouvrir(tester, 'R+1');

      // Plusieurs plans par appartement — c'est le point central de la
      // demande : « R+1 → plusieurs appartements → plusieurs plans ».
      expect(find.text('Plan 101.jpg'), findsOneWidget);
      expect(find.text('Plan 101 bis.jpg'), findsOneWidget);
      expect(find.text('Plan 102.jpg'), findsOneWidget);
    });

    testWidgets('un appartement SANS plan le dit, et propose d en ajouter',
        (tester) async {
      repondre();

      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pumpAndSettle();
      await ouvrir(tester, 'R+1');

      expect(find.text('Aucun plan pour cet appartement'), findsNWidgets(2));
      expect(find.text('Ajouter un plan'), findsNWidgets(2));
    });

    testWidgets('un niveau SANS appartement invite à en ajouter', (tester) async {
      when(() => getStructure(any())).thenAnswer(
        (_) async => const Right<Failure, ChantierStructure>(
          ChantierStructure(batiments: [
            BatimentStructure(id: 'b1', nom: 'Bâtiment A', etages: [
              EtageStructure(id: 'e1', nom: 'R+1'),
            ]),
          ]),
        ),
      );
      when(() => getPlans(any()))
          .thenAnswer((_) async => const Right<Failure, List<Plan>>([]));

      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pumpAndSettle();
      await ouvrir(tester, 'R+1');

      expect(find.text('Aucun appartement — ajoutez ceux qui manquent.'), findsOneWidget);
      expect(find.text('Ajouter un appartement'), findsOneWidget);
    });

    testWidgets('supprimer un appartement passe par une confirmation',
        (tester) async {
      repondre();
      when(() => supprimerZone(any(), any(), any(), any()))
          .thenAnswer((_) async => const Right<Failure, void>(null));

      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pumpAndSettle();
      await ouvrir(tester, 'R+1');

      // La corbeille du PREMIER appartement.
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();

      // Rien n'est parti : la question est posée d'abord, et elle annonce que
      // les plans partent avec.
      verifyNever(() => supprimerZone(any(), any(), any(), any()));
      expect(find.text('Supprimer « Appartement 101 » et ses plans ?'), findsOneWidget);
    });
  });
}
