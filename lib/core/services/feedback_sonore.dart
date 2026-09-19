import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Le petit son qui accompagne une action RÉUSSIE.
///
/// « Réserve créée », « statut modifié », « synchronisation terminée » : la
/// confirmation visuelle (carte verte, bandeau) reste telle quelle, un bref
/// « c'est fait » sonore s'y ajoute. Un seul point d'entrée pour toute
/// l'application — les écrans demandent un feedback de succès, ils ne savent
/// pas comment le son est joué.
///
/// ## Où il se déclenche
///
/// Pas dans les écrans : dans ce qui AFFICHE déjà la confirmation. C'est
/// `AppAlert.success` (la carte verte), `AppAlert.confirmation` (le bandeau
/// bas) et le bandeau de synchronisation qui appellent [succes]. Le son est
/// donc joué exactement là où le code a déjà établi que l'action a réussi —
/// après la réponse du serveur ou l'écriture locale, jamais au clic —, et une
/// confirmation affichée vaut un son, ni plus ni moins.
///
/// ## Ce qu'il garantit
///
/// - **Jamais deux sons pour une action** : deux appels à moins de
///   [_ecartMinimum] d'intervalle (double appui, double émission d'un état
///   Bloc, page reconstruite) n'en jouent qu'un.
/// - **Jamais bloquant, jamais fatal** : le son part en tâche de fond ; un
///   appareil sans audio, un plugin absent (tests, web) ou un asset manquant
///   ne remontent aucune erreur à l'écran — la confirmation visuelle passe
///   avant.
/// - **Discret** : lu comme un son d'interface (`sonification`), sans prendre
///   le focus audio — une musique en cours n'est pas coupée — et, sur iOS, en
///   catégorie `ambient` : le commutateur silencieux le tait.
///
/// ## Erreurs
///
/// Pas de son d'erreur : la carte rouge suffit, et un son d'échec ajouté à un
/// refus déjà signalé alourdirait sans informer. `AppAlert.error` n'appelle
/// rien ici — c'est volontaire.
class FeedbackSonore {
  /// Asset du son de succès (~225 ms, deux notes montantes, -5 dBFS).
  static const String assetSucces = 'sounds/succes.wav';

  /// Sous cet écart, un second appel est un doublon (double appui, double
  /// émission d'état), pas une seconde action.
  static const Duration _ecartMinimum = Duration(milliseconds: 400);

  /// Instance utilisée par toute l'application. Remplaçable dans les tests
  /// (`FeedbackSonore.instance = FeedbackSonore(lecteur: …)`) — les widgets
  /// n'ont pas à recevoir le service en paramètre pour qu'un test le voie.
  static FeedbackSonore instance = FeedbackSonore();

  final LecteurSon _lecteur;
  final DateTime Function() _maintenant;
  DateTime? _dernierSucces;
  Future<void>? _prechargement;

  /// [horloge] : pour les tests de la garde anti-doublon, qui n'ont pas à
  /// attendre 400 ms réelles.
  FeedbackSonore({LecteurSon? lecteur, DateTime Function()? horloge})
      : _lecteur = lecteur ?? LecteurSonAudioplayers(),
        _maintenant = horloge ?? DateTime.now;

  /// Charge le son en mémoire pour que le premier succès ne soit pas retardé
  /// par la lecture de l'asset. Facultatif : [succes] fonctionne sans, un peu
  /// plus lentement la première fois. Silencieux en cas d'échec.
  Future<void> precharger() {
    return _prechargement ??= _lecteur.precharger(assetSucces).catchError((Object e) {
      debugPrint('[FeedbackSonore] préchargement impossible : $e');
    });
  }

  /// Joue le son de succès — UNE fois, même si on l'appelle deux fois de
  /// suite. Ne lève jamais.
  ///
  /// À appeler seulement quand le succès est ÉTABLI (réponse du serveur ou
  /// écriture locale réussie), jamais au moment où l'action est lancée.
  void succes() {
    final maintenant = _maintenant();
    final dernier = _dernierSucces;
    if (dernier != null && maintenant.difference(dernier) < _ecartMinimum) return;
    _dernierSucces = maintenant;

    // En tâche de fond : l'affichage de la confirmation n'attend pas l'audio.
    unawaited(_lecteur.jouer(assetSucces).catchError((Object e) {
      debugPrint('[FeedbackSonore] lecture impossible : $e');
    }));
  }

  /// Pour les tests : oublie le dernier succès, afin que deux cas d'un même
  /// test ne se voient pas comme un doublon.
  @visibleForTesting
  void reinitialiser() => _dernierSucces = null;
}

/// Ce que [FeedbackSonore] attend d'un moteur audio — une lecture d'asset,
/// rien de plus. C'est la seule couche qui connaît `audioplayers` ; les
/// tests la remplacent par un enregistreur d'appels.
abstract class LecteurSon {
  Future<void> precharger(String asset);
  Future<void> jouer(String asset);
}

/// Moteur réel, sur `audioplayers`.
class LecteurSonAudioplayers implements LecteurSon {
  AudioPlayer? _lecteur;

  /// Contexte audio d'un SON D'INTERFACE : pas de focus audio (une musique en
  /// cours continue), contenu « sonification », et sur iOS la catégorie
  /// `ambient` qui respecte le commutateur silencieux.
  static final AudioContext _contexte = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.ambient,
      options: const {AVAudioSessionOptions.mixWithOthers},
    ),
  );

  Future<AudioPlayer> _obtenir() async {
    final existant = _lecteur;
    if (existant != null) return existant;
    final lecteur = AudioPlayer(playerId: 'feedback-sonore');
    await lecteur.setAudioContext(_contexte);
    await lecteur.setPlayerMode(PlayerMode.lowLatency);
    await lecteur.setReleaseMode(ReleaseMode.stop);
    await lecteur.setVolume(1);
    return _lecteur = lecteur;
  }

  @override
  Future<void> precharger(String asset) async {
    final lecteur = await _obtenir();
    await lecteur.setSource(AssetSource(asset));
  }

  @override
  Future<void> jouer(String asset) async {
    final lecteur = await _obtenir();
    // `stop` puis `play` : un son encore en cours (deux succès à plus de
    // 400 ms mais moins de 225 ms de fin) repart du début au lieu de se
    // superposer.
    await lecteur.stop();
    await lecteur.play(AssetSource(asset));
  }
}
