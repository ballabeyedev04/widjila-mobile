import 'package:dio/dio.dart';

/// `true` si [e] traduit une COUPURE réseau (timeout, connexion impossible),
/// et non un refus applicatif du serveur (4xx/5xx, qui prouve au contraire
/// que le serveur a bien été joint).
///
/// Point de vérité UNIQUE, partagé par [SynchronisationService] (décide s'il
/// faut interrompre une passe de synchronisation) et par les repositories
/// hors ligne (décident s'il faut basculer une écriture en file d'attente) —
/// les deux doivent s'accorder sur la même définition, sinon un écran
/// pourrait mettre une action en attente que la synchronisation ne
/// considérerait jamais comme « à retenter ».
bool estCoupureReseau(DioException e) =>
    e.type == DioExceptionType.connectionError ||
    e.type == DioExceptionType.connectionTimeout ||
    e.type == DioExceptionType.receiveTimeout ||
    e.type == DioExceptionType.sendTimeout;
