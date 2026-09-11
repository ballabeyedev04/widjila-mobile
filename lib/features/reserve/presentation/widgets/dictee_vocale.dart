import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Ce qui peut empêcher ou interrompre une dictée — chaque cas a son message.
enum ErreurDictee {
  /// Le micro a été refusé (maintenant ou auparavant).
  microRefuse,

  /// Aucun service de reconnaissance vocale sur l'appareil.
  indisponible,

  /// L'écoute s'est terminée sans qu'aucune parole soit reconnue.
  aucuneParole,

  /// La reconnaissance du téléphone a besoin du réseau et n'en a pas.
  reseau,

  /// Toute autre interruption (micro occupé, service arrêté…).
  interrompue,
}

/// Traduit un code d'erreur de la reconnaissance vocale native.
///
/// Codes Android (`SpeechRecognizer.ERROR_*`, tels que les nomme
/// speech_to_text) et iOS ; tout code inconnu est une interruption.
ErreurDictee erreurDicteeDepuisCode(String code) => switch (code) {
      'error_no_match' || 'error_speech_timeout' => ErreurDictee.aucuneParole,
      'error_permission' || 'error_insufficient_permissions' => ErreurDictee.microRefuse,
      'error_network' || 'error_network_timeout' || 'error_server' || 'error_server_disconnected' =>
        ErreurDictee.reseau,
      _ => ErreurDictee.interrompue,
    };

/// Moteur de reconnaissance vocale, vu du champ « Observation ».
///
/// Abstrait pour que le champ se teste sans micro ni plateforme : les tests
/// lui fournissent un moteur factice qui « dit » ce qu'on veut.
abstract class MoteurDictee {
  /// Prépare la reconnaissance — le système demande l'accès au micro la
  /// première fois. `null` si tout est prêt, sinon la raison de l'échec.
  Future<ErreurDictee?> preparer();

  /// Démarre l'écoute.
  ///
  /// [surResultat] reçoit le texte reconnu DEPUIS LE DÉBUT de cette écoute
  /// (il s'enrichit au fil de la parole) et s'il est définitif. [surFin] est
  /// appelé UNE fois, à la fin de l'écoute : `null` si elle s'est terminée
  /// normalement (silence, arrêt demandé), sinon l'erreur.
  Future<void> ecouter({
    required String langue,
    required void Function(String texte, bool definitif) surResultat,
    required void Function(ErreurDictee? erreur) surFin,
  });

  /// Termine l'écoute EN GARDANT ce qui a été dit (le résultat final suit).
  Future<void> arreter();

  /// Termine l'écoute SANS résultat.
  Future<void> annuler();
}

/// Moteur réel : la reconnaissance vocale du téléphone (Android
/// `SpeechRecognizer`, iOS `SFSpeechRecognizer`) via speech_to_text.
class MoteurDicteeSpeechToText implements MoteurDictee {
  /// Instance PARTAGÉE par toute l'application (`SpeechToText()` est un
  /// singleton du plugin).
  final SpeechToText _stt = SpeechToText();

  void Function(ErreurDictee? erreur)? _surFin;

  /// Vrai quand la fin de l'écoute en cours a déjà été signalée : le plugin
  /// peut remonter une erreur PUIS un statut « done » pour la même écoute.
  bool _finSignalee = true;

  /// Langue préférée de la reconnaissance, par langue de l'application.
  static const Map<String, String> _regionParDefaut = {
    'fr': 'fr_FR',
    'en': 'en_US',
    'es': 'es_ES',
    'de': 'de_DE',
  };

  @override
  Future<ErreurDictee?> preparer() async {
    try {
      final pret = await _stt.initialize(onError: _surErreur, onStatus: _surStatut);
      // `initialize` ne pose ses écouteurs qu'au PREMIER succès, et l'instance
      // est partagée : on les repose à chaque préparation.
      _stt.errorListener = _surErreur;
      _stt.statusListener = _surStatut;
      if (pret) return null;
      // Échec : micro refusé, ou aucun service de reconnaissance.
      return await _stt.hasPermission ? ErreurDictee.indisponible : ErreurDictee.microRefuse;
    } catch (_) {
      return ErreurDictee.indisponible;
    }
  }

  @override
  Future<void> ecouter({
    required String langue,
    required void Function(String texte, bool definitif) surResultat,
    required void Function(ErreurDictee? erreur) surFin,
  }) async {
    _surFin = surFin;
    _finSignalee = false;
    final localeId = await _localePour(langue);
    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) => surResultat(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          autoPunctuation: true,
          localeId: localeId,
          // Une observation se dicte d'une traite : 4 s de silence closent la
          // prise, 2 minutes au plus.
          pauseFor: const Duration(seconds: 4),
          listenFor: const Duration(minutes: 2),
        ),
      );
    } catch (_) {
      _terminer(ErreurDictee.interrompue);
    }
  }

  @override
  Future<void> arreter() => _stt.stop();

  @override
  Future<void> annuler() async {
    _finSignalee = true;
    await _stt.cancel();
  }

  /// Identifiant de langue du service le plus proche de [langue] ; `null`
  /// (langue du système) si le service n'en propose aucune.
  Future<String?> _localePour(String langue) async {
    try {
      final code = langue.toLowerCase().split(RegExp('[-_]')).first;
      final disponibles = (await _stt.locales()).map((l) => l.localeId).toList();
      String canon(String id) => id.toLowerCase().replaceAll('-', '_');
      final prefere = _regionParDefaut[code];
      for (final id in disponibles) {
        if (prefere != null && canon(id) == prefere.toLowerCase()) return id;
      }
      for (final id in disponibles) {
        if (canon(id).startsWith(code)) return id;
      }
    } catch (_) {
      // Liste des langues indisponible : la langue du système fera l'affaire.
    }
    return null;
  }

  void _surErreur(SpeechRecognitionError erreur) => _terminer(erreurDicteeDepuisCode(erreur.errorMsg));

  void _surStatut(String statut) {
    if (statut == SpeechToText.doneStatus) _terminer(null);
  }

  void _terminer(ErreurDictee? erreur) {
    if (_finSignalee) return;
    _finSignalee = true;
    _surFin?.call(erreur);
  }
}
