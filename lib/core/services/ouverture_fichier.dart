import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart' as plugin;
import 'package:path_provider/path_provider.dart';

import '../errors/exception_to_failure.dart';
import '../errors/failure.dart';
import '../network/dio_exception_mapper.dart';

/// Résultat de l'ouverture d'un fichier.
enum ResultatOuverture {
  ouvert,

  /// Fichier téléchargé, mais aucune application de l'appareil ne sait le
  /// lire (un DWG sur un téléphone nu, typiquement). L'échec vient du système,
  /// pas du réseau — le message doit le dire.
  aucuneApplication,
}

/// Téléchargement puis ouverture d'un fichier de l'API dans l'application
/// système appropriée.
///
/// Pourquoi ce détour plutôt qu'un simple lien confié au navigateur : depuis
/// l'audit H1, `/uploads/*` n'est plus servi publiquement et exige l'en-tête
/// `Authorization`. Un `url_launcher` sur l'URL brute répondrait donc 401.
/// Les octets doivent transiter par le Dio de l'application — celui qui porte
/// le jeton et sait le rafraîchir — puis être écrits sur disque, car
/// `open_file` prend un CHEMIN et non un flux.
class OuvertureFichier {
  final Dio dio;
  const OuvertureFichier({required this.dio});

  /// Caractères refusés dans un nom de fichier, tous systèmes confondus.
  ///
  /// Le nom vient du SERVEUR : le traiter comme sûr laisserait un
  /// `../../../` s'échapper du dossier temporaire au moment de l'écriture.
  /// Le backend assainit déjà de son côté (`utils/safeFilename.js`) — se
  /// reposer là-dessus reviendrait à faire dépendre la sécurité du client
  /// d'une garantie qu'il ne contrôle pas.
  static final _interdits = RegExp(r'[\\/:*?"<>|\x00-\x1f]');

  static String nomSur(String nomFichier) {
    // `split('/').last` puis `split(r'\').last` : on ne garde que le dernier
    // segment, quel que soit le séparateur — un `..` isolé ne survit pas au
    // remplacement qui suit.
    final base = nomFichier.split('/').last.split(r'\').last;
    final nettoye = base.replaceAll(_interdits, '_').replaceAll(RegExp(r'^\.+'), '');
    if (nettoye.trim().isEmpty) return 'document';
    // Certains systèmes de fichiers plafonnent à 255 octets ; on garde de la
    // marge pour le préfixe d'unicité ajouté plus bas.
    return nettoye.length > 120 ? nettoye.substring(nettoye.length - 120) : nettoye;
  }

  /// Télécharge [url] et l'ouvre. [nomFichier] sert de nom sur disque.
  ///
  /// [onProgression] reçoit une valeur de 0 à 1, ou `null` quand le serveur
  /// n'annonce pas de `Content-Length` — l'appelant doit alors afficher une
  /// progression indéterminée plutôt qu'une barre bloquée à zéro.
  Future<Either<Failure, ResultatOuverture>> ouvrir({
    required String url,
    required String nomFichier,
    void Function(double?)? onProgression,
  }) async {
    try {
      final reponse = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onProgression == null
            ? null
            : (recu, total) => onProgression(total > 0 ? recu / total : null),
      );

      final octets = reponse.data;
      if (octets == null || octets.isEmpty) {
        return Left(ServerFailure(errorMessage: 'Fichier vide'));
      }

      final dossier = await getTemporaryDirectory();
      // Préfixe horodaté : deux versions successives du même document
      // porteraient sinon le même chemin, et `open_file` rouvrirait l'ancienne
      // copie encore en cache.
      final horodatage = DateTime.now().millisecondsSinceEpoch;
      final chemin = '${dossier.path}${Platform.pathSeparator}${horodatage}_${nomSur(nomFichier)}';

      await File(chemin).writeAsBytes(octets, flush: true);

      final resultat = await plugin.OpenFile.open(chemin);
      return Right(
        resultat.type == plugin.ResultType.done ? ResultatOuverture.ouvert : ResultatOuverture.aucuneApplication,
      );
    } on DioException catch (e) {
      return Left(exceptionToFailure(mapDioException(e)));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
