import 'package:equatable/equatable.dart';

/// Entrée de l'historique de connexion — miroir de `ConnexionLog`
/// (`backend/src/models/connexionLog.model.js`). [type] vaut 'password',
/// 'mfa' ou 'refresh' ; [ip] est nullable (tentatives sans réseau tracé).
class ConnexionLogEntry extends Equatable {
  final String id;
  final bool succes;
  final String type;
  final String? ip;
  final DateTime createdAt;

  const ConnexionLogEntry({
    required this.id,
    required this.succes,
    required this.type,
    this.ip,
    required this.createdAt,
  });

  factory ConnexionLogEntry.fromJson(Map<String, dynamic> json) => ConnexionLogEntry(
        id: json['id'] as String,
        succes: json['succes'] as bool? ?? false,
        type: json['type'] as String? ?? 'password',
        ip: json['ip'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  List<Object?> get props => [id, succes, type, ip, createdAt];
}
