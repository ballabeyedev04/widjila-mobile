import 'package:dio/dio.dart';

import '../../../../core/config/env.dart';
import '../../../../core/network/dio_exception_mapper.dart';
import '../models/user_model.dart';

/// Résultat brut d'un appel de connexion — les tokens ne sont PAS stockés
/// ici (responsabilité du repository), cette couche ne fait que parler HTTP.
class AuthResponseModel {
  final String? token;
  final String? refreshToken;
  final bool mfaRequise;
  final UserModel utilisateur;

  AuthResponseModel({
    this.token,
    this.refreshToken,
    required this.mfaRequise,
    required this.utilisateur,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    return AuthResponseModel(
      token: json['token'] as String?,
      refreshToken: json['refreshToken'] as String?,
      mfaRequise: json['mfaRequise'] as bool? ?? false,
      utilisateur: UserModel.fromJson(json['utilisateur'] as Map<String, dynamic>),
    );
  }
}

abstract class AuthRemoteDataSource {
  Future<AuthResponseModel> login({required String identifiant, required String motDePasse});
  Future<AuthResponseModel> verifierMfa({required String code});
  Future<UserModel> register(Map<String, dynamic> payload);

  /// Renvoie le message du backend tel quel (pas de texte codé en dur côté
  /// mobile) — voir `AccountService.forgotPassword` : la même phrase est
  /// renvoyée QUE le compte existe ou non (anti-énumération), c'est donc
  /// aussi ce que l'app doit afficher, sans reformulation locale qui casserait
  /// cette garantie.
  Future<String> forgotPassword({required String email});

  /// Idem : message de confirmation renvoyé par le backend.
  Future<String> resetPassword({required String email, required String otp, required String nouveauMotDePasse});
  Future<void> logout();
  Future<UserModel> getMe();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final Dio dio;
  AuthRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  /// `/account/forgot-password` et `/account/reset-password` répondent
  /// `{ success, message }` SANS enveloppe `data` (contrairement au reste de
  /// l'API — voir `account.controller.js#forgotPassword/resetPassword`) :
  /// `_data()` ne s'applique donc pas ici.
  String _message(Response response) {
    final body = response.data;
    return (body is Map && body['message'] is String)
        ? body['message'] as String
        : 'Opération effectuée avec succès.';
  }

  @override
  Future<AuthResponseModel> login({required String identifiant, required String motDePasse}) async {
    try {
      final response = await dio.post(Env.authLogin, data: {
        'identifiant': identifiant,
        'mot_de_passe': motDePasse,
      });
      return AuthResponseModel.fromJson(_data(response));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<AuthResponseModel> verifierMfa({required String code}) async {
    try {
      final response = await dio.post(Env.authMfaVerify, data: {'code': code});
      return AuthResponseModel.fromJson(_data(response));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<UserModel> register(Map<String, dynamic> payload) async {
    try {
      final response = await dio.post(Env.authRegister, data: payload);
      final data = _data(response);
      return UserModel.fromJson(data['utilisateur'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<String> forgotPassword({required String email}) async {
    try {
      final response = await dio.post('/account/forgot-password', data: {'email': email});
      return _message(response);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<String> resetPassword({
    required String email,
    required String otp,
    required String nouveauMotDePasse,
  }) async {
    try {
      final response = await dio.post('/account/reset-password', data: {
        'email': email,
        'otp': otp,
        'nouveau_mot_de_passe': nouveauMotDePasse,
      });
      return _message(response);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> logout() async {
    // Best-effort — voir AuthRepositoryImpl.logout() : l'échec réseau ne
    // doit jamais bloquer la déconnexion locale.
    await dio.post(Env.authLogout, options: Options(extra: {'skipAuthInterceptor': true}));
  }

  @override
  Future<UserModel> getMe() async {
    try {
      final response = await dio.get('/account/me');
      final data = _data(response);
      return UserModel.fromJson(data['utilisateur'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
