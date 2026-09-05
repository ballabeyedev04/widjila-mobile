import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Tableau de bord.
///
/// ## Une seule route, mais la plus lue de l'application
///
/// C'est l'écran d'accueil : cette requête part à chaque ouverture. Elle ne
/// renvoie que des AGRÉGATS — jamais la liste des réserves elles-mêmes — et
/// ses répartitions arrivent sous forme d'objets dont les clés sont les
/// valeurs serveur (`en_cours`, `critique`). Une clé non reconnue ne provoque
/// rien : le compteur correspondant vaut simplement zéro, et le graphique
/// perd une part sans que personne ne s'en aperçoive.
void main() {
  late DioEspion espion;
  late DashboardRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = DashboardRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  test('appelle la route d’accueil et relit les compteurs', () async {
    espion.repond({
      'success': true,
      'data': {
        'stats': {
          'chantiers': 4,
          'plans': 12,
          'inspections': 3,
          'documents': 27,
          'utilisateurs': 5,
          'reserves': {'total': 40, 'ouvertes': 18},
          'parStatut': {'en_cours': 10, 'validee': 22},
          'parSeverite': {'critique': 4, 'moyenne': 30},
          'parChantier': <dynamic>[],
        },
      },
    });

    final stats = await source.getStatsGlobales();

    expect(espion.appel, 'GET /dashboard');
    expect(stats.chantiers, 4);
    expect(stats.plans, 12);
    expect(stats.documents, 27);
  });

  test('les répartitions sont indexées par les valeurs SERVEUR', () async {
    // `en_cours`, pas `enCours`. Une clé non reconnue ne lève rien : le
    // compteur vaut zéro et la part disparaît du graphique.
    espion.repond({
      'success': true,
      'data': {
        'stats': {
          'chantiers': 1,
          'parStatut': {'en_cours': 10, 'validee': 22},
          'parSeverite': {'critique': 4},
        },
      },
    });

    final stats = await source.getStatsGlobales();

    expect(stats.parStatut[ReserveStatut.enCours], 10);
    expect(stats.parStatut[ReserveStatut.validee], 22);
    expect(stats.parSeverite[ReserveSeverite.critique], 4);
  });

  test('un compte NEUF renvoie des zéros, pas une erreur', () async {
    // C'est ce que voit un utilisateur qui vient de s'inscrire. L'écran doit
    // savoir le lire pour proposer sa page d'accueil guidée plutôt qu'une
    // grille de zéros.
    espion.repond({
      'success': true,
      'data': {'stats': <String, dynamic>{}},
    });

    final stats = await source.getStatsGlobales();

    expect(stats.chantiers, 0);
    expect(stats.parChantier, isEmpty);
    expect(stats.parStatut, isEmpty);
  });
}
