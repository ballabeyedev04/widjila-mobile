import 'dart:async';

/// Bus d'événements minimal pour notifier une déconnexion forcée depuis un
/// endroit sans accès à un `BuildContext` (l'intercepteur Dio, au fin fond
/// de la couche réseau). Le routeur (go_router, `refreshListenable`) écoute
/// ce flux pour rediriger immédiatement vers /login.
class AuthEventBus {
  AuthEventBus._();
  static final AuthEventBus instance = AuthEventBus._();

  final _controller = StreamController<void>.broadcast();

  Stream<void> get onForcedLogout => _controller.stream;

  void emitLogout() {
    if (!_controller.isClosed) _controller.add(null);
  }

  void dispose() => _controller.close();
}
