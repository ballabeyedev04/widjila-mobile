import 'package:dio/dio.dart';

import '../../../../core/config/env.dart';
import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/abonnement.dart';

abstract class AbonnementRemoteDataSource {
  Future<List<FormuleAbonnement>> getFormules();
  Future<DroitsAbonnement> getDroits();
  Future<List<SouscriptionHistorique>> getHistorique();
  Future<String> creerCodeTransfertWeb();
}

class AbonnementRemoteDataSourceImpl implements AbonnementRemoteDataSource {
  final Dio dio;
  AbonnementRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<List<FormuleAbonnement>> getFormules() async {
    try {
      // Route PUBLIQUE : elle reste accessible même sans abonnement actif,
      // sans quoi un client dont l'essai est terminé ne pourrait plus voir
      // les offres — précisément quand il en a besoin.
      final response = await dio.get('/abonnement/plans');
      return (_data(response)['plans'] as List)
          .map((e) => FormuleAbonnement.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<DroitsAbonnement> getDroits() async {
    try {
      final response = await dio.get('/abonnement/droits');
      return DroitsAbonnement.fromJson(_data(response));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<SouscriptionHistorique>> getHistorique() async {
    try {
      // Route réservée à GESTION côté serveur (`subscription.route.js`) : un
      // rôle qui ne peut pas engager de dépense ne voit pas la facturation.
      // L'appelant doit donc savoir traiter un 403 comme un refus normal, et
      // non comme une panne — voir `AbonnementCubit.charger`.
      final response = await dio.get('/abonnement/historique');
      return (_data(response)['souscriptions'] as List)
          .map((e) => SouscriptionHistorique.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<String> creerCodeTransfertWeb() async {
    try {
      // Code de deux minutes, à usage unique, que la page de paiement du web
      // échange contre une session (`auth.service.js#_generateTransfertWeb`).
      // Jamais le jeton d'accès ni le refresh token dans une adresse.
      final response = await dio.post(Env.authTransfertWeb);
      return _data(response)['code'] as String;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
