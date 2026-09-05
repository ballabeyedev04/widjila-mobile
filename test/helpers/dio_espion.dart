import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Adaptateur HTTP qui n'atteint jamais le réseau : il ENREGISTRE ce que le
/// mobile a réellement envoyé, et rend la réponse qu'on lui a préparée.
///
/// ## Pourquoi les tests de datasource passent par là
///
/// Un datasource fait deux choses, et ce sont exactement les deux que rien
/// d'autre ne vérifie :
///
///  1. il compose une requête — un verbe, un chemin, des paramètres, un
///     corps. Une faute ici ne se voit ni à l'analyse, ni à la compilation :
///     Dart accepte n'importe quelle chaîne comme chemin. Elle se voit en
///     production, sous forme de 404 sur un écran qui reste vide.
///
///  2. il relit une réponse JSON. Une clé mal orthographiée traverse le
///     `as String?` sans bruit et ressort en `null`, donc en champ vide à
///     l'écran — un défaut silencieux, qui ressemble à une donnée absente
///     côté serveur.
///
/// L'espion rend les deux observables : [requetes] conserve ce qui est parti,
/// et les réponses sont écrites à la main, telles que le backend les forme.
class DioEspion implements HttpClientAdapter {
  /// Ce que le mobile a envoyé, dans l'ordre.
  final List<RequestOptions> requetes = [];

  /// Réponses à servir, dans l'ordre des appels. La dernière est réutilisée
  /// si les appels sont plus nombreux — le cas courant étant une réponse
  /// unique pour un test à un seul appel.
  final List<_Reponse> _reponses = [];

  /// Prépare une réponse JSON de succès.
  ///
  /// [corps] est écrit tel que le backend le forme, ENVELOPPE COMPRISE :
  /// c'est justement l'enveloppe (`{ success, data: { ... } }`) que le
  /// datasource doit savoir défaire, et l'omettre testerait un format que le
  /// serveur n'envoie jamais.
  void repond(Map<String, dynamic> corps, {int statut = 200}) {
    _reponses.add(_Reponse(jsonEncode(corps), statut));
  }

  /// Prépare une réponse d'ERREUR — un refus du serveur, avec son corps.
  ///
  /// Le corps compte autant que le code : c'est lui qui porte le `code` et le
  /// `message` sur lesquels le mobile s'appuie pour distinguer un refus
  /// d'abonnement d'une panne.
  void repondErreur(int statut, {Map<String, dynamic>? corps}) {
    _reponses.add(_Reponse(jsonEncode(corps ?? const {}), statut));
  }

  /// La requête envoyée — pour un test à un seul appel.
  RequestOptions get requete {
    if (requetes.isEmpty) {
      throw StateError('aucune requête n\'a été envoyée');
    }
    return requetes.single;
  }

  /// « VERBE /chemin », la forme comparée dans les assertions.
  String get appel => '${requete.method} ${requete.path}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requetes.add(options);

    // Consommer le corps, comme le ferait un vrai adaptateur.
    //
    // Un envoi multipart tient des fichiers OUVERTS tant que son flux n'a pas
    // ete lu. Sans ce drain, le test conserve un verrou sur le fichier
    // temporaire et ne peut plus le supprimer — sous Windows, l'effacement
    // echoue franchement, et le test tombe pour une raison sans rapport avec
    // ce qu'il verifie.
    if (requestStream != null) {
      await requestStream.drain<void>();
    }

    if (_reponses.isEmpty) {
      throw StateError('aucune réponse préparée pour ${options.method} ${options.path}');
    }
    final reponse = _reponses.length > 1 ? _reponses.removeAt(0) : _reponses.first;

    return ResponseBody.fromString(
      reponse.corps,
      reponse.statut,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Reponse {
  final String corps;
  final int statut;
  const _Reponse(this.corps, this.statut);
}

/// Un `Dio` branché sur [espion], configuré comme celui de l'application.
///
/// `validateStatus` réplique le réglage réel : au-delà de 400, Dio lève une
/// `DioException`, ce que les datasources traduisent en exception métier.
Dio dioDeTest(DioEspion espion) {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api.test/api/v1',
    validateStatus: (statut) => statut != null && statut < 400,
  ));
  dio.httpClientAdapter = espion;
  return dio;
}
