import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/features/document/domain/entities/document.dart';
import 'package:suivie_chantier_mobile/features/document/domain/usecases/ajouter_document.dart';
import 'package:suivie_chantier_mobile/features/document/domain/usecases/get_documents.dart';
import 'package:suivie_chantier_mobile/features/document/presentation/cubit/documents_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/document/presentation/pages/documents_list_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockGetDocuments extends Mock implements GetDocuments {}

class _MockAjouter extends Mock implements AjouterDocument {}

/// L'écran « Photos & documents ».
///
/// ## Sa particularité
///
/// Il ne montre pas une liste mais TROIS onglets, alimentés par une seule
/// requête que le cubit répartit par nature de fichier. Chaque onglet a donc
/// son propre état vide, et un chantier qui n'a que des PDF doit voir « Aucune
/// photo » dans le premier onglet sans que cela ressemble à une panne.
void main() {
  late _MockGetDocuments getDocuments;

  ChantierDocument doc(String id, DocumentType type, String nom) => ChantierDocument(
        id: id,
        chantierId: 'c1',
        type: type,
        nomFichier: nom,
        fichierUrl: 'https://exemple.test/$nom',
        createdAt: DateTime(2026, 4, 2),
      );

  setUp(() {
    getDocuments = _MockGetDocuments();
    if (sl.isRegistered<DocumentsListCubit>()) sl.unregister<DocumentsListCubit>();
    sl.registerFactoryParam<DocumentsListCubit, String, void>(
      (chantierId, _) => DocumentsListCubit(
        getDocuments: getDocuments,
        ajouterDocument: _MockAjouter(),
        chantierId: chantierId,
      ),
    );
  });

  tearDown(() {
    if (sl.isRegistered<DocumentsListCubit>()) sl.unregister<DocumentsListCubit>();
  });

  void repondre(List<ChantierDocument> items) {
    when(() => getDocuments(
          chantierId: any(named: 'chantierId'),
          search: any(named: 'search'),
          type: any(named: 'type'),
        )).thenAnswer((_) async => Right<Failure, List<ChantierDocument>>(items));
  }

  const page = DocumentsListPage(chantierId: 'c1');

  testWidgets('un squelette pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, List<ChantierDocument>>>();
    when(() => getDocuments(
          chantierId: any(named: 'chantierId'),
          search: any(named: 'search'),
          type: any(named: 'type'),
        )).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(const Right([]));
    await tester.pumpAndSettle();
  });

  testWidgets('chantier sans aucun fichier : le premier onglet guide', (tester) async {
    repondre(const []);

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucune photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('des PDF mais aucune photo : l’onglet vide ne crie pas à la panne',
      (tester) async {
    // Le cas qui distingue un état vide LOCAL d'une erreur : les données sont
    // bien arrivées, c'est cet onglet-là qui n'a rien.
    repondre([doc('d1', DocumentType.doe, 'DOE.pdf')]);

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucune photo'), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : une erreur, pas un onglet vide', (tester) async {
    when(() => getDocuments(
          chantierId: any(named: 'chantierId'),
          search: any(named: 'search'),
          type: any(named: 'type'),
        )).thenAnswer((_) async =>
        const Left<Failure, List<ChantierDocument>>(ServerFailure(errorMessage: 'Indisponible')));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Aucune photo'), findsNothing);
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
        repondre([
          doc('d1', DocumentType.doe, 'DOE-lot-gros-oeuvre-tranche-2.pdf'),
          doc('d2', DocumentType.photo, 'facade-nord.jpg'),
        ]);

        await pomperPage(tester, page, taille: format.taille);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}
