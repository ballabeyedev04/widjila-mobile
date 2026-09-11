import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/services/collecteur_erreurs.dart';

/// Destination d'essai : enregistre au lieu d'envoyer.
class _PuitsEspion implements PuitsErreurs {
  final List<Object> recues = [];
  final List<Map<String, Object?>> contextes = [];
  final List<String?> utilisateurs = [];

  @override
  void erreurFlutter(FlutterErrorDetails details) => recues.add(details.exception);

  @override
  void erreur(Object erreur, StackTrace? pile) => recues.add(erreur);

  @override
  void erreurNonFatale(Object erreur, StackTrace? pile, {String? raison, Map<String, Object?> contexte = const {}}) {
    recues.add(erreur);
    contextes.add({'raison': raison, ...contexte});
  }

  @override
  void identifierUtilisateur(String? id) => utilisateurs.add(id);
}

void main() {
  late CollecteurErreurs collecteur;
  late _PuitsEspion puits;

  setUp(() {
    collecteur = CollecteurErreurs();
    puits = _PuitsEspion();
  });

  test('les erreurs d’AVANT le branchement sont rejouées, dans l’ordre', () {
    // Le cœur du dispositif : c'est ce qui permet de ne plus attendre Firebase
    // avant `runApp` sans perdre les crashs de la fenêtre de démarrage — celle
    // où une config absente ou une migration ratée se manifestent.
    collecteur.differer((p) => p.erreur('avant-1', null));
    collecteur.differer((p) => p.erreur('avant-2', null));

    expect(puits.recues, isEmpty, reason: 'rien ne part tant que Firebase n’a pas répondu');
    expect(collecteur.enAttente, 2);
    expect(collecteur.estBranche, isFalse);

    collecteur.brancher(puits);

    expect(puits.recues, ['avant-1', 'avant-2']);
    expect(collecteur.enAttente, 0, reason: 'le tampon est vidé après rejeu');
    expect(collecteur.estBranche, isTrue);
  });

  test('après branchement, l’envoi est immédiat et ne passe plus par le tampon', () {
    collecteur.brancher(puits);
    collecteur.differer((p) => p.erreur('apres', null));

    expect(puits.recues, ['apres']);
    expect(collecteur.enAttente, 0);
  });

  test('le type d’erreur est préservé : framework vs hors framework', () {
    // `recordFlutterFatalError` produit un rapport plus riche que
    // `recordError` ; différer ne doit pas aplatir cette distinction.
    final details = FlutterErrorDetails(exception: 'framework');
    collecteur.differer((p) => p.erreurFlutter(details));
    collecteur.differer((p) => p.erreur('hors-framework', StackTrace.current));
    collecteur.brancher(puits);

    expect(puits.recues, ['framework', 'hors-framework']);
  });

  test('le tampon est borné — une erreur répétée à chaque image ne noie pas la mémoire', () {
    // Une erreur de construction se relève à CHAQUE image. Sans plafond, un
    // écran cassé au démarrage transformerait un bug d'affichage en panne
    // sèche par épuisement mémoire.
    final borne = CollecteurErreurs(tamponMax: 3);
    for (var i = 0; i < 500; i++) {
      borne.differer((p) => p.erreur('boucle-$i', null));
    }

    expect(borne.enAttente, 3);
    borne.brancher(puits);
    expect(puits.recues, ['boucle-0', 'boucle-1', 'boucle-2'],
        reason: 'on garde les PREMIÈRES — les plus proches de la cause');
  });

  test('abandonner() vide le tampon et ignore les erreurs suivantes', () {
    // Cas « pas de google-services.json » : ces erreurs ne partiront jamais,
    // les retenir ne ferait que consommer de la mémoire pour rien.
    collecteur.differer((p) => p.erreur('perdue', null));
    collecteur.abandonner();

    expect(collecteur.enAttente, 0);

    collecteur.differer((p) => p.erreur('ignorée', null));
    expect(collecteur.enAttente, 0);

    // Un branchement tardif ne ressuscite rien.
    collecteur.brancher(puits);
    expect(puits.recues, isEmpty);
    expect(collecteur.estBranche, isFalse);
  });

  group('erreurs non fatales', () {
    test('partent avec leur contexte (requestId, chemin, statut)', () {
      collecteur.brancher(puits);

      collecteur.signalerNonFatale(
        'boom',
        null,
        raison: 'Erreur serveur 500',
        contexte: {'requestId': 'abc-12345678', 'chemin': '/reserves', 'statut': 500},
      );

      expect(puits.recues, ['boom']);
      expect(puits.contextes.single, {
        'raison': 'Erreur serveur 500',
        'requestId': 'abc-12345678',
        'chemin': '/reserves',
        'statut': 500,
      });
    });

    test('la même erreur n’est signalée qu’une fois par minute — un écran qui réessaie ne noie pas Crashlytics', () {
      collecteur.brancher(puits);
      final t0 = DateTime(2026, 9, 11, 10);

      for (var i = 0; i < 30; i++) {
        collecteur.signalerNonFatale('boom', null,
            raison: 'Erreur serveur 503', contexte: {'chemin': '/health'}, maintenant: t0.add(Duration(seconds: i)));
      }
      collecteur.signalerNonFatale('boom', null,
          raison: 'Erreur serveur 503', contexte: {'chemin': '/health'}, maintenant: t0.add(const Duration(minutes: 2)));
      // Une erreur DIFFÉRENTE passe tout de suite.
      collecteur.signalerNonFatale('autre', null,
          raison: 'Erreur serveur 500', contexte: {'chemin': '/reserves'}, maintenant: t0.add(const Duration(seconds: 5)));

      // Ordre d'APPEL : les 30 « boom » (1 seul envoyé), le « boom » deux
      // minutes plus tard (renvoyé), puis « autre » (signature différente).
      expect(puits.recues, ['boom', 'boom', 'autre']);
    });

    test('retenues avant le branchement, comme les crashs', () {
      collecteur.signalerNonFatale('au démarrage', null, raison: 'test');
      expect(collecteur.enAttente, 1);

      collecteur.brancher(puits);
      expect(puits.recues, ['au démarrage']);
    });
  });

  test('identifierUtilisateur transmet l’identifiant, puis null à la déconnexion', () {
    collecteur.identifierUtilisateur('u-42');
    collecteur.brancher(puits);
    collecteur.identifierUtilisateur(null);

    expect(puits.utilisateurs, ['u-42', null]);
  });
}
