import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../theme/app_colors.dart';

/// Canal de notification Android.
///
/// Cet identifiant est un CONTRAT à trois : il doit être identique ici, dans
/// `android/app/src/main/AndroidManifest.xml` (canal par défaut) et dans le
/// `channelId` envoyé par le back (`notification.service.js`). Un identifiant
/// inconnu et Android retombe sur un canal par défaut, sans son ni vibration.
const String canalAlertes = 'suivi_chantier_alertes';

/// Point d'entrée des messages reçus alors que l'application est TERMINÉE ou
/// en arrière-plan.
///
/// Doit être une fonction de premier niveau annotée `@pragma('vm:entry-point')`
/// : Flutter la réveille dans un isolat séparé, sans accès à l'état de
/// l'application. On n'y fait donc rien — Android a déjà affiché l'alerte à
/// partir du bloc `notification` du message. Le corps sert uniquement à
/// enregistrer le passage.
@pragma('vm:entry-point')
Future<void> messageEnArrierePlan(RemoteMessage message) async {
  debugPrint('[push] reçu en arrière-plan : ${message.messageId}');
}

/// Notifications push — inscription de l'appareil, permissions et affichage.
///
/// ## Trois situations, trois responsables
///
///  - **application fermée ou en arrière-plan** : c'est le SYSTÈME qui affiche
///    l'alerte, à partir du bloc `notification` du message FCM. Rien à faire
///    côté Dart, et c'est ce qui permet à l'utilisateur d'être prévenu
///    téléphone verrouillé ;
///  - **application au premier plan** : Android n'affiche RIEN de lui-même.
///    C'est [flutter_local_notifications] qui dessine la bannière ;
///  - **alerte touchée** : [onOuverture] est appelé avec les données du
///    message, pour naviguer vers l'écran concerné.
///
/// ## Tolérance aux pannes
///
/// Tout est encapsulé : sans `google-services.json`, sans réseau ou avec une
/// permission refusée, [initialiser] renonce en silence et l'application
/// fonctionne normalement. Le push est un canal SECONDAIRE — les notifications
/// restent consultables dans l'écran dédié.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();

  bool _pret = false;
  String? _jetonCourant;

  /// Rappelé quand l'utilisateur touche une alerte. Reçoit le contenu `data`
  /// du message (type + données métier sérialisées par le back).
  void Function(Map<String, dynamic> donnees)? onOuverture;

  /// Rappelé à chaque obtention ou rotation du jeton FCM. C'est l'application
  /// qui décide quoi en faire (l'envoyer au back si l'utilisateur est
  /// connecté) — le service, lui, ne connaît pas la session.
  void Function(String jeton)? onJeton;

  /// Filtre d'affichage — consulté avant chaque bannière du premier plan.
  ///
  /// Injecté plutôt que lu depuis le conteneur d'injection : ce service est un
  /// singleton créé avant lui, et le garder sans dépendance permet de le
  /// tester sans Firebase ni `SharedPreferences`.
  ///
  /// Absent, tout passe : un filtre non branché ne doit jamais faire taire
  /// l'application par accident.
  bool Function(String type)? filtreAffichage;

  /// Dernier jeton connu, `null` si le push n'est pas actif.
  String? get jeton => _jetonCourant;

  bool get estActif => _pret;

  /// Prépare Firebase, le canal Android et les écoutes.
  ///
  /// Idempotent : un second appel ne fait rien.
  Future<void> initialiser() async {
    if (_pret) return;

    try {
      // `main.dart` initialise déjà Firebase au démarrage (pour Crashlytics,
      // voir `_demarrerAvecSurveillanceCrash`) — `isEmpty` évite un second
      // `initializeApp()` sur l'app par défaut, qui lèverait une erreur
      // « duplicate-app » plutôt que de la réutiliser silencieusement.
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    } catch (e) {
      // Cas nominal tant que `google-services.json` n'a pas été déposé.
      debugPrint('[push] Firebase non configuré — notifications push inactives ($e)');
      return;
    }

    try {
      await _preparerAffichageLocal();
      await _demanderPermission();

      FirebaseMessaging.onBackgroundMessage(messageEnArrierePlan);
      FirebaseMessaging.onMessage.listen(_afficherAuPremierPlan);
      FirebaseMessaging.onMessageOpenedApp.listen(_ouvrir);

      // Application lancée DEPUIS une alerte : le message n'est pas rejoué par
      // `onMessageOpenedApp`, il faut aller le chercher.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _ouvrir(initial);

      FirebaseMessaging.instance.onTokenRefresh.listen(_publierJeton);
      final jeton = await FirebaseMessaging.instance.getToken();
      if (jeton != null) _publierJeton(jeton);

      _pret = true;
    } catch (e) {
      debugPrint('[push] Initialisation incomplète : $e');
    }
  }

  /// Crée le canal Android et branche les taps sur les alertes locales.
  Future<void> _preparerAffichageLocal() async {
    const parametres = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        // Les alertes du premier plan sont dessinées par nos soins : laisser
        // iOS les afficher AUSSI produirait un doublon.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _local.initialize(
      parametres,
      onDidReceiveNotificationResponse: (reponse) {
        final charge = reponse.payload;
        if (charge == null || charge.isEmpty) return;
        onOuverture?.call(_decoder(charge));
      },
    );

    // `importance: max` est ce qui autorise la bannière par-dessus l'écran
    // courant. Un canal créé en `default` reste silencieux en haut de la liste
    // et son importance ne peut PLUS être relevée par la suite : Android
    // interdit d'augmenter l'importance d'un canal existant.
    const canal = AndroidNotificationChannel(
      canalAlertes,
      'Alertes chantier',
      description: 'Réserves, inspections et échéances de vos chantiers.',
      importance: Importance.max,
    );

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canal);
  }

  Future<void> _demanderPermission() async {
    // Android 13+ et iOS exigent un accord explicite. Un refus n'est pas une
    // erreur : l'application continue, seules les bannières manquent.
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Affiche une bannière quand l'application est visible.
  Future<void> _afficherAuPremierPlan(RemoteMessage message) async {
    final alerte = message.notification;
    if (alerte == null) return;

    // Filtre LOCAL : l'utilisateur a coupé cette famille d'alertes sur cet
    // appareil. Le serveur continue de les envoyer et elles restent lisibles
    // dans l'écran Notifications — on cesse seulement de l'interrompre.
    final type = message.data['type']?.toString() ?? '';
    if (filtreAffichage != null && !filtreAffichage!(type)) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        canalAlertes,
        'Alertes chantier',
        channelDescription: 'Réserves, inspections et échéances de vos chantiers.',
        importance: Importance.max,
        priority: Priority.high,
        icon: 'ic_notification',
        // Le LOGO de l'application, en couleurs, dans l'alerte déroulée — la
        // petite icône de la barre d'état, elle, est forcément monochrome.
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        color: AppColors.primary,
        styleInformation: BigTextStyleInformation(alerte.body ?? ''),
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true),
    );

    await _local.show(
      // `hashCode` du messageId : un identifiant stable par message, qui évite
      // qu'un même push affiché deux fois n'empile deux bannières.
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
      alerte.title,
      alerte.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  void _ouvrir(RemoteMessage message) => onOuverture?.call(message.data);

  void _publierJeton(String jeton) {
    if (jeton == _jetonCourant) return;
    _jetonCourant = jeton;
    onJeton?.call(jeton);
  }

  /// Décode la charge utile d'une alerte locale, en tolérant tout format
  /// inattendu : un message malformé ne doit pas faire planter l'ouverture.
  Map<String, dynamic> _decoder(String charge) {
    try {
      final decode = jsonDecode(charge);
      return decode is Map<String, dynamic> ? decode : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
