import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/corps_etat/domain/entities/corps_etat.dart';
import 'package:suivie_chantier_mobile/features/corps_etat/domain/usecases/get_corps_etat_actifs.dart';
import 'package:suivie_chantier_mobile/features/phase/domain/entities/phase_referentiel.dart';
import 'package:suivie_chantier_mobile/features/phase/domain/usecases/get_phases_actives.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/ajouter_media_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/changer_statut_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/creer_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_detail.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserve_detail_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserve_wizard_cubit.dart';

class MockCreerReserve extends Mock implements CreerReserve {}

class MockGetChantierStructure extends Mock implements GetChantierStructure {}

class MockGetCorpsEtatActifs extends Mock implements GetCorpsEtatActifs {}

class MockGetPhasesActives extends Mock implements GetPhasesActives {}

class MockGetReserveDetail extends Mock implements GetReserveDetail {}

class MockChangerStatutReserve extends Mock implements ChangerStatutReserve {}

class MockAjouterMediaReserve extends Mock implements AjouterMediaReserve {}

class MockReserveRepository extends Mock implements ReserveRepository {}

Reserve _reserve({ReserveStatut statut = ReserveStatut.creee}) =>
    Reserve(id: 'r1', numero: 'R-1', chantierId: 'c1', titre: 'Réserve', statut: statut);

/// Non-régression [C8] — verrous de double soumission.
///
/// La désactivation du bouton (`onPressed: enCours ? null : ...`) ne prend
/// effet qu'à la frame SUIVANTE : deux appuis dans la même frame (~16 ms), ou
/// un utilisateur qui martèle l'écran sur un téléphone lent, passaient au
/// travers. Chaque garde testée ici évite une écriture serveur en double.
void main() {
  setUpAll(() {
    registerFallbackValue(ReserveStatut.creee);
    registerFallbackValue(ReserveSeverite.moyenne);
    registerFallbackValue(ReserveCategorie.autre);
  });

  group('ReserveWizardCubit.soumettre', () {
    test('un second appui pendant l\'envoi ne crée PAS une seconde réserve', () async {
      final creerReserve = MockCreerReserve();
      final getStructure = MockGetChantierStructure();
      final enVol = Completer<Either<Failure, Reserve>>();

      when(() => creerReserve(
            chantierId: any(named: 'chantierId'),
            titre: any(named: 'titre'),
            description: any(named: 'description'),
            priorite: any(named: 'priorite'),
            categorie: any(named: 'categorie'),
            batimentId: any(named: 'batimentId'),
            etageId: any(named: 'etageId'),
            zoneId: any(named: 'zoneId'),
            lotId: any(named: 'lotId'),
            dateLimite: any(named: 'dateLimite'),
          )).thenAnswer((_) => enVol.future);

      // Le catalogue des métiers est une dépendance du wizard depuis qu'il
      // remplace l'énumération figée. Il n'est pas le sujet de ce test : on
      // rend une liste vide, ce qui laisse le verrou de double soumission
      // strictement inchangé.
      final getCorpsEtat = MockGetCorpsEtatActifs();
      when(() => getCorpsEtat()).thenAnswer((_) async => Right<Failure, List<CorpsEtat>>(const []));
      final getPhases = MockGetPhasesActives();
      when(() => getPhases()).thenAnswer((_) async => Right<Failure, List<PhaseReferentiel>>(const []));

      final cubit = ReserveWizardCubit(
        getChantierStructure: getStructure,
        creerReserve: creerReserve,
        getCorpsEtatActifs: getCorpsEtat,
        getPhasesActives: getPhases,
        chantierId: 'c1',
      );
      cubit.changerTitre('Fissure');

      final premier = cubit.soumettre();
      final second = await cubit.soumettre(); // pendant que le premier est en vol

      expect(second, isNull, reason: 'la seconde soumission doit être refusée');

      enVol.complete(Right(_reserve()));
      await premier;

      verify(() => creerReserve(
            chantierId: any(named: 'chantierId'),
            titre: any(named: 'titre'),
            description: any(named: 'description'),
            priorite: any(named: 'priorite'),
            categorie: any(named: 'categorie'),
            batimentId: any(named: 'batimentId'),
            etageId: any(named: 'etageId'),
            zoneId: any(named: 'zoneId'),
            lotId: any(named: 'lotId'),
            dateLimite: any(named: 'dateLimite'),
          )).called(1);

      await cubit.close();
    });
  });

  group('ReserveDetailCubit', () {
    late MockGetReserveDetail getDetail;
    late MockChangerStatutReserve changerStatut;
    late MockAjouterMediaReserve ajouterMedia;
    late MockReserveRepository repository;

    setUp(() {
      getDetail = MockGetReserveDetail();
      changerStatut = MockChangerStatutReserve();
      ajouterMedia = MockAjouterMediaReserve();
      repository = MockReserveRepository();
      when(() => getDetail(any())).thenAnswer((_) async => Right(_reserve()));
    });

    ReserveDetailCubit build() => ReserveDetailCubit(
          getReserveDetail: getDetail,
          changerStatutReserve: changerStatut,
          ajouterMediaReserve: ajouterMedia,
          // Collaboration (commentaires, affectations, édition) : non
          // sollicitée par ces tests, qui portent sur le verrou de double
          // soumission du changement de statut.
          repository: repository,
          reserveId: 'r1',
        );

    test('un double appui n\'envoie PAS deux changements de statut', () async {
      final enVol = Completer<Either<Failure, Reserve>>();
      when(() => changerStatut(
            reserveId: any(named: 'reserveId'),
            statut: any(named: 'statut'),
            motif: any(named: 'motif'),
          )).thenAnswer((_) => enVol.future);

      final cubit = build();
      final premier = cubit.changerStatut(ReserveStatut.enCours);
      final second = await cubit.changerStatut(ReserveStatut.enCours);

      expect(second, isFalse);

      enVol.complete(Right(_reserve(statut: ReserveStatut.enCours)));
      await premier;

      verify(() => changerStatut(
            reserveId: any(named: 'reserveId'),
            statut: any(named: 'statut'),
            motif: any(named: 'motif'),
          )).called(1);

      await cubit.close();
    });

    test('un double appui ne téléverse PAS deux fois la même photo', () async {
      final enVol = Completer<Either<Failure, ReserveMedia>>();
      when(() => ajouterMedia(
            reserveId: any(named: 'reserveId'),
            cheminFichier: any(named: 'cheminFichier'),
            type: any(named: 'type'),
          )).thenAnswer((_) => enVol.future);

      final cubit = build();
      final premier = cubit.ajouterPhoto('/tmp/photo.jpg');
      final second = await cubit.ajouterPhoto('/tmp/photo.jpg');

      expect(second, isFalse);

      enVol.complete(const Right(ReserveMedia(id: 'm1', type: 'photo', url: '/u/m1.jpg')));
      await premier;

      verify(() => ajouterMedia(
            reserveId: any(named: 'reserveId'),
            cheminFichier: any(named: 'cheminFichier'),
            type: any(named: 'type'),
          )).called(1);

      await cubit.close();
    });

    test('aucune exception si l\'écran est quitté pendant le chargement', () async {
      final enVol = Completer<Either<Failure, Reserve>>();
      when(() => getDetail(any())).thenAnswer((_) => enVol.future);

      final cubit = build();
      final chargement = cubit.charger();
      await cubit.close();
      enVol.complete(Right(_reserve()));

      await expectLater(chargement, completes);
    });
  });
}
