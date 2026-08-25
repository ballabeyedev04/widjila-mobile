import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve_collaboration.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/ajouter_media_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/changer_statut_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_detail.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserve_detail_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserve_detail_state.dart';

class MockGetReserveDetail extends Mock implements GetReserveDetail {}

class MockChangerStatutReserve extends Mock implements ChangerStatutReserve {}

class MockAjouterMediaReserve extends Mock implements AjouterMediaReserve {}

class MockReserveRepository extends Mock implements ReserveRepository {}

Reserve _reserve() => const Reserve(
      id: 'r1',
      numero: 'R-1',
      chantierId: 'c1',
      titre: 'Fissure',
      statut: ReserveStatut.enCours,
    );

CommentaireReserve _commentaire(String id, {String message = 'Bonjour'}) =>
    CommentaireReserve(id: id, message: message);

AffectationReserve _affectation(String id) => AffectationReserve(id: id);

void main() {
  late MockGetReserveDetail getDetail;
  late MockChangerStatutReserve changerStatut;
  late MockAjouterMediaReserve ajouterMedia;
  late MockReserveRepository repository;

  setUp(() {
    getDetail = MockGetReserveDetail();
    changerStatut = MockChangerStatutReserve();
    ajouterMedia = MockAjouterMediaReserve();
    repository = MockReserveRepository();
  });

  ReserveDetailCubit build() => ReserveDetailCubit(
        getReserveDetail: getDetail,
        changerStatutReserve: changerStatut,
        ajouterMediaReserve: ajouterMedia,
        repository: repository,
        reserveId: 'r1',
      );

  group('chargerCollaboration', () {
    test('charge commentaires et affectations', () async {
      when(() => repository.getCommentaires(any()))
          .thenAnswer((_) async => Right([_commentaire('c1')]));
      when(() => repository.getAffectations(any()))
          .thenAnswer((_) async => Right([_affectation('a1')]));

      final cubit = build();
      await cubit.chargerCollaboration();

      expect(cubit.state.commentaires.length, 1);
      expect(cubit.state.affectations.length, 1);
      expect(cubit.state.commentairesCharges, isTrue);
      expect(cubit.state.affectationsChargees, isTrue);
    });

    test('un échec marque quand même les sections comme chargées', () async {
      when(() => repository.getCommentaires(any()))
          .thenAnswer((_) async => const Left(NetworkFailure()));
      when(() => repository.getAffectations(any()))
          .thenAnswer((_) async => const Left(NetworkFailure()));

      final cubit = build();
      await cubit.chargerCollaboration();

      // Sans ce drapeau, la section resterait sur un tourniquet perpétuel
      // alors que la fiche, elle, est parfaitement lisible.
      expect(cubit.state.commentairesCharges, isTrue);
      expect(cubit.state.affectationsChargees, isTrue);
      expect(cubit.state.commentaires, isEmpty);
    });
  });

  group('ajouterCommentaire', () {
    test('succès : le message est ajouté EN FIN de liste', () async {
      when(() => repository.ajouterCommentaire(
            reserveId: any(named: 'reserveId'),
            message: any(named: 'message'),
          )).thenAnswer((_) async => Right(_commentaire('c2', message: 'Nouveau')));

      final cubit = build();
      cubit.emit(cubit.state.copyWith(commentaires: [_commentaire('c1')]));

      final ok = await cubit.ajouterCommentaire('Nouveau');

      expect(ok, isTrue);
      // Le back renvoie les commentaires par `createdAt ASC` : le plus récent
      // est en bas, l'ordre local doit suivre.
      expect(cubit.state.commentaires.map((c) => c.id).toList(), ['c1', 'c2']);
    });

    test('échec : la liste reste inchangée et le message est posé', () async {
      when(() => repository.ajouterCommentaire(
            reserveId: any(named: 'reserveId'),
            message: any(named: 'message'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Trop long')));

      final cubit = build();
      cubit.emit(cubit.state.copyWith(commentaires: [_commentaire('c1')]));

      final ok = await cubit.ajouterCommentaire('x');

      expect(ok, isFalse);
      expect(cubit.state.commentaires.map((c) => c.id).toList(), ['c1']);
      expect(cubit.state.erreur, 'Trop long');
    });

    test('un second envoi est ignoré tant que le premier est en vol', () async {
      when(() => repository.ajouterCommentaire(
            reserveId: any(named: 'reserveId'),
            message: any(named: 'message'),
          )).thenAnswer((_) async => Right(_commentaire('c2')));

      final cubit = build();
      final premier = cubit.ajouterCommentaire('a');
      await cubit.ajouterCommentaire('b');
      await premier;

      // Sans ce verrou, un double appui poste deux fois le même message.
      verify(() => repository.ajouterCommentaire(
            reserveId: any(named: 'reserveId'),
            message: any(named: 'message'),
          )).called(1);
    });
  });

  group('affectations', () {
    test('affecter ajoute en tête de liste', () async {
      when(() => repository.affecter(
            reserveId: any(named: 'reserveId'),
            utilisateurId: any(named: 'utilisateurId'),
            entrepriseId: any(named: 'entrepriseId'),
          )).thenAnswer((_) async => Right(_affectation('a2')));

      final cubit = build();
      cubit.emit(cubit.state.copyWith(affectations: [_affectation('a1')]));

      final ok = await cubit.affecter(utilisateurId: 'u1');

      expect(ok, isTrue);
      expect(cubit.state.affectations.map((a) => a.id).toList(), ['a2', 'a1']);
    });

    test('retirer enlève la bonne affectation', () async {
      when(() => repository.retirerAffectation(
            reserveId: any(named: 'reserveId'),
            affectationId: any(named: 'affectationId'),
          )).thenAnswer((_) async => const Right(null));

      final cubit = build();
      cubit.emit(cubit.state.copyWith(
        affectations: [_affectation('a1'), _affectation('a2')],
      ));

      final ok = await cubit.retirerAffectation('a1');

      expect(ok, isTrue);
      expect(cubit.state.affectations.map((a) => a.id).toList(), ['a2']);
    });
  });

  group('modifier / supprimer', () {
    test('modifier remplace la réserve affichée', () async {
      when(() => repository.modifierReserve(
            id: any(named: 'id'),
            titre: any(named: 'titre'),
            description: any(named: 'description'),
            severite: any(named: 'severite'),
            categorie: any(named: 'categorie'),
            dateLimite: any(named: 'dateLimite'),
          )).thenAnswer((_) async => Right(_reserve()));

      final cubit = build();
      final ok = await cubit.modifier(titre: 'Corrigé');

      expect(ok, isTrue);
      expect(cubit.state.reserve, isNotNull);
      expect(cubit.state.status, ReserveDetailStatus.succes);
    });

    test('supprimer lève le drapeau que l\'écran attend pour se refermer', () async {
      when(() => repository.supprimerReserve(any())).thenAnswer((_) async => const Right(null));

      final cubit = build();
      final ok = await cubit.supprimer();

      expect(ok, isTrue);
      expect(cubit.state.supprimee, isTrue);
    });

    test('suppression refusée : pas de fermeture, message posé', () async {
      when(() => repository.supprimerReserve(any()))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Droits insuffisants')));

      final cubit = build();
      final ok = await cubit.supprimer();

      expect(ok, isFalse);
      // Refermer l'écran sur un échec ferait croire à une suppression réussie.
      expect(cubit.state.supprimee, isFalse);
      expect(cubit.state.erreur, 'Droits insuffisants');
    });
  });
}
