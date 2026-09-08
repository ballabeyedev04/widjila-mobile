import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/dashboard/presentation/widgets/derniers_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';

/// Un plan rattaché à un niveau de la structure — donc un SOUS-plan.
Plan _sousPlan(String id, DateTime? cree, {bool zone = false}) => Plan(
      id: id,
      chantierId: 'chantier-1',
      nom: id,
      fichierUrl: 'https://exemple.test/$id.pdf',
      format: PlanFormat.pdf,
      createdAt: cree,
      batiment: const PlanNiveauRef(id: 'bat-1', nom: 'Bâtiment A'),
      etage: zone ? null : const PlanNiveauRef(id: 'et-1', nom: 'R+2'),
      zone: zone ? const PlanNiveauRef(id: 'z-1', nom: 'A203') : null,
    );

/// Un plan de DÉTAIL d'un plan global : il porte un `parentId`, et AUCUN
/// rattachement de structure — puisqu'il hérite de ceux de son parent, qui
/// n'en a pas.
///
/// C'est le cas qui passait à travers le filtre : ni bâtiment, ni étage, ni
/// zone, il ressemblait trait pour trait à un plan global.
Plan _detailDeGlobal(String id, DateTime? cree) => Plan(
      id: id,
      chantierId: 'chantier-1',
      nom: id,
      fichierUrl: 'https://exemple.test/$id.pdf',
      format: PlanFormat.pdf,
      createdAt: cree,
      parentId: 'global',
    );

Plan _plan(String id, DateTime? cree) => Plan(
      id: id,
      chantierId: 'chantier-1',
      nom: id,
      fichierUrl: 'https://exemple.test/$id.pdf',
      format: PlanFormat.pdf,
      createdAt: cree,
    );

void main() {
  group('derniersPlans', () {
    test('classe du plus récent au plus ancien', () {
      final tries = derniersPlans([
        _plan('vieux', DateTime(2024, 1, 1)),
        _plan('recent', DateTime(2026, 8, 30)),
        _plan('moyen', DateTime(2025, 6, 15)),
      ]);

      expect(tries.map((p) => p.id), ['recent', 'moyen', 'vieux']);
    });

    test('renvoie huit plans au maximum', () {
      final douze = [
        for (var i = 0; i < 12; i++) _plan('p$i', DateTime(2026, 1, 1).add(Duration(days: i))),
      ];

      final tries = derniersPlans(douze);

      expect(tries, hasLength(8));
      // Les huit derniers ajoutés, pas les huit premiers de la liste reçue.
      expect(tries.first.id, 'p11');
      expect(tries.last.id, 'p4');
    });

    test('relègue en fin de liste un plan sans date', () {
      // Une date manquante est une information absente, pas une date nulle :
      // la trier comme telle ferait remonter les plans les moins renseignés.
      final tries = derniersPlans([
        _plan('sans-date', null),
        _plan('date', DateTime(2020, 1, 1)),
      ]);

      expect(tries.map((p) => p.id), ['date', 'sans-date']);
    });

    test('ne modifie pas la liste reçue', () {
      // Elle appartient à l'état du cubit : la trier sur place muterait un
      // état déjà émis, que `Equatable` considère alors comme inchangé.
      final source = [
        _plan('a', DateTime(2020, 1, 1)),
        _plan('b', DateTime(2026, 1, 1)),
      ];

      derniersPlans(source);

      expect(source.map((p) => p.id), ['a', 'b']);
    });

    test('accepte une liste vide', () {
      expect(derniersPlans(const []), isEmpty);
    });
  });

  group('seuls les plans GLOBAUX entrent dans la bande', () {
    // La bande est une porte d'ENTRÉE : on y choisit un chantier pour y
    // descendre ensuite, bâtiment par bâtiment. Elle mélangeait tous les
    // niveaux — le plan de masse y voisinait avec celui de l'appartement
    // A203, sans que rien ne dise lequel était lequel.

    test('écarte les plans de bâtiment, d’étage et de zone', () {
      final tries = derniersPlans([
        _plan('global', DateTime(2026, 1, 1)),
        _sousPlan('etage', DateTime(2026, 6, 1)),
        _sousPlan('appartement', DateTime(2026, 7, 1), zone: true),
      ]);

      // Les sous-plans sont pourtant les PLUS RÉCENTS : sans le filtre, ils
      // occupaient toute la bande et le plan global n'apparaissait pas.
      expect(tries.map((p) => p.id), ['global']);
    });

    test('rend une bande vide quand aucun plan global n’existe', () {
      // Mieux vaut une bande vide qu'une bande de sous-plans : l'état vide
      // dit qu'il n'y a rien à ouvrir, une liste trompeuse ne dit rien.
      expect(derniersPlans([_sousPlan('a', DateTime(2026, 1, 1))]), isEmpty);
    });

    test('écarte le DÉTAIL d’un plan global, qui lui ressemble pourtant', () {
      // Un plan de détail hérite des rattachements de son parent : le détail
      // d'un plan de masse n'a ni bâtiment, ni étage, ni zone. Sans le test
      // sur `parentId`, il s'affichait dans la bande à côté du plan dont il
      // dépend, sans que rien ne les distingue.
      final tries = derniersPlans([
        _plan('global', DateTime(2026, 1, 1)),
        _detailDeGlobal('detail-cuisine', DateTime(2026, 9, 1)),
      ]);

      // Le détail est pourtant le PLUS RÉCENT : sans le filtre, il passait en
      // tête de bande.
      expect(tries.map((p) => p.id), ['global']);
    });

    test('estPlanGlobal reconnaît un plan sans aucun rattachement', () {
      expect(estPlanGlobal(_plan('g', DateTime(2026, 1, 1))), isTrue);
      expect(estPlanGlobal(_sousPlan('s', DateTime(2026, 1, 1))), isFalse);
      expect(estPlanGlobal(_sousPlan('z', DateTime(2026, 1, 1), zone: true)), isFalse);
      expect(estPlanGlobal(_detailDeGlobal('d', DateTime(2026, 1, 1))), isFalse);
    });

    test('le classement et le plafond de huit s’appliquent APRÈS le filtre', () {
      final melange = <Plan>[
        for (var i = 0; i < 6; i++) _sousPlan('s$i', DateTime(2026, 8, 1)),
        for (var i = 0; i < 10; i++) _plan('g$i', DateTime(2026, 1, 1).add(Duration(days: i))),
      ];

      final tries = derniersPlans(melange);

      expect(tries, hasLength(8));
      expect(tries.every(estPlanGlobal), isTrue);
      expect(tries.first.id, 'g9');
    });
  });
}
