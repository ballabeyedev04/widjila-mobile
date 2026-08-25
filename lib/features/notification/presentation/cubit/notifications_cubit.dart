import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/notification.dart';
import '../../domain/usecases/get_notifications.dart';
import '../../domain/usecases/marquer_notifications_lues.dart';

enum NotificationsStatus { initial, chargement, succes, erreur }

class NotificationsState extends Equatable {
  final NotificationsStatus status;
  final List<NotificationItem> items;
  final int nonLues;
  final String? erreur;

  const NotificationsState({
    this.status = NotificationsStatus.initial,
    this.items = const [],
    this.nonLues = 0,
    this.erreur,
  });

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<NotificationItem>? items,
    int? nonLues,
    String? erreur,
  }) {
    return NotificationsState(
      status: status ?? this.status,
      items: items ?? this.items,
      nonLues: nonLues ?? this.nonLues,
      erreur: erreur,
    );
  }

  @override
  List<Object?> get props => [status, items, nonLues, erreur];
}

/// Notifications de l'utilisateur connecté.
///
/// Un seul cubit sert la pastille de l'en-tête ET la feuille qui liste les
/// messages : le compteur de non-lues arrive dans la même réponse que la liste
/// (voir `notification.service.js`), les tenir séparés ferait diverger la
/// pastille de son contenu après un « tout marquer comme lu ».
class NotificationsCubit extends Cubit<NotificationsState> {
  final GetNotifications getNotifications;
  final MarquerNotificationsLues marquerLues;

  NotificationsCubit({required this.getNotifications, required this.marquerLues})
      : super(const NotificationsState());

  Future<void> charger() async {
    emit(state.copyWith(status: NotificationsStatus.chargement));
    final result = await getNotifications();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(status: NotificationsStatus.erreur, erreur: failure.errorMessage)),
      (page) => emit(state.copyWith(
        status: NotificationsStatus.succes,
        items: page.items,
        nonLues: page.nonLues,
      )),
    );
  }

  /// Marque tout comme lu, puis recharge pour refléter l'état réel du serveur
  /// plutôt que de le supposer.
  Future<void> toutMarquerLu() async {
    if (state.nonLues == 0) return;
    final result = await marquerLues();
    if (isClosed) return;
    await result.fold(
      (failure) async => emit(state.copyWith(erreur: failure.errorMessage)),
      (_) async => charger(),
    );
  }
}
