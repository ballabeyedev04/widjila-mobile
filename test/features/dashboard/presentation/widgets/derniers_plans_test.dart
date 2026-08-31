import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/dashboard/presentation/widgets/derniers_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';

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
}
