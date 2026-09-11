import 'package:dio/dio.dart';

/// Options d'une requête qui ENVOIE un fichier — photo, vidéo, plan, document.
///
/// Chez Dio, `sendTimeout` borne l'envoi ENTIER du corps, pas l'inactivité.
/// Avec les 30 s par défaut du client, une vidéo ou un plan de quelques
/// méga-octets sur la 4G d'un chantier échouait en « délai dépassé » quel que
/// soit l'état du réseau. La réponse, elle, n'arrive qu'une fois le fichier
/// recopié par le serveur sur le stockage (Cloudflare R2) : elle mérite aussi
/// plus que 30 s.
Options optionsEnvoiFichier() => Options(
      sendTimeout: const Duration(minutes: 15),
      receiveTimeout: const Duration(minutes: 3),
    );
