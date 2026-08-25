import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/document/domain/entities/document.dart';
import 'package:suivie_chantier_mobile/features/document/domain/usecases/ajouter_document.dart';
import 'package:suivie_chantier_mobile/features/document/domain/usecases/get_documents.dart';
import 'package:suivie_chantier_mobile/features/document/presentation/cubit/documents_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/document/presentation/cubit/documents_list_state.dart';

class MockGetDocuments extends Mock implements GetDocuments {}

class MockAjouterDocument extends Mock implements AjouterDocument {}

const _chantierId = 'chantier-1';
const _chemin = '/tmp/photo.jpg';

ChantierDocument _document(String id, {DocumentType type = DocumentType.autre}) => ChantierDocument(
      id: id,
      chantierId: _chantierId,
      type: type,
      nomFichier: 'doc-$id.pdf',
      fichierUrl: 'https://cdn.test/doc-$id.pdf',
    );

void main() {
  late MockGetDocuments getDocuments;
  late MockAjouterDocument ajouterDocument;

  setUp(() {
    getDocuments = MockGetDocuments();
    ajouterDocument = MockAjouterDocument();
  });

  DocumentsListCubit build() => DocumentsListCubit(
        getDocuments: getDocuments,
        ajouterDocument: ajouterDocument,
        chantierId: _chantierId,
      );

  blocTest<DocumentsListCubit, DocumentsListState>(
    'charger() remplace la liste avec les documents renvoyés par le back',
    build: () {
      when(() => getDocuments(chantierId: _chantierId, search: '', type: null))
          .thenAnswer((_) async => Right([_document('a'), _document('b')]));
      return build();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const DocumentsListState(status: DocumentsListStatus.chargement),
      isA<DocumentsListState>()
          .having((s) => s.status, 'status', DocumentsListStatus.succes)
          .having((s) => s.items.length, 'items.length', 2),
    ],
  );

  blocTest<DocumentsListCubit, DocumentsListState>(
    'filtrerParType() relance charger() avec le type sélectionné',
    build: () {
      when(() => getDocuments(chantierId: _chantierId, search: '', type: DocumentType.plan))
          .thenAnswer((_) async => Right([_document('p1', type: DocumentType.plan)]));
      return build();
    },
    act: (cubit) => cubit.filtrerParType(DocumentType.plan),
    expect: () => [
      isA<DocumentsListState>().having((s) => s.filtreType, 'filtreType', DocumentType.plan),
      isA<DocumentsListState>().having((s) => s.status, 'status', DocumentsListStatus.chargement),
      isA<DocumentsListState>()
          .having((s) => s.items.single.type, 'type', DocumentType.plan),
    ],
  );

  blocTest<DocumentsListCubit, DocumentsListState>(
    'émet erreur quand le back échoue',
    build: () {
      when(() => getDocuments(chantierId: _chantierId, search: '', type: null))
          .thenAnswer((_) async => const Left(NetworkFailure()));
      return build();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const DocumentsListState(status: DocumentsListStatus.chargement),
      isA<DocumentsListState>().having((s) => s.status, 'status', DocumentsListStatus.erreur),
    ],
  );

  // ── Dépôt d'un fichier ─────────────────────────────────────────────────────

  blocTest<DocumentsListCubit, DocumentsListState>(
    'deposer() insère le document créé en tête de liste, sans recharger',
    build: () {
      when(() => ajouterDocument(
            chantierId: _chantierId,
            cheminFichier: _chemin,
            type: DocumentType.photo,
          )).thenAnswer((_) async => Right(_document('neuf', type: DocumentType.photo)));
      return build();
    },
    seed: () => DocumentsListState(
      status: DocumentsListStatus.succes,
      items: [_document('ancien')],
    ),
    act: (cubit) => cubit.deposer(cheminFichier: _chemin, type: DocumentType.photo),
    expect: () => [
      isA<DocumentsListState>().having((s) => s.depotStatus, 'depotStatus', DepotStatus.enCours),
      isA<DocumentsListState>()
          .having((s) => s.depotStatus, 'depotStatus', DepotStatus.succes)
          .having((s) => s.items.first.id, 'items.first.id', 'neuf')
          .having((s) => s.items.length, 'items.length', 2),
    ],
    // Aucun rechargement : le back renvoie déjà l'objet complet.
    verify: (_) => verifyNever(() => getDocuments(
          chantierId: any(named: 'chantierId'),
          search: any(named: 'search'),
          type: any(named: 'type'),
        )),
  );

  blocTest<DocumentsListCubit, DocumentsListState>(
    "deposer() en échec conserve la liste déjà affichée",
    build: () {
      when(() => ajouterDocument(
            chantierId: _chantierId,
            cheminFichier: _chemin,
            type: DocumentType.photo,
          )).thenAnswer((_) async => const Left(NetworkFailure()));
      return build();
    },
    seed: () => DocumentsListState(
      status: DocumentsListStatus.succes,
      items: [_document('ancien')],
    ),
    act: (cubit) => cubit.deposer(cheminFichier: _chemin, type: DocumentType.photo),
    expect: () => [
      isA<DocumentsListState>().having((s) => s.depotStatus, 'depotStatus', DepotStatus.enCours),
      isA<DocumentsListState>()
          .having((s) => s.depotStatus, 'depotStatus', DepotStatus.erreur)
          .having((s) => s.depotErreur, 'depotErreur', isNotNull)
          .having((s) => s.items.length, 'items.length', 1),
    ],
  );
}
