import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/liste_chrome.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/entities/partenaire.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/changer_statut_partenaire.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/creer_partenaire.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/get_partenaires.dart';
import 'package:suivie_chantier_mobile/features/organisation/presentation/cubit/partenaires_cubit.dart';
import 'package:suivie_chantier_mobile/features/organisation/presentation/pages/intervenants_list_page.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/type_referentiel.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/usecases/get_types_actifs.dart';
import 'package:suivie_chantier_mobile/features/referentiel/presentation/cubit/types_referentiel_cubit.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockGetPartenaires extends Mock implements GetPartenaires {}

class _MockCreer extends Mock implements CreerPartenaire {}

class _MockChangerStatut extends Mock implements ChangerStatutPartenaire {}

class _MockTypes extends Mock implements GetTypesActifs {}

/// L'écran Intervenants.
///
/// ## Sa particularité
///
/// Il monte DEUX cubits : l'annuaire lui-même et le référentiel des types
/// (administrable côté serveur, donc chargé à part). Le second sert les
/// puces de filtre. Si sa requête échoue, l'annuaire doit continuer de
/// s'afficher : une panne du référentiel n'est pas une panne de la liste.
void main() {
  late _MockGetPartenaires getPartenaires;

  // `any()` ne sait pas fabriquer un `ReferentielType` : mocktail lui en
  // demande un exemplaire de repli, faute de quoi il refuse le matcher.
  setUpAll(() => registerFallbackValue(ReferentielType.intervenant));

  Partenaire partenaire(String id, {bool actif = true}) => Partenaire(
        id: id,
        nom: 'Societe $id',
        type: PartenaireType.sousTraitant,
        typeCode: 'sous_traitant',
        actif: actif,
      );

  void desinscrire() {
    if (sl.isRegistered<PartenairesCubit>()) sl.unregister<PartenairesCubit>();
    if (sl.isRegistered<TypesReferentielCubit>()) sl.unregister<TypesReferentielCubit>();
  }

  setUp(() {
    getPartenaires = _MockGetPartenaires();

    final types = _MockTypes();
    when(() => types(any()))
        .thenAnswer((_) async => const Right<Failure, List<TypeReferentiel>>([]));

    desinscrire();
    sl.registerFactory<PartenairesCubit>(() => PartenairesCubit(
          getPartenaires: getPartenaires,
          creerPartenaireUsecase: _MockCreer(),
          changerStatutPartenaireUsecase: _MockChangerStatut(),
        ));
    sl.registerFactoryParam<TypesReferentielCubit, ReferentielType, void>(
      (referentiel, _) => TypesReferentielCubit(getTypesActifs: types, referentiel: referentiel),
    );
  });

  tearDown(desinscrire);

  void repondre(List<Partenaire> items) {
    when(getPartenaires.call)
        .thenAnswer((_) async => Right<Failure, List<Partenaire>>(items));
  }

  testWidgets('un squelette pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, List<Partenaire>>>();
    when(getPartenaires.call).thenAnswer((_) => attente.future);

    await pomperPage(tester, const IntervenantsListPage());

    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(const Right([]));
    await tester.pumpAndSettle();
  });

  testWidgets('annuaire vide + role qui gere : le message invite a remplir',
      (tester) async {
    repondre(const []);

    await pomperPage(tester, const IntervenantsListPage(),
        role: UserRole.conducteurTravaux);
    await tester.pumpAndSettle();

    expect(find.text('Aucun intervenant'), findsOneWidget);
    expect(find.textContaining('sous-traitants'), findsOneWidget);
    expect(find.byType(BoutonAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('annuaire vide + role en LECTURE : message seul, sans bouton mort',
      (tester) async {
    repondre(const []);

    await pomperPage(tester, const IntervenantsListPage(), role: UserRole.client);
    await tester.pumpAndSettle();

    expect(find.text('Aucun intervenant'), findsOneWidget);
    expect(find.byType(BoutonAction), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : une erreur, pas un annuaire vide', (tester) async {
    when(getPartenaires.call).thenAnswer(
      (_) async =>
          const Left<Failure, List<Partenaire>>(ServerFailure(errorMessage: 'Indisponible')),
    );

    await pomperPage(tester, const IntervenantsListPage());
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Aucun intervenant'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('le referentiel en panne ne fait pas tomber l annuaire', (tester) async {
    // Deux requêtes indépendantes : celle des types alimente seulement les
    // puces de filtre. Son échec ne doit rien retirer à la liste.
    if (sl.isRegistered<TypesReferentielCubit>()) sl.unregister<TypesReferentielCubit>();
    final typesEnPanne = _MockTypes();
    when(() => typesEnPanne(any())).thenAnswer(
      (_) async =>
          const Left<Failure, List<TypeReferentiel>>(ServerFailure(errorMessage: 'HS')),
    );
    sl.registerFactoryParam<TypesReferentielCubit, ReferentielType, void>(
      (referentiel, _) =>
          TypesReferentielCubit(getTypesActifs: typesEnPanne, referentiel: referentiel),
    );

    repondre([partenaire('a'), partenaire('b')]);

    await pomperPage(tester, const IntervenantsListPage());
    await tester.pumpAndSettle();

    expect(find.textContaining('Societe a'), findsOneWidget);
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
        repondre([partenaire('a'), partenaire('b', actif: false)]);

        await pomperPage(
          tester,
          const IntervenantsListPage(),
          role: UserRole.conducteurTravaux,
          taille: format.taille,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}
