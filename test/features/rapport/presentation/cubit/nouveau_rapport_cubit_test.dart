import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/configuration_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/etat_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/modele_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/option_filtre.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/suivi_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/repositories/rapport_repository.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/usecases/rapport_usecases.dart';
import 'package:suivie_chantier_mobile/features/rapport/presentation/cubit/nouveau_rapport_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';

class _MockRepository extends Mock implements RapportRepository {}

class _MockStructure extends Mock implements GetChantierStructure {}

/// L'assistant « + Nouveau rapport » — le parcours du § 3 du cahier des
/// charges, étape par étape, et les règles qui le gardent :
///
///   - un modèle ciblé EXIGE son filtre (§ 5) ;
///   - « Tous » se lit comme une liste vide (§ 4) ;
///   - rien n'est écrit sur le serveur avant l'aperçu, puis une seule fois ;
///   - un seul appui compte pour générer (§ 11).
void main() {
  late _MockRepository repository;
  late _MockStructure getStructure;

  const structure = ChantierStructure(batiments: [
    BatimentStructure(id: 'bA', nom: 'A', etages: [
      EtageStructure(id: 'eA1', nom: 'R+1', zones: [ZoneStructure(id: 'zA11', nom: 'A101')]),
      EtageStructure(id: 'eA2', nom: 'R+2'),
    ]),
    BatimentStructure(id: 'bB', nom: 'B', etages: [EtageStructure(id: 'eB1', nom: 'RDC')]),
  ]);

  const brouillon = Rapport(id: 'r1', chantierId: 'c1', fichierUrl: '', etat: EtatRapport.brouillon);
  const genere = Rapport(id: 'r1', chantierId: 'c1', fichierUrl: '/uploads/rapports/r1.pdf');

  NouveauRapportCubit construire({String? chantierId = 'c1', Rapport? existant}) => NouveauRapportCubit(
        getStructure: getStructure,
        getOptions: GetOptionsFiltresRapport(repository),
        getProjets: GetProjetsRapport(repository),
        creerRapport: CreerRapport(repository),
        modifierRapport: ModifierRapport(repository),
        calculerResume: CalculerResumeRapport(repository),
        genererRapport: GenererRapportConfigure(repository),
        chantierId: chantierId,
        chantierNom: 'Résidence',
        existant: existant,
      );

  setUpAll(() => registerFallbackValue(const ConfigurationRapport(chantierId: 'c', modele: ModeleRapport.global)));

  setUp(() {
    repository = _MockRepository();
    getStructure = _MockStructure();
    when(() => getStructure(any())).thenAnswer((_) async => const Right(structure));
    when(() => repository.getOptionsFiltres(any())).thenAnswer((_) async => const Right(OptionsFiltresRapport(
          entreprises: [OptionFiltre(id: 'p1', nom: 'ABC')],
          corpsEtat: [OptionFiltre(id: 'ce1', nom: 'Carrelage')],
        )));
    when(() => repository.getProjets()).thenAnswer((_) async => const Right([
          OptionFiltre(id: 'c1', nom: 'Résidence Les Jardins', detail: 'RJ'),
          OptionFiltre(id: 'c2', nom: 'Villa'),
        ]));
    when(() => repository.creerRapport(any())).thenAnswer((_) async => const Right(brouillon));
    when(() => repository.modifierRapport(any(), any())).thenAnswer((_) async => const Right(brouillon));
    when(() => repository.resumeRapport(any())).thenAnswer((_) async => const Right(ResumeRapport(
          total: 12,
          parStatut: {StatutReserveRapport.aTraiter: 5},
          entreprises: 3,
        )));
    when(() => repository.genererRapportConfigure(any())).thenAnswer((_) async => const Right(genere));
  });

  /// Amène l'assistant jusqu'à l'aperçu avec le modèle donné.
  Future<NouveauRapportCubit> jusquAApercu(ModeleRapport modele, {void Function(NouveauRapportCubit)? filtrer}) async {
    final cubit = construire();
    await cubit.demarrer();
    cubit.choisirModele(modele);
    await cubit.suivant(); // → filtres
    filtrer?.call(cubit);
    await cubit.suivant(); // → sections
    await cubit.suivant(); // → aperçu
    return cubit;
  }

  group('§ 3 — le parcours', () {
    test('depuis un chantier : pas d’étape « projet », listes chargées', () async {
      final cubit = construire();
      await cubit.demarrer();

      expect(cubit.state.etapes, [EtapeRapport.modele, EtapeRapport.filtres, EtapeRapport.sections, EtapeRapport.apercu]);
      expect(cubit.state.etape, EtapeRapport.modele);
      expect(cubit.state.optionsStatut, ChargementWizard.pret);
      expect(cubit.state.entreprises.single.nom, 'ABC');
      expect(cubit.state.structure?.batiments, hasLength(2));
      await cubit.close();
    });

    test('hors chantier : on choisit d’abord le projet', () async {
      final cubit = construire(chantierId: null);
      await cubit.demarrer();

      expect(cubit.state.etape, EtapeRapport.projet);
      expect(cubit.state.projets, hasLength(2));

      await cubit.choisirProjet(const OptionFiltre(id: 'c2', nom: 'Villa'));

      expect(cubit.state.chantierId, 'c2');
      expect(cubit.state.chantierNom, 'Villa');
      expect(cubit.state.etape, EtapeRapport.modele);
      verify(() => repository.getOptionsFiltres('c2')).called(1);
      await cubit.close();
    });

    test('« Suivant » ne quitte pas l’étape du modèle sans modèle choisi', () async {
      final cubit = construire();
      await cubit.demarrer();
      await cubit.suivant();
      expect(cubit.state.etape, EtapeRapport.modele);
      await cubit.close();
    });

    test('« Précédent » revient d’une étape', () async {
      final cubit = construire();
      await cubit.demarrer();
      cubit.choisirModele(ModeleRapport.global);
      await cubit.suivant();
      cubit.precedent();
      expect(cubit.state.etape, EtapeRapport.modele);
      await cubit.close();
    });
  });

  group('§ 5 — les modèles', () {
    test('« à traiter » pose son périmètre, « levées » allume l’historique', () async {
      final cubit = construire();
      cubit.choisirModele(ModeleRapport.aTraiter);
      expect(cubit.state.filtres.statuts,
          [StatutReserveRapport.aTraiter, StatutReserveRapport.enCours, StatutReserveRapport.aControler]);

      cubit.choisirModele(ModeleRapport.levees);
      expect(cubit.state.filtres.statuts, [StatutReserveRapport.levee, StatutReserveRapport.cloturee]);
      expect(cubit.state.sections.history, isTrue);
      await cubit.close();
    });

    test('un « rapport par bâtiment » sans bâtiment ne passe pas l’étape des filtres', () async {
      final cubit = construire();
      await cubit.demarrer();
      cubit.choisirModele(ModeleRapport.batiment);
      await cubit.suivant(); // → filtres

      await cubit.suivant();
      expect(cubit.state.etape, EtapeRapport.filtres);
      expect(cubit.state.manquants, [FiltreRequis.batiment]);

      // Dès que le bâtiment est choisi, l'avertissement disparaît.
      cubit.basculerBatiment('bA');
      expect(cubit.state.manquants, isEmpty);
      await cubit.suivant();
      expect(cubit.state.etape, EtapeRapport.sections);
      await cubit.close();
    });
  });

  group('§ 4 — les filtres', () {
    test('les niveaux proposés suivent les bâtiments choisis', () async {
      final cubit = construire();
      await cubit.demarrer();

      expect(cubit.state.etagesProposes.map((p) => p.etage.id), ['eA1', 'eA2', 'eB1']);
      cubit.basculerBatiment('bB');
      expect(cubit.state.etagesProposes.map((p) => p.etage.id), ['eB1']);
      await cubit.close();
    });

    test('retirer un bâtiment retire ses niveaux et ses zones — aucun filtre invisible', () async {
      final cubit = construire();
      await cubit.demarrer();
      cubit
        ..basculerBatiment('bA')
        ..basculerEtage('eA1')
        ..basculerZone('zA11');
      expect(cubit.state.filtres.zones, ['zA11']);

      cubit.basculerBatiment('bA');

      expect(cubit.state.filtres.batiments, isEmpty);
      expect(cubit.state.filtres.etages, isEmpty);
      expect(cubit.state.filtres.zones, isEmpty);
      await cubit.close();
    });

    test('une sélection se défait d’un second appui — revenir à « Tous »', () async {
      final cubit = construire();
      cubit
        ..basculerEntreprise('p1')
        ..basculerGravite(GraviteRapport.critique);
      expect(cubit.state.filtres.entreprises, ['p1']);

      cubit
        ..basculerEntreprise('p1')
        ..basculerGravite(GraviteRapport.critique);
      expect(cubit.state.filtres.estVide, isTrue);
      await cubit.close();
    });

    test('la période se pose et s’efface', () async {
      final cubit = construire();
      cubit.definirPeriode(debut: DateTime(2026, 9, 1));
      cubit.definirPeriode(fin: DateTime(2026, 9, 30));
      expect(cubit.state.filtres.dateDebut, DateTime(2026, 9, 1));
      expect(cubit.state.filtres.dateFin, DateTime(2026, 9, 30));

      cubit.effacerPeriode();
      expect(cubit.state.filtres.dateDebut, isNull);
      expect(cubit.state.filtres.dateFin, isNull);
      await cubit.close();
    });
  });

  group('§ 10 — sections et format', () {
    test('sans aucun format, on ne passe pas à l’aperçu', () async {
      final cubit = construire();
      await cubit.demarrer();
      cubit.choisirModele(ModeleRapport.global);
      await cubit.suivant();
      await cubit.suivant(); // → sections
      cubit.basculerFormat(FormatRapport.pdf); // retire le seul format

      await cubit.suivant();

      expect(cubit.state.etape, EtapeRapport.sections);
      expect(cubit.state.formatManquant, isTrue);
      verifyNever(() => repository.creerRapport(any()));
      await cubit.close();
    });
  });

  group('§ 20 — aperçu', () {
    test('le brouillon n’est créé qu’à l’aperçu, avec la configuration choisie', () async {
      final cubit = await jusquAApercu(ModeleRapport.batiment, filtrer: (c) {
        c.basculerBatiment('bA');
        c.basculerStatut(StatutReserveRapport.levee);
      });

      final config = verify(() => repository.creerRapport(captureAny())).captured.single as ConfigurationRapport;
      expect(config.chantierId, 'c1');
      expect(config.modele, ModeleRapport.batiment);
      expect(config.filtres.batiments, ['bA']);
      expect(config.filtres.statuts, [StatutReserveRapport.levee]);

      expect(cubit.state.etape, EtapeRapport.apercu);
      expect(cubit.state.rapportId, 'r1');
      expect(cubit.state.resume?.total, 12);
      await cubit.close();
    });

    test('recalculer sans rien changer ne réécrit pas le brouillon', () async {
      final cubit = await jusquAApercu(ModeleRapport.global);
      await cubit.actualiserResume();

      verify(() => repository.creerRapport(any())).called(1);
      verifyNever(() => repository.modifierRapport(any(), any()));
      await cubit.close();
    });

    test('revenir modifier un filtre MODIFIE le brouillon, sans en créer un second', () async {
      final cubit = await jusquAApercu(ModeleRapport.global);
      cubit.precedent();
      cubit.precedent(); // → filtres
      cubit.basculerGravite(GraviteRapport.majeure);
      await cubit.suivant();
      await cubit.suivant(); // → aperçu

      verify(() => repository.creerRapport(any())).called(1);
      verify(() => repository.modifierRapport('r1', any())).called(1);
      await cubit.close();
    });

    test('la prévisualisation passe par la route du § 9', () async {
      final cubit = await jusquAApercu(ModeleRapport.global);
      expect(await cubit.cheminPrevisualisation(), '/reports/r1/preview');
      await cubit.close();
    });

    test('un refus du serveur à l’enregistrement est dit, sans générer', () async {
      when(() => repository.creerRapport(any()))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Modèle inconnu')));
      final cubit = await jusquAApercu(ModeleRapport.global);

      expect(cubit.state.rapportId, isNull);
      await cubit.generer();
      verifyNever(() => repository.genererRapportConfigure(any()));
      await cubit.close();
    });
  });

  group('§ 11 — génération', () {
    test('génère et retient le rapport produit', () async {
      final cubit = await jusquAApercu(ModeleRapport.global);
      await cubit.generer();

      verify(() => repository.genererRapportConfigure('r1')).called(1);
      expect(cubit.state.rapportGenere, genere);
      await cubit.close();
    });

    test('un seul appui compte — deux appuis produiraient deux versions', () async {
      final attente = Completer<Either<Failure, Rapport>>();
      when(() => repository.genererRapportConfigure(any())).thenAnswer((_) => attente.future);
      final cubit = await jusquAApercu(ModeleRapport.global);

      final a = cubit.generer();
      final b = cubit.generer();
      attente.complete(const Right(genere));
      await Future.wait([a, b]);

      verify(() => repository.genererRapportConfigure(any())).called(1);
      await cubit.close();
    });

    test('un échec de génération est dit, sans quitter l’assistant', () async {
      when(() => repository.genererRapportConfigure(any()))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Stockage saturé')));
      final cubit = await jusquAApercu(ModeleRapport.global);

      await cubit.generer();

      expect(cubit.state.rapportGenere, isNull);
      expect(cubit.state.action, ActionWizard.aucune);
      await cubit.close();
    });
  });

  group('§ 20 — modifier un rapport existant', () {
    const existant = Rapport(
      id: 'r7',
      chantierId: 'c1',
      fichierUrl: '/uploads/rapports/r7.pdf',
      nom: 'Relance ABC',
      modele: ModeleRapport.entreprise,
      filtres: FiltresRapport(entreprises: ['p1']),
      formats: {FormatRapport.pdf, FormatRapport.xlsx},
    );

    test('reprend sa configuration, à l’étape des filtres', () {
      final cubit = construire(existant: existant);

      expect(cubit.state.etape, EtapeRapport.filtres);
      expect(cubit.state.rapportId, 'r7');
      expect(cubit.state.modele, ModeleRapport.entreprise);
      expect(cubit.state.filtres.entreprises, ['p1']);
      expect(cubit.state.formats, {FormatRapport.pdf, FormatRapport.xlsx});
      cubit.close();
    });

    test('régénérer SANS modification ne réécrit rien', () async {
      final cubit = construire(existant: existant);
      await cubit.generer();

      verifyNever(() => repository.creerRapport(any()));
      verifyNever(() => repository.modifierRapport(any(), any()));
      verify(() => repository.genererRapportConfigure('r7')).called(1);
      await cubit.close();
    });

    test('régénérer APRÈS modification enregistre d’abord la nouvelle configuration', () async {
      final cubit = construire(existant: existant);
      cubit.basculerStatut(StatutReserveRapport.aTraiter);
      await cubit.generer();

      verify(() => repository.modifierRapport('r7', any())).called(1);
      verify(() => repository.genererRapportConfigure('r1')).called(1);
      await cubit.close();
    });
  });
}
