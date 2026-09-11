import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/modele_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/option_filtre.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/repositories/rapport_repository.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/usecases/rapport_usecases.dart';
import 'package:suivie_chantier_mobile/features/rapport/presentation/cubit/nouveau_rapport_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';

class _MockRepository extends Mock implements RapportRepository {}

class _MockStructure extends Mock implements GetChantierStructure {}

/// Une entreprise ajoutée à l'annuaire du chantier DEPUIS les filtres.
///
/// On la crée pour faire SON rapport : elle doit revenir cochée, et lever
/// l'exigence du modèle « par entreprise » — sinon l'utilisateur devait encore
/// la retrouver dans les puces et la cocher lui-même.
void main() {
  late NouveauRapportCubit cubit;

  setUp(() {
    final repo = _MockRepository();
    cubit = NouveauRapportCubit(
      getStructure: _MockStructure(),
      getOptions: GetOptionsFiltresRapport(repo),
      getProjets: GetProjetsRapport(repo),
      creerRapport: CreerRapport(repo),
      modifierRapport: ModifierRapport(repo),
      calculerResume: CalculerResumeRapport(repo),
      genererRapport: GenererRapportConfigure(repo),
      chantierId: 'c1',
    );
  });

  tearDown(() => cubit.close());

  const nanei = OptionFiltre(id: 'p9', nom: 'Groupe Nanei');

  test('l’entreprise ajoutée rejoint la liste ET se trouve cochée', () {
    cubit.choisirModele(ModeleRapport.entreprise);

    cubit.ajouterEntreprise(nanei);

    expect(cubit.state.entreprises, [nanei]);
    expect(cubit.state.filtres.entreprises, ['p9']);
    // L'exigence du modèle « par entreprise » est satisfaite.
    expect(cubit.state.filtres.manquantsPour(ModeleRapport.entreprise), isEmpty);
  });

  test('signalée deux fois : ni doublon dans la liste, ni décochée', () {
    cubit.choisirModele(ModeleRapport.entreprise);

    cubit.ajouterEntreprise(nanei);
    cubit.ajouterEntreprise(nanei);

    expect(cubit.state.entreprises, [nanei]);
    expect(cubit.state.filtres.entreprises, ['p9']);
  });
}
