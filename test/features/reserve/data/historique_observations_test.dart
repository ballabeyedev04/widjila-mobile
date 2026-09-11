import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/observations_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/historique_observations.dart';

class _DistantFactice implements ObservationsRemoteDataSource {
  List<String> reponse;
  Object? erreur;
  _DistantFactice([this.reponse = const []]);

  @override
  Future<List<String>> observationsUtilisees({int limite = 100}) async {
    if (erreur != null) throw erreur!;
    return reponse;
  }
}

/// Historique des observations : serveur + copie locale, par utilisateur.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  HistoriqueObservations historique(_DistantFactice distant, {String? utilisateur = 'u-1'}) =>
      HistoriqueObservations(distant: distant, prefs: prefs, utilisateurId: utilisateur);

  test('fusionne les observations locales (d’abord) et celles du serveur, sans doublon', () async {
    final h = historique(_DistantFactice(['coins casse', 'fissure plafond']));
    await h.memoriser('Coins cassé');
    await h.memoriser('joint à reprendre');

    // « coins casse » (serveur) = « Coins cassé » (local) à la casse et à
    // l'accent près : une seule entrée, la formulation locale, plus récente.
    expect(await h.charger(), ['joint à reprendre', 'Coins cassé', 'fissure plafond']);
  });

  test('hors ligne : les observations locales restent proposées', () async {
    final distant = _DistantFactice();
    final h = historique(distant);
    await h.memoriser('coins casse');
    distant.erreur = const NetworkException();

    expect(await h.charger(), ['coins casse']);
  });

  test('une observation saisie hors ligne est proposée dès la réserve suivante', () async {
    final distant = _DistantFactice()..erreur = const NetworkException();
    final h = historique(distant);

    await h.memoriser('pas encore synchronisée');

    expect(await h.charger(), ['pas encore synchronisée']);
  });

  test('rangé par utilisateur : sur un téléphone partagé, rien ne passe de l’un à l’autre', () async {
    await historique(_DistantFactice(), utilisateur: 'u-1').memoriser('observation de u-1');

    expect(await historique(_DistantFactice(), utilisateur: 'u-2').charger(), isEmpty);
  });

  test('la fusion est conservée pour la prochaine ouverture hors ligne', () async {
    await historique(_DistantFactice(['du serveur'])).charger();

    final horsLigne = _DistantFactice()..erreur = const NetworkException();
    expect(await historique(horsLigne).charger(), ['du serveur']);
  });
}
