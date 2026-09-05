import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/corps_etat/domain/entities/corps_etat.dart';
import 'package:suivie_chantier_mobile/features/corps_etat/domain/usecases/get_corps_etat_actifs.dart';
import 'package:suivie_chantier_mobile/features/phase/domain/entities/phase_referentiel.dart';
import 'package:suivie_chantier_mobile/features/phase/domain/usecases/get_phases_actives.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/creer_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserve_wizard_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/pages/reserve_wizard_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/pompe_page.dart';

class _MockStructure extends Mock implements GetChantierStructure {}

class _MockCreer extends Mock implements CreerReserve {}

class _MockCorpsEtat extends Mock implements GetCorpsEtatActifs {}

class _MockPhases extends Mock implements GetPhasesActives {}

/// L'assistant de création d'une réserve.
///
/// ## Trois chargements, une seule raison de ne pas s'ouvrir
///
/// L'assistant lance ensemble la structure du chantier, le catalogue des
/// corps d'état et celui des phases. Seule la structure lui est
/// indispensable : les deux catalogues alimentent des champs FACULTATIFS.
///
/// Leur échec est donc ignoré volontairement. C'est le comportement qui
/// compte ici : sur un chantier, un référentiel indisponible ne doit pas
/// empêcher de consigner une fissure. La réserve se crée sans corps d'état,
/// et on complétera plus tard.
void main() {
  late _MockStructure getStructure;
  late _MockCorpsEtat getCorpsEtat;
  late _MockPhases getPhases;

  void desinscrire() {
    if (sl.isRegistered<ReserveWizardCubit>()) sl.unregister<ReserveWizardCubit>();
  }

  setUp(() {
    getStructure = _MockStructure();
    getCorpsEtat = _MockCorpsEtat();
    getPhases = _MockPhases();

    when(getCorpsEtat.call)
        .thenAnswer((_) async => const Right<Failure, List<CorpsEtat>>([]));
    when(getPhases.call)
        .thenAnswer((_) async => const Right<Failure, List<PhaseReferentiel>>([]));
    when(() => getStructure(any())).thenAnswer(
      (_) async => const Right<Failure, ChantierStructure>(ChantierStructure()),
    );

    desinscrire();
    sl.registerFactoryParam<ReserveWizardCubit, String, void>(
      (chantierId, _) => ReserveWizardCubit(
        getChantierStructure: getStructure,
        creerReserve: _MockCreer(),
        getCorpsEtatActifs: getCorpsEtat,
        getPhasesActives: getPhases,
        chantierId: chantierId,
      ),
    );
  });

  tearDown(desinscrire);

  const page = ReserveWizardPage(chantierId: 'c1');

  testWidgets('s ouvre sur un chantier sans aucun batiment', (tester) async {
    // Le cas d'un chantier dont la structure n'a pas encore été saisie : la
    // réserve reste consignable, simplement sans localisation.
    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('les REFERENTIELS en panne n empechent pas de consigner',
      (tester) async {
    // Corps d'état et phases sont facultatifs. Leur indisponibilité ne doit
    // pas fermer l'assistant : sur un chantier, la fissure se relève
    // maintenant.
    when(getCorpsEtat.call).thenAnswer(
      (_) async => const Left<Failure, List<CorpsEtat>>(NetworkFailure()),
    );
    when(getPhases.call).thenAnswer(
      (_) async => const Left<Failure, List<PhaseReferentiel>>(NetworkFailure()),
    );

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('atteint DEPUIS un plan, l assistant retient ce plan',
      (tester) async {
    // Parcours du bouton « + » : chantier, puis plan, puis ce formulaire. La
    // réserve créée sera rattachée à ce plan côté serveur — perdre
    // l'information ici la détacherait sans que rien ne le signale.
    await pomperPage(
      tester,
      const ReserveWizardPage(chantierId: 'c1', planId: 'p1', planNom: 'Niveau R+2'),
      role: UserRole.entreprise,
    );
    await tester.pumpAndSettle();

    // Le bandeau du plan n'apparait qu'a l'etape de localisation ; ce qui se
    // verifie ici est l'ETAT, c'est-a-dire ce qui partira reellement au
    // serveur, et non l'endroit ou il s'affiche.
    // Le contexte doit etre SOUS le fournisseur : `ReserveWizardPage` le
    // cree dans son propre `build`, elle est donc au-dessus de lui.
    final cubit =
        tester.element(find.byType(Scaffold).first).read<ReserveWizardCubit>();
    expect(cubit.state.planId, 'p1');
    expect(cubit.state.planNom, 'Niveau R+2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('une structure complete s affiche sans incident', (tester) async {
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
}
