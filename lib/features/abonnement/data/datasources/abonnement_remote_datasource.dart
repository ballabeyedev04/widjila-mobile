import 'package:dio/dio.dart';

import '../../../../core/config/env.dart';
import '../../../../core/network/cache_reponses_get.dart';
import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/abonnement.dart';

abstract class AbonnementRemoteDataSource {
  Future<List<FormuleAbonnement>> getFormules();
  Future<DroitsAbonnement> getDroits();
  Future<List<SouscriptionHistorique>> getHistorique();
  Future<String> creerCodeTransfertWeb();
  Future<EtatPaiement?> getEtatPaiement();

  // ── Devis « Premium sur devis » ───────────────────────────────────────
  Future<List<Devis>> listerDevis();
  Future<Devis> demanderDevis(DemandeDevis demande);
  Future<Devis> accepterDevis(String id);
  Future<Devis> refuserDevis(String id, String? motif);
  Future<String> payerDevis(String id);
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
  Future<EtatPaiement?> getEtatPaiement() async {
    try {
      // JAMAIS servie depuis le cache des GET : on interroge cet état
      // précisément parce qu'il vient peut-être de changer (webhook reçu il
      // y a une seconde). Une réponse d'il y a vingt secondes dirait « en
      // attente » d'un paiement déjà confirmé.
      final response = await dio.get(
        '/abonnement/paiement/etat',
        options: Options(extra: {CacheReponsesGet.ignorerCache: true}),
      );
      return EtatPaiement.fromJson(_data(response));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<Devis>> listerDevis() async {
    try {
      // Jamais depuis le cache des GET : un devis vient peut-être d'être
      // chiffré ou accepté, et un état d'il y a vingt secondes proposerait
      // un bouton que le serveur refuserait.
      final response = await dio.get(
        '/abonnement/devis',
        options: Options(extra: {CacheReponsesGet.ignorerCache: true}),
      );
      return (_data(response)['devis'] as List)
          .map((e) => Devis.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Devis> demanderDevis(DemandeDevis demande) async {
    try {
      final response = await dio.post('/abonnement/devis', data: demande.toJson());
      return Devis.fromJson(_data(response)['devis'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Devis> accepterDevis(String id) async {
    try {
      final response = await dio.post('/abonnement/devis/$id/accepter');
      return Devis.fromJson(_data(response)['devis'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Devis> refuserDevis(String id, String? motif) async {
    try {
      final response = await dio.post('/abonnement/devis/$id/refuser', data: {'motif': motif});
      return Devis.fromJson(_data(response)['devis'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<String> payerDevis(String id) async {
    try {
      // Rend l'ADRESSE de la page Stripe. Aucun montant n'est transmis : le
      // serveur relit celui qu'il a lui-même posé sur le devis.
      final response = await dio.post('/abonnement/devis/$id/paiement');
      return _data(response)['url'] as String;
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
