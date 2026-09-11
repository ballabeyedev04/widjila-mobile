import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
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

/// Téléchargement, aperçu, ouverture et enregistrement d'un fichier de l'API.
///
/// Pourquoi ce détour plutôt qu'un simple lien confié au navigateur : depuis
/// l'audit H1, `/uploads/*` n'est plus servi publiquement et exige l'en-tête
/// `Authorization`. Un `url_launcher` sur l'URL brute répondrait donc 401.
/// Les octets doivent transiter par le Dio de l'application — celui qui porte
/// le jeton et sait le rafraîchir.
///
/// Trois usages, trois destinations des octets :
///   - [telecharger] : en MÉMOIRE seulement — l'aperçu intégré (« voir sans
///     télécharger ») ; rien n'est écrit sur l'appareil ;
///   - [ouvrir] / [ouvrirOctets] : copie dans le dossier TEMPORAIRE, confiée à
///     l'application système (`open_file` prend un chemin, pas un flux) ;
///   - [enregistrer] : copie DURABLE, à l'emplacement choisi par l'utilisateur.
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

  /// Télécharge [url] EN MÉMOIRE, sans rien écrire sur l'appareil.
  ///
  /// [onProgression] reçoit une valeur de 0 à 1, ou `null` quand le serveur
  /// n'annonce pas de `Content-Length` — l'appelant doit alors afficher une
  /// progression indéterminée plutôt qu'une barre bloquée à zéro.
  Future<Either<Failure, Uint8List>> telecharger({
    required String url,
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
      return Right(octets is Uint8List ? octets : Uint8List.fromList(octets));
    } on DioException catch (e) {
      return Left(exceptionToFailure(mapDioException(e)));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Télécharge [url] et l'ouvre dans l'application système appropriée.
  /// [nomFichier] sert de nom sur disque ; [onProgression] : voir [telecharger].
  Future<Either<Failure, ResultatOuverture>> ouvrir({
    required String url,
    required String nomFichier,
    void Function(double?)? onProgression,
  }) async {
    final octets = await telecharger(url: url, onProgression: onProgression);
    return octets.fold<Future<Either<Failure, ResultatOuverture>>>(
      (failure) async => Left(failure),
      (donnees) => ouvrirOctets(octets: donnees, nomFichier: nomFichier),
    );
  }

  /// Confie des octets DÉJÀ chargés à l'application système appropriée —
  /// depuis l'aperçu, sans second téléchargement.
  Future<Either<Failure, ResultatOuverture>> ouvrirOctets({
    required List<int> octets,
    required String nomFichier,
  }) async {
    try {
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
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  /// Enregistre [octets] sur l'appareil, à l'emplacement choisi par
  /// l'utilisateur.
  ///
  /// Passe par la boîte « Enregistrer sous » du système — le sélecteur de
  /// documents d'Android, qui propose le dossier Téléchargements, ou l'app
  /// Fichiers d'iOS. Aucune permission de stockage n'est demandée : c'est
  /// l'utilisateur qui désigne le fichier à créer, et le système n'accorde
  /// l'écriture que pour celui-là.
  ///
  /// `Right(false)` : l'utilisateur a refermé la boîte sans enregistrer. Ce
  /// n'est pas une erreur, rien ne doit s'afficher.
  Future<Either<Failure, bool>> enregistrer({
    required Uint8List octets,
    required String nomFichier,
  }) async {
    try {
      final chemin = await FilePicker.platform.saveFile(fileName: nomSur(nomFichier), bytes: octets);
      return Right(chemin != null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
