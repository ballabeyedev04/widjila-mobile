import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/inspection.dart';

abstract class InspectionRemoteDataSource {
  Future<List<Inspection>> getInspections({required String chantierId, InspectionStatut? statut});
  Future<Inspection> getInspection(String id);
  Future<Inspection> creerInspection({
    required String chantierId,
    /// CODE du type, issu du référentiel administrable
    /// (`/types-inspection/actifs`). Une énumération figée ici
    /// empêcherait d'utiliser un type ajouté par l'administrateur.
    required String typeCode,
    DateTime? dateVisite,
    List<String> libellesChecklist,
  });
  Future<Inspection> changerStatut({required String id, required InspectionStatut statut, String? compteRendu});
  Future<LigneChecklist> cocherLigne({
    required String inspectionId,
    required String ligneId,
    required bool coche,
    String? commentaire,
  });
  Future<List<Convocation>> getConvocations(String inspectionId);
  Future<void> repondreConvocation({
    required String inspectionId,
    required String convocationId,
    required StatutConvocation statut,
  });
}

class InspectionRemoteDataSourceImpl implements InspectionRemoteDataSource {
  final Dio dio;
  InspectionRemoteDataSourceImpl({required this.dio});

  /// Déballe `{ success, message, data: { … } }` — enveloppe uniforme du back.
  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<List<Inspection>> getInspections({required String chantierId, InspectionStatut? statut}) async {
    try {
      final response = await dio.get(
        '/chantiers/$chantierId/inspections',
        queryParameters: {if (statut != null) 'statut': statut.raw},
      );
      return (_data(response)['inspections'] as List)
          .map((e) => Inspection.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Inspection> getInspection(String id) async {
    try {
      final response = await dio.get('/inspections/$id');
      return Inspection.fromJson(_data(response)['inspection'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Inspection> creerInspection({
    required String chantierId,
    /// CODE du type, issu du référentiel administrable
    /// (`/types-inspection/actifs`). Une énumération figée ici
    /// empêcherait d'utiliser un type ajouté par l'administrateur.
    required String typeCode,
    DateTime? dateVisite,
    List<String> libellesChecklist = const [],
  }) async {
    try {
      final response = await dio.post('/chantiers/$chantierId/inspections', data: {
        'chantierId': chantierId,
        'type': typeCode,
        // `date_visite` est un DATEONLY côté serveur : on n'envoie que la
        // partie date, sinon Joi reçoit un instant avec fuseau et la visite
        // peut basculer d'un jour selon l'heure de saisie.
        if (dateVisite != null) 'date_visite': dateVisite.toIso8601String().split('T').first,
        if (libellesChecklist.isNotEmpty)
          'checklist': libellesChecklist.map((l) => {'libelle': l}).toList(),
      });
      return Inspection.fromJson(_data(response)['inspection'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Inspection> changerStatut({
    required String id,
    required InspectionStatut statut,
    String? compteRendu,
  }) async {
    try {
      final response = await dio.put('/inspections/$id', data: {
        'statut': statut.raw,
        if (compteRendu != null) 'compte_rendu': compteRendu,
      });
      return Inspection.fromJson(_data(response)['inspection'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<LigneChecklist> cocherLigne({
    required String inspectionId,
    required String ligneId,
    required bool coche,
    String? commentaire,
  }) async {
    try {
      final response = await dio.patch(
        '/inspections/$inspectionId/checklist/$ligneId',
        data: {
          'coche': coche,
          if (commentaire != null) 'commentaire': commentaire,
        },
      );
      return LigneChecklist.fromJson(_data(response)['ligne'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<Convocation>> getConvocations(String inspectionId) async {
    try {
      final response = await dio.get('/inspections/$inspectionId/convocations');
      return (_data(response)['convocations'] as List)
          .map((e) => Convocation.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> repondreConvocation({
    required String inspectionId,
    required String convocationId,
    required StatutConvocation statut,
  }) async {
    try {
      await dio.patch(
        '/inspections/$inspectionId/convocations/$convocationId',
        data: {'statut': statut.raw},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
