import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/routes/app_router.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/repositories/chantier_repository.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/get_chantiers.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/demandes_chantier_cubit.dart';

class _MockGetChantiers extends Mock implements GetChantiers {}

Chantier _chantier({
  String id = 'c1',
  ChantierStatut statut = ChantierStatut.enAttenteValidation,
  String? motifRejet,
}) =>
    Chantier(id: id, nom: 'Résidence', statut: statut, motifRejet: motifRejet);

void main() {
  group('chemins des écrans de demande', () {
    // `/chantiers/:id` est déclaré plus haut dans le routeur, à l'intérieur de
    // la coquille, et go_router résout dans l'ORDRE DE DÉCLARATION. Un chemin
    // sous `/chantiers/` y serait donc capturé comme un identifiant de
    // chantier : ouvrir « Envoi Plan » chargeait la fiche du chantier
    // « envoi-plan », et le serveur répondait 500 sur cet UUID impossible.
    //
    // Les remonter dans le fichier corrigerait le symptôme, mais la justesse
    // dépendrait alors de la position relative de deux blocs éloignés.
    test('vivent hors de l’espace /chantiers/', () {
      expect(AppRoutes.demandesChantier.startsWith('/chantiers/'), isFalse);
      expect(AppRoutes.depotPlans.startsWith('/chantiers/'), isFalse);
    });

    test('ne se recouvrent pas entre eux', () {
      expect(AppRoutes.demandesChantier, isNot(AppRoutes.depotPlans));
    });
  });

  group('ChantierStatutX.fromString', () {
    test('reconnaît les deux statuts du circuit', () {
      // Sans eux, le défaut de `fromString` afficherait « En préparation » et
      // le demandeur croirait sa demande acceptée. Un défaut silencieux est
      // ici pire qu'une absence.
      expect(ChantierStatutX.fromString('en_attente_validation'),
          ChantierStatut.enAttenteValidation);
      expect(ChantierStatutX.fromString('rejete'), ChantierStatut.rejete);
    });

    test('fait l’aller-retour sur tous les statuts', () {
      for (final statut in ChantierStatut.values) {
        expect(ChantierStatutX.fromString(statut.raw), statut);
      }
    });

    test('ne classe en demande que les deux statuts du circuit', () {
      expect(ChantierStatut.enAttenteValidation.estUneDemande, isTrue);
      expect(ChantierStatut.rejete.estUneDemande, isTrue);
      for (final statut in [
        ChantierStatut.enPreparation,
        ChantierStatut.enCours,
        ChantierStatut.enPause,
        ChantierStatut.archive,
        ChantierStatut.cloture,
      ]) {
        expect(statut.estUneDemande, isFalse, reason: statut.raw);
      }
    });
  });

  group('Chantier.fromJson', () {
    test('lit le motif du refus', () {
      final c = Chantier.fromJson({
        'id': 'c1',
        'nom': 'Résidence',
        'statut': 'rejete',
        'motif_rejet': 'Adresse incomplète.',
      });

      expect(c.statut, ChantierStatut.rejete);
      expect(c.motifRejet, 'Adresse incomplète.');
    });

    test('survit à l’absence de motif', () {
      final c = Chantier.fromJson({'id': 'c1', 'nom': 'Résidence', 'statut': 'en_cours'});
      expect(c.motifRejet, isNull);
    });
  });

  group('DemandesChantierCubit', () {
    late _MockGetChantiers getChantiers;
    late DemandesChantierCubit cubit;

    setUp(() {
      getChantiers = _MockGetChantiers();
      cubit = DemandesChantierCubit(getChantiers: getChantiers);
    });

    tearDown(() => cubit.close());

    test('demande explicitement la vue « mes demandes »', () async {
      // Le serveur écarte les demandes de la liste par défaut : sans ce
      // paramètre, l'écran n'afficherait jamais rien.
      when(() => getChantiers(
            limit: any(named: 'limit'),
            demandes: any(named: 'demandes'),
          )).thenAnswer((_) async => Right(ChantierPage(items: [_chantier()], total: 1)));

      await cubit.charger();

      verify(() => getChantiers(limit: any(named: 'limit'), demandes: VueDemandes.miennes))
          .called(1);
      expect(cubit.state.status, DemandesStatus.succes);
      expect(cubit.state.items, hasLength(1));
    });

    test('vide la liste en changeant de vue', () async {
      // Les deux vues n'ont pas le même contenu : garder l'ancienne le temps
      // de l'appel ferait croire à un onglet mal branché.
      when(() => getChantiers(
            limit: any(named: 'limit'),
            demandes: any(named: 'demandes'),
          )).thenAnswer((_) async => Right(ChantierPage(items: [_chantier()], total: 1)));
      await cubit.charger();

      final vues = <List<Chantier>>[];
      cubit.stream.listen((e) => vues.add(e.items));

      await cubit.changerVue(VueDemandes.aValider);

      expect(cubit.state.vue, VueDemandes.aValider);
      // Un état intermédiaire au moins a présenté une liste vide.
      expect(vues.any((items) => items.isEmpty), isTrue);
    });

    test('signale l’erreur au lieu d’afficher une liste vide', () async {
      // Une panne réseau affichée « aucune demande » ferait croire au
      // demandeur que la sienne a disparu.
      when(() => getChantiers(
            limit: any(named: 'limit'),
            demandes: any(named: 'demandes'),
          )).thenAnswer((_) async => const Left(NetworkFailure()));

      await cubit.charger();

      expect(cubit.state.status, DemandesStatus.erreur);
      expect(cubit.state.erreur, isNotNull);
      expect(cubit.state.items, isEmpty);
    });
  });
}
