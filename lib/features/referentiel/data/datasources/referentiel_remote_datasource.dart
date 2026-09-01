import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/code_niveau.dart';
import '../../domain/entities/pays.dart';
import '../../domain/entities/type_referentiel.dart';

abstract class ReferentielRemoteDataSource {
  Future<List<TypeReferentiel>> getTypesActifs(ReferentielType referentiel);

  /// Pays proposés à l'inscription, et les identifiants de chacun.
  Future<List<Pays>> getPays();

  /// Codes de niveau proposés à la saisie — « SS1 », « RDC », « R+1 »…
  Future<List<CodeNiveau>> getCodesNiveau();

  /// Crée un code absent de la liste. Il appartient à l'organisation de
  /// l'appelant : le serveur ne laisse pas écrire dans le catalogue standard.
  Future<CodeNiveau> creerCodeNiveau({
    required TypeNiveau typeNiveau,
    required String code,
    String? nom,
  });
}

class ReferentielRemoteDataSourceImpl implements ReferentielRemoteDataSource {
  final Dio dio;
  ReferentielRemoteDataSourceImpl({required this.dio});

  @override
  Future<List<TypeReferentiel>> getTypesActifs(ReferentielType referentiel) async {
    try {
      // `/actifs` et non la liste paginée : un sélecteur doit tout montrer
      // d'un coup, et les types désactivés n'ont rien à y faire.
      final response = await dio.get('${referentiel.chemin}/actifs');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return (data['types'] as List)
          .map((e) => TypeReferentiel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<CodeNiveau>> getCodesNiveau() async {
    try {
      // Les trois sections sont demandées d'un coup : l'écran de dépôt les
      // affiche ensemble, et trois appels pour une liste de vingt lignes
      // coûteraient trois allers-retours sur un réseau de chantier.
      final response = await dio.get('/referentiels/codes-niveau');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return (data['codes'] as List)
          .map((e) => CodeNiveau.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<CodeNiveau> creerCodeNiveau({
    required TypeNiveau typeNiveau,
    required String code,
    String? nom,
  }) async {
    try {
      final response = await dio.post('/referentiels/codes-niveau', data: {
        'typeNiveau': typeNiveau.raw,
        'code': code,
        if (nom != null && nom.isNotEmpty) 'nom': nom,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return CodeNiveau.fromJson(data['code'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<Pays>> getPays() async {
    try {
      // Route PUBLIQUE : c'est le formulaire d'INSCRIPTION qui la consomme,
      // son utilisateur n'a pas encore de session.
      final response = await dio.get('/referentiels/pays');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return (data['pays'] as List)
          .map((e) => Pays.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
