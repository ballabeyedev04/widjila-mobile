import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/core/services/ouverture_fichier.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/usecases/rapport_usecases.dart';
import 'package:suivie_chantier_mobile/features/rapport/presentation/pages/rapports_list_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockGetRapports extends Mock implements GetRapports {}

class _MockGenerer extends Mock implements GenererRapport {}

class _MockSupprimer extends Mock implements SupprimerRapport {}

class _MockOuverture extends Mock implements OuvertureFichier {}

/// L'écran Rapports, dans ses quatre situations.
///
/// ## Ce que ce test protège
///
/// La page construit son cubit à partir de trois cas d'usage résolus dans
/// `sl` AU MOMENT DU `build`. Une dépendance oubliée à l'enregistrement ne se
/// voit ni à l'analyse, ni à la compilation : elle jette un
/// `StateError` de get_it la première fois qu'un utilisateur ouvre l'écran.
/// Monter réellement la page est la seule façon de s'en apercevoir avant lui.
///
/// Les quatre situations valent chacune pour elle-même : une liste vide n'est
/// pas une panne, une panne n'est pas une liste vide, et confondre les deux
/// est le défaut le plus courant de ces écrans.
void main() {
  late _MockGetRapports getRapports;

  Rapport rapport(String id) => Rapport(
        id: id,
        chantierId: 'c1',
        fichierUrl: 'https://exemple.test/$id.pdf',
        createdAt: DateTime(2026, 3, 14),
      );

  setUp(() {
    getRapports = _MockGetRapports();

    for (final desinscrire in [
      () => sl.isRegistered<GetRapports>() ? sl.unregister<GetRapports>() : null,
      () => sl.isRegistered<GenererRapport>() ? sl.unregister<GenererRapport>() : null,
      () => sl.isRegistered<SupprimerRapport>() ? sl.unregister<SupprimerRapport>() : null,
      () => sl.isRegistered<OuvertureFichier>() ? sl.unregister<OuvertureFichier>() : null,
    ]) {
      desinscrire();
    }

    sl.registerFactory<GetRapports>(() => getRapports);
    sl.registerFactory<GenererRapport>(() => _MockGenerer());
    sl.registerFactory<SupprimerRapport>(() => _MockSupprimer());
    sl.registerLazySingleton<OuvertureFichier>(() => _MockOuverture());
  });

  tearDown(() {
    if (sl.isRegistered<GetRapports>()) sl.unregister<GetRapports>();
    if (sl.isRegistered<GenererRapport>()) sl.unregister<GenererRapport>();
    if (sl.isRegistered<SupprimerRapport>()) sl.unregister<SupprimerRapport>();
    if (sl.isRegistered<OuvertureFichier>()) sl.unregister<OuvertureFichier>();
  });

  const page = RapportsListPage(chantierId: 'c1', chantierNom: 'Résidence Les Cèdres');

  testWidgets('affiche un indicateur pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, List<Rapport>>>();
    when(() => getRapports(any())).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    // Un squelette de liste, pas une roue au milieu du vide : l'écran
    // annonce la forme de ce qui arrive.
    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(const Right([]));
    await tester.pumpAndSettle();
  });

  testWidgets('liste vide : un message qui EXPLIQUE, pas un écran blanc', (tester) async {
    when(() => getRapports(any()))
        .thenAnswer((_) async => const Right<Failure, List<Rapport>>([]));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucun rapport'), findsOneWidget);
    // Le titre seul laisserait l'utilisateur devant un constat. La phrase
    // suivante lui dit ce qu'il peut faire.
    expect(find.textContaining('rapport PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : l’écran ne se fait pas passer pour vide', (tester) async {
    when(() => getRapports(any())).thenAnswer(
      (_) async => const Left<Failure, List<Rapport>>(ServerFailure(errorMessage: 'Service indisponible')),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    // Le mot « Aucun rapport » serait un mensonge : le serveur n'a rien dit.
    expect(find.text('Aucun rapport'), findsNothing);
    expect(find.byType(ErrorView), findsOneWidget);
    // Et l'utilisateur doit pouvoir réessayer sans quitter l'écran.
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche les rapports reçus', (tester) async {
    when(() => getRapports(any())).thenAnswer(
      (_) async => Right<Failure, List<Rapport>>([rapport('r1'), rapport('r2')]),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucun rapport'), findsNothing);
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
        when(() => getRapports(any())).thenAnswer(
          (_) async => Right<Failure, List<Rapport>>([rapport('r1'), rapport('r2')]),
        );

        await pomperPage(tester, page, taille: format.taille);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}
