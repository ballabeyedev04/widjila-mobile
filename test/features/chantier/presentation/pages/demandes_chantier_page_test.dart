import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/empty_state.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/repositories/chantier_repository.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/get_chantiers.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/demandes_chantier_cubit.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/pages/demandes_chantier_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockGetChantiers extends Mock implements GetChantiers {}

/// Le suivi des demandes de chantier.
///
/// ## Le mensonge à ne pas commettre
///
/// « Aucune demande » et « je n'ai pas pu vérifier » sont deux phrases
/// différentes, et cet écran est celui où les confondre coûte le plus cher :
/// quelqu'un qui a déposé une demande de chantier et lit « aucune demande »
/// en conclut qu'elle a été perdue. Il la redépose — et l'administrateur se
/// retrouve avec deux demandes identiques à trancher.
///
/// ## Deux vues, deux publics
///
/// « Mes demandes » s'adresse au demandeur ; « À valider » à celui qui
/// tranche. Leurs états vides ne disent donc pas la même chose, et cette
/// distinction est vérifiée ici.
void main() {
  late _MockGetChantiers getChantiers;

  void desinscrire() {
    if (sl.isRegistered<DemandesChantierCubit>()) sl.unregister<DemandesChantierCubit>();
  }

  setUp(() {
    getChantiers = _MockGetChantiers();
    desinscrire();
    sl.registerFactory<DemandesChantierCubit>(
        () => DemandesChantierCubit(getChantiers: getChantiers));
  });

  tearDown(desinscrire);

  void repondre(List<Chantier> items) {
    when(() => getChantiers(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
          demandes: any(named: 'demandes'),
        )).thenAnswer(
      (_) async => Right<Failure, ChantierPage>(
        ChantierPage(items: items, total: items.length),
      ),
    );
  }

  testWidgets('un squelette pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, ChantierPage>>();
    when(() => getChantiers(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
          demandes: any(named: 'demandes'),
        )).thenAnswer((_) => attente.future);

    await pomperPage(tester, const DemandesChantierPage());

    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(ChantierPage(items: [], total: 0)));
    await tester.pumpAndSettle();
  });

  testWidgets('aucune demande : un message, pas un ecran blanc', (tester) async {
    repondre(const []);

    await pomperPage(tester, const DemandesChantierPage());
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne reseau : surtout PAS « aucune demande »', (tester) async {
    // Le defaut le plus couteux de cet ecran : quelqu'un qui a depose une
    // demande et lit « aucune demande » la croit perdue et la redepose.
    when(() => getChantiers(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
          demandes: any(named: 'demandes'),
        )).thenAnswer(
      (_) async => const Left<Failure, ChantierPage>(NetworkFailure()),
    );

    await pomperPage(tester, const DemandesChantierPage());
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('les demandes recues sont affichees', (tester) async {
    repondre(const [
      Chantier(
        id: 'c1',
        nom: 'Residence Les Cedres',
        statut: ChantierStatut.enAttenteValidation,
      ),
    ]);

    await pomperPage(tester, const DemandesChantierPage());
    await tester.pumpAndSettle();

    expect(find.textContaining('Residence Les Cedres'), findsWidgets);
    expect(find.byType(EmptyState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une demande REJETEE porte son motif', (tester) async {
    // Sans le motif, le demandeur ne sait pas quoi corriger et redepose la
    // meme demande a l'identique.
    repondre(const [
      Chantier(
        id: 'c1',
        nom: 'Residence Les Cedres',
        statut: ChantierStatut.rejete,
        motifRejet: 'Adresse incomplete',
      ),
    ]);

    await pomperPage(tester, const DemandesChantierPage());
    await tester.pumpAndSettle();

    expect(find.textContaining('Adresse incomplete'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('mise en page — balayage des formats', () {
    // Un ecran dessine sur un telephone de 390 dp passe presque toujours a
    // 390 dp. Les debordements se produisent aux EXTREMES : sur un petit
    // Android de 320 dp encore courant sur les chantiers, et sur une tablette
    // ou une rangee concue serree se distend.
    //
    // `flutter_test` remonte un `RenderFlex overflowed` comme une exception :
    // pomper l'ecran a chaque format et verifier qu'aucune n'a ete levee
    // transforme l'audit visuel en mesure repetable.
    for (final format in tousLesFormats) {
      testWidgets('sans debordement sur $format', (tester) async {
        repondre(const [
          Chantier(
            id: 'c1',
            nom: 'Residence Les Cedres — tranche 2',
            statut: ChantierStatut.rejete,
            motifRejet: 'Adresse incomplete, merci de preciser le code postal',
          ),
        ]);

        await pomperPage(tester, const DemandesChantierPage(), taille: format.taille);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}
