import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/routes/app_router.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/repositories/chantier_repository.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/creer_chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/get_chantiers.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/demandes_chantier_cubit.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/envoi_plan_cubit.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/uploader_plan.dart';

class _MockGetChantiers extends Mock implements GetChantiers {}

class _MockCreerChantier extends Mock implements CreerChantier {}

class _MockUploaderPlan extends Mock implements UploaderPlan {}

Chantier _chantier({
  String id = 'c1',
  ChantierStatut statut = ChantierStatut.enAttenteValidation,
  String? motifRejet,
}) =>
    Chantier(id: id, nom: 'Résidence', statut: statut, motifRejet: motifRejet);

Plan _plan(String nom) => Plan(
      id: 'p-$nom',
      chantierId: 'c1',
      nom: nom,
      fichierUrl: 'https://exemple.test/$nom.pdf',
    );

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
      expect(AppRoutes.envoiPlan.startsWith('/chantiers/'), isFalse);
    });

    test('ne se recouvrent pas entre eux', () {
      expect(AppRoutes.demandesChantier, isNot(AppRoutes.envoiPlan));
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

  group('EnvoiPlanCubit', () {
    late _MockCreerChantier creerChantier;
    late _MockUploaderPlan uploaderPlan;
    late EnvoiPlanCubit cubit;

    setUp(() {
      creerChantier = _MockCreerChantier();
      uploaderPlan = _MockUploaderPlan();
      cubit = EnvoiPlanCubit(creerChantier: creerChantier, uploaderPlan: uploaderPlan);
    });

    tearDown(() => cubit.close());

    void creationReussit() {
      when(() => creerChantier(
            nom: any(named: 'nom'),
            adresse: any(named: 'adresse'),
            description: any(named: 'description'),
          )).thenAnswer((_) async => Right(_chantier()));
    }

    test('refuse d’ajouter deux fois le même fichier', () {
      // Le même chemin deux fois produirait deux versions du même plan côté
      // serveur, sans que rien à l'écran ne l'ait laissé prévoir.
      const plan = PlanAJoindre(chemin: '/tmp/a.pdf', nom: 'a.pdf');

      cubit.ajouter(plan);
      cubit.ajouter(plan);

      expect(cubit.state.plans, hasLength(1));
    });

    test('crée la demande AVANT de déposer les plans', () async {
      // L'ordre est imposé par le serveur : un plan appartient à un chantier,
      // il n'existe pas de plan orphelin.
      creationReussit();
      when(() => uploaderPlan(
            chantierId: any(named: 'chantierId'),
            cheminFichier: any(named: 'cheminFichier'),
            nom: any(named: 'nom'),
          )).thenAnswer((_) async => Right(_plan('a')));

      cubit.ajouter(const PlanAJoindre(chemin: '/tmp/a.pdf', nom: 'a.pdf'));
      await cubit.envoyer(nom: 'Résidence');

      verifyInOrder([
        () => creerChantier(
              nom: any(named: 'nom'),
              adresse: any(named: 'adresse'),
              description: any(named: 'description'),
            ),
        () => uploaderPlan(
              chantierId: 'c1',
              cheminFichier: '/tmp/a.pdf',
              nom: 'a.pdf',
            ),
      ]);
      expect(cubit.state.status, EnvoiPlanStatus.succes);
      expect(cubit.state.plansEnEchec, isEmpty);
    });

    test('ne dépose aucun plan si la demande échoue', () async {
      when(() => creerChantier(
            nom: any(named: 'nom'),
            adresse: any(named: 'adresse'),
            description: any(named: 'description'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'refusé')));

      cubit.ajouter(const PlanAJoindre(chemin: '/tmp/a.pdf', nom: 'a.pdf'));
      await cubit.envoyer(nom: 'Résidence');

      verifyNever(() => uploaderPlan(
            chantierId: any(named: 'chantierId'),
            cheminFichier: any(named: 'cheminFichier'),
            nom: any(named: 'nom'),
          ));
      expect(cubit.state.status, EnvoiPlanStatus.erreur);
      expect(cubit.state.erreur, 'refusé');
    });

    test('un plan en échec ne fait pas échouer la demande', () async {
      // La demande EXISTE : la présenter comme perdue pousserait le demandeur
      // à la déposer une deuxième fois. Les plans manquants se rejoignent
      // depuis la demande.
      creationReussit();
      when(() => uploaderPlan(
            chantierId: any(named: 'chantierId'),
            cheminFichier: '/tmp/lourd.pdf',
            nom: any(named: 'nom'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'trop lourd')));
      when(() => uploaderPlan(
            chantierId: any(named: 'chantierId'),
            cheminFichier: '/tmp/ok.pdf',
            nom: any(named: 'nom'),
          )).thenAnswer((_) async => Right(_plan('ok')));

      cubit
        ..ajouter(const PlanAJoindre(chemin: '/tmp/lourd.pdf', nom: 'lourd.pdf'))
        ..ajouter(const PlanAJoindre(chemin: '/tmp/ok.pdf', nom: 'ok.pdf'));
      await cubit.envoyer(nom: 'Résidence');

      expect(cubit.state.status, EnvoiPlanStatus.succes);
      expect(cubit.state.demande, isNotNull);
      // Le plan qui a échoué est NOMMÉ : « certains plans » sans dire
      // lesquels n'aiderait personne à réparer.
      expect(cubit.state.plansEnEchec, ['lourd.pdf']);
    });

    test('envoie une demande sans aucun plan', () async {
      // Le client peut décrire son chantier d'abord et joindre les plans
      // ensuite : rien n'oblige à tout avoir sous la main.
      creationReussit();

      await cubit.envoyer(nom: 'Résidence');

      expect(cubit.state.status, EnvoiPlanStatus.succes);
      verifyNever(() => uploaderPlan(
            chantierId: any(named: 'chantierId'),
            cheminFichier: any(named: 'cheminFichier'),
            nom: any(named: 'nom'),
          ));
    });
  });
}
