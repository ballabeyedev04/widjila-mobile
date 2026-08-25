import 'package:equatable/equatable.dart';

/// Session active (refresh token vivant) — miroir de la sélection faite par
/// `AccountService.listSessions` (`backend/src/modules/account/service/account.service.js`).
/// Le refresh token brut n'est jamais exposé : seuls l'identifiant, la date
/// d'ouverture et l'échéance le sont.
class SessionActive extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime expiresAt;

  const SessionActive({required this.id, required this.createdAt, required this.expiresAt});

  factory SessionActive.fromJson(Map<String, dynamic> json) => SessionActive(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );

  @override
  List<Object?> get props => [id, createdAt, expiresAt];
}
