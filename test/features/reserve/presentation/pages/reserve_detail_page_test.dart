import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve_collaboration.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/ajouter_media_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/changer_statut_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_detail.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserve_detail_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/pages/reserve_detail_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockDetail extends Mock implements GetReserveDetail {}

class _MockChangerStatut extends Mock implements ChangerStatutReserve {}

class _MockAjouterMedia extends Mock implements AjouterMediaReserve {}

class _MockRepo extends Mock implements ReserveRepository {}

/// La fiche d'une réserve.
///
/// ## Le champ qui casse les fiches
///
/// Presque tout est facultatif sur une réserve : description, échéance,
/// localisation, entreprise, assigné, photos, commentaires, historique. Une
/// fiche écrite en supposant leur présence tombe sur la première réserve
/// saisie en trois secondes sur un chantier — c'est-à-dire sur le cas le plus
/// courant.
///
/// Le test « réserve minimale » est donc le plus utile du fichier : il monte
/// la fiche avec le strict nécessaire et vérifie qu'elle ne lève rien.
void main() {
  late _MockDetail getDetail;

  void desinscrire() {
    if (sl.isRegistered<ReserveDetailCubit>()) sl.unregister<ReserveDetailCubit>();
  }

  setUp(() {
    getDetail = _MockDetail();

    final repo = _MockRepo();
    when(() => repo.getCommentaires(any())).thenAnswer(
      (_) async => const Right<Failure, List<CommentaireReserve>>([]),
    );
    when(() => repo.getAffectations(any())).thenAnswer(
      (_) async => const Right<Failure, List<AffectationReserve>>([]),
    );

    desinscrire();
    sl.registerFactoryParam<ReserveDetailCubit, String, void>(
      (reserveId, _) => ReserveDetailCubit(
        getReserveDetail: getDetail,
        changerStatutReserve: _MockChangerStatut(),
        ajouterMediaReserve: _MockAjouterMedia(),
        repository: repo,
        reserveId: reserveId,
      ),
    );
  });

  tearDown(desinscrire);

  const page = ReserveDetailPage(reserveId: 'r1');

  testWidgets('un indicateur pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, Reserve>>();
    when(() => getDetail(any())).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(
      Reserve(id: 'r1', numero: 'R-001', chantierId: 'c1', titre: 'Fissure'),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('reserve introuvable : un message, pas une fiche muette',
      (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Left<Failure, Reserve>(
        ServerFailure(errorMessage: 'Reserve introuvable', statusCode: 404),
      ),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reserve MINIMALE : aucun champ facultatif, la fiche tient',
      (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Right<Failure, Reserve>(
        Reserve(id: 'r1', numero: 'R-001', chantierId: 'c1', titre: 'Fissure mur nord'),
      ),
    );

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.textContaining('Fissure mur nord'), findsWidgets);
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reserve COMPLETE : la fiche se monte sans incident', (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => Right<Failure, Reserve>(
        Reserve(
          id: 'r1',
          numero: 'R-001',
          chantierId: 'c1',
          titre: 'Fissure mur nord',
          description: 'Fissure traversante au niveau du linteau.',
          severite: ReserveSeverite.critique,
          statut: ReserveStatut.enCours,
          dateLimite: DateTime(2026, 9, 30),
          createdAt: DateTime(2026, 9, 1),
        ),
      ),
    );

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.textContaining('Fissure mur nord'), findsWidgets);
    expect(find.byType(ErrorView), findsNothing);
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
          (_) async => Right<Failure, Reserve>(
            Reserve(
              id: 'r1',
              numero: 'R-001',
              chantierId: 'c1',
              titre: 'Fissure traversante au niveau du linteau nord',
              description: 'Reprise complete de la maconnerie a prevoir.',
              severite: ReserveSeverite.critique,
              statut: ReserveStatut.enCours,
              dateLimite: DateTime(2026, 9, 30),
              createdAt: DateTime(2026, 9, 1),
            ),
          ),
        );

        await pomperPage(
          tester,
          page,
          role: UserRole.entreprise,
          taille: format.taille,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}
