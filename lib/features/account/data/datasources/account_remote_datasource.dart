import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../../../core/services/token_service.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/domain/entities/user.dart';
import '../../domain/entities/connexion_log_entry.dart';
import '../../domain/entities/mfa_provisionnement.dart';
import '../../domain/entities/session_active.dart';

abstract class AccountRemoteDataSource {
  Future<bool> getStatutMfa();
  Future<List<ConnexionLogEntry>> getConnexions();
  Future<List<SessionActive>> getSessions();
  Future<void> revokerSession(String sessionId);
  Future<void> revokerToutesSessions();
  Future<MfaProvisionnement> provisionnerMfa();
  Future<void> activerMfa({required String secret, required String code});
  Future<void> desactiverMfa({required String code});
  Future<void> changerLangue(String code);

  /// `PUT /account/profil` — nom, prénom, téléphone, fonction et photo.
  ///
  /// Un champ ABSENT (`null`) est laissé tel quel côté serveur ; une chaîne
  /// VIDE efface la valeur (téléphone et fonction uniquement). Les deux cas
  /// doivent donc rester distincts jusqu'au corps de la requête.
  Future<User> modifierProfil({
    String? nom,
    String? prenom,
    String? telephone,
    String? fonction,
    String? cheminPhoto,
  });

  /// `PUT /account/change-password` — remet aussi `mdp_temporaire` à faux
  /// côté serveur, ce qui fait de cette route le SEUL moyen de solder un mot
  /// de passe provisoire sans passer par le circuit « mot de passe oublié ».
  /// Renvoie le nombre d'AUTRES sessions fermées par l'opération.
  Future<int> changerMotDePasse({
    required String ancienMotDePasse,
    required String nouveauMotDePasse,
  });
  Future<Map<String, dynamic>> exporterDonnees();
  Future<void> supprimerCompte();
}

class AccountRemoteDataSourceImpl implements AccountRemoteDataSource {
  final Dio dio;

  /// Sert UNIQUEMENT au changement de mot de passe, pour deux choses :
  ///  - désigner la session de cet appareil, que le serveur épargne quand il
  ///    révoque les autres (le token d'accès ne porte pas d'identifiant de
  ///    session) ;
  ///  - enregistrer le token d'accès neuf renvoyé en réponse, l'ancien ayant
  ///    été périmé par l'incrémentation de `token_version`.
  final TokenService tokenService;

  AccountRemoteDataSourceImpl({required this.dio, required this.tokenService});

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<bool> getStatutMfa() async {
    try {
      final response = await dio.get('/account/me');
      final utilisateur = _data(response)['utilisateur'] as Map<String, dynamic>;
      return utilisateur['mfaActive'] as bool? ?? false;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<ConnexionLogEntry>> getConnexions() async {
    try {
      final response = await dio.get('/account/connexions', queryParameters: {'limit': 50});
      final connexions = _data(response)['connexions'] as List;
      return connexions.map((e) => ConnexionLogEntry.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<SessionActive>> getSessions() async {
    try {
      final response = await dio.get('/account/sessions');
      final sessions = _data(response)['sessions'] as List;
      return sessions.map((e) => SessionActive.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> revokerSession(String sessionId) async {
    try {
      await dio.delete('/account/sessions/$sessionId');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> revokerToutesSessions() async {
    try {
      await dio.delete('/account/sessions');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<MfaProvisionnement> provisionnerMfa() async {
    try {
      final response = await dio.post('/account/mfa/provision');
      return MfaProvisionnement.fromJson(_data(response));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> activerMfa({required String secret, required String code}) async {
    try {
      await dio.post('/account/mfa/enable', data: {'secret': secret, 'code': code});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> desactiverMfa({required String code}) async {
    try {
      await dio.post('/account/mfa/disable', data: {'code': code});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> changerLangue(String code) async {
    try {
      await dio.put('/account/profil', data: {'langue': code});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<User> modifierProfil({
    String? nom,
    String? prenom,
    String? telephone,
    String? fonction,
    String? cheminPhoto,
  }) async {
    try {
      // `null` = champ non touché, donc omis du corps. La chaîne vide, elle,
      // est TRANSMISE : c'est ainsi qu'on efface un téléphone ou une fonction.
      final champs = <String, dynamic>{
        if (nom != null) 'nom': nom,
        if (prenom != null) 'prenom': prenom,
        if (telephone != null) 'telephone': telephone,
        if (fonction != null) 'fonction': fonction,
      };

      // Multipart UNIQUEMENT s'il y a une photo : le serveur accepte les deux
      // formes, et un envoi JSON reste plus léger pour une simple correction
      // de nom. Le champ de fichier s'appelle `photoProfil` — nom imposé par
      // `upload.fields([{ name: 'photoProfil' }])` côté back.
      final response = await dio.put(
        '/account/profil',
        data: cheminPhoto == null
            ? champs
            : FormData.fromMap({
                ...champs,
                'photoProfil': await MultipartFile.fromFile(cheminPhoto),
              }),
      );
      return UserModel.fromJson(_data(response)['utilisateur'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<int> changerMotDePasse({
    required String ancienMotDePasse,
    required String nouveauMotDePasse,
  }) async {
    try {
      // Refresh token de CET appareil : le serveur révoque toutes les autres
      // sessions et laisse celle-ci ouverte. S'il manque (lecture du stockage
      // sécurisé en échec), le serveur révoque tout — l'utilisateur devra se
      // reconnecter, ce qui est le bon défaut : on préfère une reconnexion de
      // trop à une session volée laissée ouverte.
      final refreshToken = await tokenService.getRefreshToken();
      final response = await dio.put('/account/change-password', data: {
        'ancien_mot_de_passe': ancienMotDePasse,
        'nouveau_mot_de_passe': nouveauMotDePasse,
        if (refreshToken != null && refreshToken.isNotEmpty) 'refresh_token': refreshToken,
      });
      final data = _data(response);

      // Le serveur a incrémenté `token_version` : notre token d'accès actuel
      // est mort à la seconde même. Sans ce remplacement, la requête suivante
      // repartirait avec l'ancien et l'utilisateur serait déconnecté par son
      // propre geste de sécurisation.
      //
      // Le refresh token, lui, a été épargné côté serveur — inutile d'y
      // toucher, et le renouvellement automatique reste disponible en repli
      // si l'écriture ci-dessous échouait.
      final accessToken = data['accessToken'] as String?;
      if (accessToken != null && accessToken.isNotEmpty) {
        await tokenService.setToken(accessToken);
      }

      // Défaut à 0 si le serveur ne le renvoie pas (déploiement plus ancien) :
      // le mot de passe a bien changé, seule la précision du message se perd.
      return data['sessionsRevoquees'] as int? ?? 0;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> exporterDonnees() async {
    try {
      final response = await dio.get('/account/export-data');
      return _data(response);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> supprimerCompte() async {
    try {
      await dio.delete('/account/delete-account');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
