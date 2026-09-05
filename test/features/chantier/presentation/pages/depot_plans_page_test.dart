import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/empty_state.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/creer_structure.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/pages/depot_plans_page.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/uploader_plan.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/code_niveau.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/usecases/creer_code_niveau.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/usecases/get_codes_niveau.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/pompe_page.dart';

class _MockStructure extends Mock implements GetChantierStructure {}

class _MockPlans extends Mock implements GetPlansChantier {}

class _MockCodes extends Mock implements GetCodesNiveau {}

class _MockCreerCode extends Mock implements CreerCodeNiveau {}

class _MockCreerBatiment extends Mock implements CreerBatiment {}

class _MockCreerEtage extends Mock implements CreerEtage {}

class _MockUploader extends Mock implements UploaderPlan {}

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

  void desinscrire() {
    if (sl.isRegistered<GetChantierStructure>()) sl.unregister<GetChantierStructure>();
    if (sl.isRegistered<GetPlansChantier>()) sl.unregister<GetPlansChantier>();
    if (sl.isRegistered<GetCodesNiveau>()) sl.unregister<GetCodesNiveau>();
    if (sl.isRegistered<CreerCodeNiveau>()) sl.unregister<CreerCodeNiveau>();
    if (sl.isRegistered<CreerBatiment>()) sl.unregister<CreerBatiment>();
    if (sl.isRegistered<CreerEtage>()) sl.unregister<CreerEtage>();
    if (sl.isRegistered<UploaderPlan>()) sl.unregister<UploaderPlan>();
  }

  setUp(() {
    getStructure = _MockStructure();
    getPlans = _MockPlans();
    getCodes = _MockCodes();

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
    sl.registerLazySingleton<CreerBatiment>(() => _MockCreerBatiment());
    sl.registerLazySingleton<CreerEtage>(() => _MockCreerEtage());
    sl.registerLazySingleton<UploaderPlan>(() => _MockUploader());
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
}
