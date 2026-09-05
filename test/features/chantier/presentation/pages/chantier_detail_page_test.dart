import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/get_chantier_detail.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/chantier_detail_cubit.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/pages/chantier_detail_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockDetail extends Mock implements GetChantierDetail {}

/// La fiche d'un chantier.
///
/// ## Pourquoi une fiche mérite ses tests autant qu'une liste
///
/// Une fiche n'a pas d'état vide — elle existe ou elle n'existe pas — mais
/// elle a un état plus traître : le chantier introuvable. Le serveur répond
/// 404 quand l'identifiant est faux, ou quand le cloisonnement retire l'accès
/// à quelqu'un qui vient de perdre son affectation. Dans les deux cas l'écran
/// doit le DIRE. Une fiche vide, sans message, laisse croire à un chantier
/// sans contenu.
void main() {
  late _MockDetail getDetail;

  void desinscrire() {
    if (sl.isRegistered<ChantierDetailCubit>()) sl.unregister<ChantierDetailCubit>();
  }

  setUp(() {
    getDetail = _MockDetail();
    desinscrire();
    sl.registerFactoryParam<ChantierDetailCubit, String, void>(
      (chantierId, _) =>
          ChantierDetailCubit(getChantierDetail: getDetail, chantierId: chantierId),
    );
  });

  tearDown(desinscrire);

  const page = ChantierDetailPage(chantierId: 'c1');

  testWidgets('un indicateur pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, Chantier>>();
    when(() => getDetail(any())).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(
      Chantier(id: 'c1', nom: 'Les Cedres', statut: ChantierStatut.enCours),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('chantier introuvable : un message, pas une fiche muette',
      (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Left<Failure, Chantier>(
        ServerFailure(errorMessage: 'Chantier introuvable', statusCode: 404),
      ),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.textContaining('introuvable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche la fiche recue', (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Right<Failure, Chantier>(
        Chantier(
          id: 'c1',
          nom: 'Residence Les Cedres',
          code: 'RLC-2026',
          adresse: '12 rue des Acacias',
          statut: ChantierStatut.enCours,
        ),
      ),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.textContaining('Residence Les Cedres'), findsWidgets);
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un chantier SANS description ni adresse se monte quand meme',
      (tester) async {
    // Tous ces champs sont facultatifs côté serveur. Une fiche qui suppose
    // leur présence tombe sur le premier chantier saisi à la va-vite.
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Right<Failure, Chantier>(
        Chantier(id: 'c1', nom: 'Minimal', statut: ChantierStatut.enCours),
      ),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.textContaining('Minimal'), findsWidgets);
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
        when(() => getDetail(any())).thenAnswer(
          (_) async => const Right<Failure, Chantier>(
            Chantier(
              id: 'c1',
              nom: 'Residence Les Cedres — tranche 2, batiment principal',
              code: 'RLC-2026-T2',
              adresse: '12 rue des Acacias, 34000 Montpellier',
              statut: ChantierStatut.enCours,
            ),
          ),
        );

        await pomperPage(tester, page, taille: format.taille);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}
