import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/membre_chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/creer_structure.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/structure_chantier_cubit.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/structure_chantier_state.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/code_niveau.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';

class _MockStructure extends Mock implements GetChantierStructure {}

class _MockCreerBatiment extends Mock implements CreerBatiment {}

class _MockModifierBatiment extends Mock implements ModifierBatiment {}

class _MockSupprimerBatiment extends Mock implements SupprimerBatiment {}

class _MockCreerEtage extends Mock implements CreerEtage {}

class _MockModifierEtage extends Mock implements ModifierEtage {}

class _MockSupprimerEtage extends Mock implements SupprimerEtage {}

class _MockCreerZone extends Mock implements CreerZone {}

class _MockModifierZone extends Mock implements ModifierZone {}

class _MockSupprimerZone extends Mock implements SupprimerZone {}

/// La section « Structure » de la fiche chantier — annoncée « Prochainement »
/// jusqu'ici.
void main() {
  late _MockStructure getStructure;
  late _MockCreerBatiment creerBatiment;
  late _MockSupprimerBatiment supprimerBatiment;

  StructureChantierCubit construire() => StructureChantierCubit(
        chantierId: 'c1',
        getStructure: getStructure,
        creerBatimentUsecase: creerBatiment,
        modifierBatimentUsecase: _MockModifierBatiment(),
        supprimerBatimentUsecase: supprimerBatiment,
        creerEtageUsecase: _MockCreerEtage(),
        modifierEtageUsecase: _MockModifierEtage(),
        supprimerEtageUsecase: _MockSupprimerEtage(),
        creerZoneUsecase: _MockCreerZone(),
        modifierZoneUsecase: _MockModifierZone(),
        supprimerZoneUsecase: _MockSupprimerZone(),
      );

  const batiment = BatimentStructure(
    id: 'b1',
    nom: 'Bâtiment A',
    etages: [
      EtageStructure(id: 'e0', nom: 'RDC', niveau: 0),
      EtageStructure(id: 'e1', nom: 'R+1', niveau: 1),
      EtageStructure(id: 's1', nom: 'SS1', niveau: -1, typeNiveau: TypeNiveau.sousSol),
    ],
  );

  setUp(() {
    getStructure = _MockStructure();
    creerBatiment = _MockCreerBatiment();
    supprimerBatiment = _MockSupprimerBatiment();
    when(() => getStructure('c1')).thenAnswer(
      (_) async => const Right<Failure, ChantierStructure>(ChantierStructure(batiments: [batiment])),
    );
  });

  test('charger() publie la structure du chantier', () async {
    final cubit = construire();
    await cubit.charger();

    expect(cubit.state.status, StructureStatus.succes);
    expect(cubit.state.structure!.batiments.single.etages, hasLength(3));
  });

  test('la cote d’un nouveau niveau se déduit des niveaux existants', () async {
    final cubit = construire();
    await cubit.charger();

    expect(cubit.coteSuivante('b1', TypeNiveau.etage), 2);
    expect(cubit.coteSuivante('b1', TypeNiveau.sousSol), -2);
    expect(cubit.coteSuivante('b1', TypeNiveau.toiture), 2);
  });

  test('bâtiment vide : rez-de-chaussée à 0, premier sous-sol à -1', () {
    final cubit = construire();

    expect(cubit.coteSuivante('inconnu', TypeNiveau.etage), 0);
    expect(cubit.coteSuivante('inconnu', TypeNiveau.sousSol), -1);
    expect(cubit.coteSuivante('inconnu', TypeNiveau.toiture), 1);
  });

  test('une modification réussie recharge la structure', () async {
    when(() => creerBatiment('c1', nom: 'Bâtiment B')).thenAnswer(
      (_) async => const Right<Failure, BatimentStructure>(BatimentStructure(id: 'b2', nom: 'Bâtiment B')),
    );
    final cubit = construire();
    await cubit.charger();

    final erreur = await cubit.ajouterBatiment('Bâtiment B');

    expect(erreur, isNull);
    verify(() => getStructure('c1')).called(2);
    expect(cubit.state.actionEnCours, isFalse);
  });

  test('un refus du serveur remonte tel quel, sans rechargement', () async {
    when(() => supprimerBatiment('c1', 'b1')).thenAnswer(
      (_) async => const Left<Failure, void>(ServerFailure(errorMessage: '3 réserves y sont rattachées')),
    );
    final cubit = construire();
    await cubit.charger();

    final erreur = await cubit.retirerBatiment('b1');

    expect(erreur, '3 réserves y sont rattachées');
    verify(() => getStructure('c1')).called(1);
    expect(cubit.state.structure!.batiments, hasLength(1));
  });

  group('MembreChantier.fromJson', () {
    test('lit le rôle sur le chantier dans la table de liaison', () {
      final membre = MembreChantier.fromJson(const {
        'id': 'u1',
        'nom': 'Diop',
        'prenom': 'Awa',
        'role': 'ChefProjet',
        'ChantierMembre': {'roleChantier': 'Responsable lot 2'},
      });

      expect(membre.roleChantier, 'Responsable lot 2');
      expect(membre.role, UserRole.chefProjet);
      expect(membre.initiales, 'AD');
      expect(membre.email, isNull);
    });

    test('un rôle vide vaut « aucun rôle »', () {
      final membre = MembreChantier.fromJson(const {
        'id': 'u2',
        'nom': 'Ba',
        'prenom': 'Moussa',
        'role': 'Pilote',
        'ChantierMembre': {'roleChantier': '  '},
      });

      expect(membre.roleChantier, isNull);
    });
  });
}
