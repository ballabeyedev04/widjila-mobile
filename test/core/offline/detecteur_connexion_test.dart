import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';

class _MockConnectivity extends Mock implements Connectivity {}

/// Serveur de santé qui répond après [delai], et compte les sondes reçues.
class _Sante implements HttpClientAdapter {
  _Sante(this.delai);
  final Duration delai;
  int sondes = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sondes++;
    await Future<void>.delayed(delai);
    return ResponseBody.fromString('{"status":"ok"}', 200);
  }

  @override
  void close({bool force = false}) {}
}

/// Deuxième audit — A2-14 : la sonde de joignabilité.
///
/// Signalé par l'audit de performance (session parallèle) puis reproduit ici :
/// des vérifications qui se chevauchent (sondage périodique + changement
/// d'interface + retour au premier plan) lançaient chacune leur propre
/// requête. Sur un signal faible, leurs réponses arrivaient dans le désordre
/// et faisaient basculer l'état en ligne / hors ligne — chaque bascule vers
/// « en ligne » déclenchant une passe de synchronisation.
void main() {
  late _MockConnectivity connectivite;

  setUp(() {
    connectivite = _MockConnectivity();
    when(() => connectivite.checkConnectivity()).thenAnswer((_) async => [ConnectivityResult.mobile]);
  });

  test('des vérifications simultanées partagent UNE seule sonde', () async {
    final sante = _Sante(const Duration(milliseconds: 80));
    final dio = Dio()..httpClientAdapter = sante;
    final detecteur = DetecteurConnexion(dio: dio, connectivity: connectivite);

    final resultats = await Future.wait([detecteur.verifier(), detecteur.verifier(), detecteur.verifier()]);

    expect(sante.sondes, 1, reason: 'trois déclencheurs rapprochés, une seule requête');
    expect(resultats, everyElement(EtatReseau.enLigne));
  });

  test('une nouvelle vérification APRÈS la fin de la précédente sonde de nouveau', () async {
    final sante = _Sante(const Duration(milliseconds: 5));
    final dio = Dio()..httpClientAdapter = sante;
    final detecteur = DetecteurConnexion(dio: dio, connectivity: connectivite);

    await detecteur.verifier();
    await detecteur.verifier();

    expect(sante.sondes, 2);
  });
}
