import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/piece_jointe.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/pieces_jointes_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/pieces_jointes_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/pieces_jointes_state.dart';

class _MockRepo extends Mock implements PiecesJointesRepository {}

/// Pièces jointes d'une réserve — absentes du mobile jusqu'ici.
void main() {
  late _MockRepo repo;

  const devis = PieceJointe(
    id: 'p1',
    reserveId: 'r1',
    nomFichier: 'Devis reprise.pdf',
    fichierUrl: '/uploads/reserves/pieces/p1.pdf',
    mimeType: 'application/pdf',
  );
  const photo = PieceJointe(
    id: 'p2',
    reserveId: 'r1',
    nomFichier: 'fissure.jpg',
    fichierUrl: '/uploads/reserves/pieces/p2.jpg',
  );

  setUp(() {
    repo = _MockRepo();
    when(() => repo.lister('r1')).thenAnswer((_) async => const Right<Failure, List<PieceJointe>>([devis]));
  });

  test('charger() publie les pièces de la réserve', () async {
    final cubit = PiecesJointesCubit(reserveId: 'r1', repository: repo);
    await cubit.charger();

    expect(cubit.state.status, PiecesJointesStatus.succes);
    expect(cubit.state.pieces, [devis]);
  });

  test('une pièce ajoutée passe en tête, sans rechargement', () async {
    when(() => repo.ajouter(
          'r1',
          cheminFichier: '/tmp/fissure.jpg',
          nomFichier: 'fissure.jpg',
          onProgression: any(named: 'onProgression'),
        )).thenAnswer((_) async => const Right<Failure, PieceJointe>(photo));
    final cubit = PiecesJointesCubit(reserveId: 'r1', repository: repo);
    await cubit.charger();

    final erreur = await cubit.ajouter(cheminFichier: '/tmp/fissure.jpg', nomFichier: 'fissure.jpg');

    expect(erreur, isNull);
    expect(cubit.state.pieces.map((p) => p.id), ['p2', 'p1']);
    expect(cubit.state.envoiEnCours, isFalse);
    verify(() => repo.lister('r1')).called(1);
  });

  test('un refus du serveur remonte tel quel et garde la liste', () async {
    when(() => repo.ajouter(
          'r1',
          cheminFichier: any(named: 'cheminFichier'),
          nomFichier: any(named: 'nomFichier'),
          onProgression: any(named: 'onProgression'),
        )).thenAnswer((_) async => const Left<Failure, PieceJointe>(ServerFailure(errorMessage: 'Format non reconnu')));
    final cubit = PiecesJointesCubit(reserveId: 'r1', repository: repo);
    await cubit.charger();

    final erreur = await cubit.ajouter(cheminFichier: '/tmp/x.exe', nomFichier: 'x.exe');

    expect(erreur, 'Format non reconnu');
    expect(cubit.state.pieces, [devis]);
  });

  test('une pièce supprimée quitte la liste', () async {
    when(() => repo.supprimer('p1')).thenAnswer((_) async => const Right<Failure, void>(null));
    final cubit = PiecesJointesCubit(reserveId: 'r1', repository: repo);
    await cubit.charger();

    expect(await cubit.supprimer('p1'), isNull);
    expect(cubit.state.pieces, isEmpty);
  });

  test('vue comme un document, la pièce garde son nom et son adresse', () {
    final document = devis.commeDocument;
    expect(document.nomFichier, 'Devis reprise.pdf');
    expect(document.fichierUrl, '/uploads/reserves/pieces/p1.pdf');
    expect(document.apercuIntegre, isTrue);
  });
}
