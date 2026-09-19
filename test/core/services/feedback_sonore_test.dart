import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/services/feedback_sonore.dart';

/// Un moteur audio qui note ce qu'on lui demande — et peut refuser.
class LecteurEspion implements LecteurSon {
  final List<String> joues = [];
  int precharges = 0;
  Object? panne;

  @override
  Future<void> precharger(String asset) async {
    precharges++;
    if (panne != null) throw panne!;
  }

  @override
  Future<void> jouer(String asset) async {
    if (panne != null) throw panne!;
    joues.add(asset);
  }
}

/// Le petit son de succès — ce que le service garantit à ceux qui l'appellent.
///
/// - un succès → un son, joué en tâche de fond ;
/// - un doublon (double appui, double émission d'état) à moins de 400 ms → un
///   seul son ;
/// - un moteur audio en panne (plugin absent, appareil muet) → aucune erreur
///   ne remonte à l'écran ;
/// - le préchargement ne se fait qu'une fois.
void main() {
  late LecteurEspion lecteur;
  late FeedbackSonore feedback;

  setUp(() {
    lecteur = LecteurEspion();
    feedback = FeedbackSonore(lecteur: lecteur);
  });

  test('un succès joue le son de succès, une fois', () async {
    feedback.succes();
    await Future<void>.delayed(Duration.zero);

    expect(lecteur.joues, [FeedbackSonore.assetSucces]);
  });

  test('deux appels rapprochés (double appui, double émission) → un seul son', () async {
    feedback.succes();
    feedback.succes();
    feedback.succes();
    await Future<void>.delayed(Duration.zero);

    expect(lecteur.joues, hasLength(1));
  });

  test('deux succès distincts, espacés → deux sons', () async {
    var instant = DateTime(2026, 9, 18, 12, 0, 0);
    feedback = FeedbackSonore(lecteur: lecteur, horloge: () => instant);

    feedback.succes();
    instant = instant.add(const Duration(milliseconds: 600));
    feedback.succes();
    await Future<void>.delayed(Duration.zero);

    expect(lecteur.joues, hasLength(2));
  });

  test('la garde anti-doublon est de 400 ms : à 399 ms c’est un doublon, à 400 ms non', () async {
    var instant = DateTime(2026, 9, 18, 12, 0, 0);
    feedback = FeedbackSonore(lecteur: lecteur, horloge: () => instant);

    feedback.succes();
    instant = instant.add(const Duration(milliseconds: 399));
    feedback.succes();
    await Future<void>.delayed(Duration.zero);
    expect(lecteur.joues, hasLength(1));

    instant = instant.add(const Duration(milliseconds: 1));
    feedback.succes();
    await Future<void>.delayed(Duration.zero);
    expect(lecteur.joues, hasLength(2));
  });

  test('ne bloque pas l’appelant : la lecture part en tâche de fond', () {
    // `succes()` est synchrone et rend la main immédiatement, même si le
    // moteur audio met du temps : la confirmation visuelle n'attend pas.
    final chrono = Stopwatch()..start();
    feedback.succes();
    chrono.stop();
    expect(chrono.elapsedMilliseconds, lessThan(50));
  });

  test('un moteur audio en panne ne fait pas échouer l’action', () async {
    lecteur.panne = StateError('MissingPluginException');

    expect(feedback.succes, returnsNormally);
    await Future<void>.delayed(Duration.zero);
    expect(lecteur.joues, isEmpty);
  });

  test('le préchargement ne se fait qu’une fois, et sa panne est silencieuse', () async {
    await feedback.precharger();
    await feedback.precharger();
    expect(lecteur.precharges, 1);

    final enPanne = FeedbackSonore(lecteur: LecteurEspion()..panne = Exception('asset absent'));
    await expectLater(enPanne.precharger(), completes);
  });

  test('`reinitialiser` lève la garde anti-doublon (tests)', () async {
    feedback.succes();
    feedback.reinitialiser();
    feedback.succes();
    await Future<void>.delayed(Duration.zero);

    expect(lecteur.joues, hasLength(2));
  });
}
