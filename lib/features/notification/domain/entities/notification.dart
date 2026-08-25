import 'package:equatable/equatable.dart';

/// Notification adressée à l'utilisateur connecté.
///
/// Miroir du modèle `backend/src/models/notification.model.js`. Le champ de
/// lecture s'appelle `lu_a` côté serveur — d'où le décalage de nom avec
/// [luLe], qui suit la convention Dart.
class NotificationItem extends Equatable {
  final String id;

  /// Catégorie métier libre côté serveur (`STRING(50)`) : `reserve`,
  /// `inspection`, `convocation`… Sert à choisir l'icône, avec un repli neutre
  /// pour toute valeur inconnue — le back peut en ajouter sans casser le
  /// mobile.
  final String type;

  final String titre;
  final String? message;
  final DateTime? luLe;
  final DateTime? creeLe;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.titre,
    this.message,
    this.luLe,
    this.creeLe,
  });

  bool get nonLue => luLe == null;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    DateTime? date(dynamic valeur) =>
        valeur is String ? DateTime.tryParse(valeur)?.toLocal() : null;

    return NotificationItem(
      id: json['id'] as String,
      type: (json['type'] as String?) ?? 'info',
      titre: (json['titre'] as String?) ?? '',
      message: json['message'] as String?,
      luLe: date(json['lu_a']),
      creeLe: date(json['createdAt']),
    );
  }

  @override
  List<Object?> get props => [id, type, titre, message, luLe, creeLe];
}
