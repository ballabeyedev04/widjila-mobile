import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../errors/exceptions.dart';
import 'base_locale.dart';
import 'classification_erreur.dart';
import 'detecteur_connexion.dart';
import 'file_attente.dart';

/// Où en est la synchronisation — alimente le bandeau d'état.
enum EtatSynchro { repos, enCours, termine, echec }

/// Issue d'une tentative d'envoi UNIQUE — usage interne à
/// `SynchronisationService`, partagé entre la boucle automatique et la
/// synchronisation manuelle d'une tâche isolée (voir `_tenterAction`).
enum _ResultatAction { succes, coupureReseau, echecDefinitif, echecTemporaire }

/// Instantané de l'état hors ligne, consommé par l'interface.
@immutable
class StatutOffline {
  final EtatReseau reseau;
  final EtatSynchro synchro;

  /// Actions faites hors ligne, pas encore envoyées.
  final int enAttente;

  /// Actions refusées par le serveur pour une raison métier.
  final int enEchec;

  const StatutOffline({
    this.reseau = EtatReseau.inconnu,
    this.synchro = EtatSynchro.repos,
    this.enAttente = 0,
    this.enEchec = 0,
  });

  bool get estHorsLigne => reseau == EtatReseau.horsLigne;
  bool get aDuTravailEnAttente => enAttente > 0;

  StatutOffline copyWith({
    EtatReseau? reseau,
    EtatSynchro? synchro,
    int? enAttente,
    int? enEchec,
  }) =>
      StatutOffline(
        reseau: reseau ?? this.reseau,
        synchro: synchro ?? this.synchro,
        enAttente: enAttente ?? this.enAttente,
        enEchec: enEchec ?? this.enEchec,
      );
}

/// Rejoue la file d'attente dès que le réseau revient — SANS action de
/// l'utilisateur.
///
/// ## Déclencheurs (tous automatiques)
///
///  1. le réseau repasse en ligne ([DetecteurConnexion.flux]) ;
///  2. l'application revient au premier plan ;
///  3. une action vient d'être déposée alors qu'on est déjà en ligne.
///
/// Aucun bouton « réessayer » n'est nécessaire : l'utilisateur pose son
/// action et l'oublie. Une méthode manuelle existe malgré tout
/// ([synchroniser]), mais elle n'est là que pour les tests et un éventuel
/// geste de rafraîchissement — le fonctionnement nominal ne l'exige jamais.
///
/// ## Garanties
///
///  - **Ordre** : les actions partent dans leur ordre de création, ce qui
///    permet à une photo de suivre la réserve à laquelle elle se rattache.
///  - **Pas de doublon** : un verrou interne empêche deux passes simultanées
///    (le réseau peut « revenir » plusieurs fois en quelques secondes).
///  - **Idempotence** : les identifiants étant générés côté mobile, rejouer
///    une action déjà reçue par le serveur est sans effet (voir
///    `ReserveService.creerReserve`).
class SynchronisationService {
  final FileAttente _file;
  final DetecteurConnexion _detecteur;
  final BaseLocale _base;

  /// Exécute une action métier contre l'API. Injecté plutôt que codé ici :
  /// ce service ne connaît rien aux réserves, il orchestre seulement.
  final Future<void> Function(ActionEnAttente action) _executer;

  // Champs privés, paramètres publics : les appelants écrivent
  // `SynchronisationService(file: ...)`. Utiliser `this._file` en paramètre,
  // comme le suggère la règle, imposerait le préfixe souligne à chaque site
  // d'appel — une fuite de détail interne dans l'API publique.
  // ignore_for_file: prefer_initializing_formals
  SynchronisationService({
    required FileAttente file,
    required DetecteurConnexion detecteur,
    required BaseLocale base,
    required Future<void> Function(ActionEnAttente action) executer,
  })  : _file = file,
        _detecteur = detecteur,
        _base = base,
        _executer = executer;

  final _statut = ValueNotifier<StatutOffline>(const StatutOffline());

  /// État observable par l'interface (bandeau).
  ValueListenable<StatutOffline> get statut => _statut;

  StreamSubscription<EtatReseau>? _abonnementReseau;

  /// Verrou anti-concurrence : sans lui, un réseau instable qui bascule
  /// plusieurs fois lancerait des passes parallèles, et la même action
  /// partirait deux fois.
  bool _enCours = false;

  Future<void> demarrer() async {
    _abonnementReseau = _detecteur.flux.listen((etat) {
      _statut.value = _statut.value.copyWith(reseau: etat);
      // LE déclencheur principal : le réseau revient, tout part.
      if (etat == EtatReseau.enLigne) {
        synchroniser();
      }
    });

    _statut.value = _statut.value.copyWith(reseau: _detecteur.etat);
    await rafraichirCompteurs();
    if (_detecteur.estEnLigne) await synchroniser();
  }

  /// Recompte les actions en attente et en échec.
  Future<void> rafraichirCompteurs() async {
    final enAttente = await _file.nombreEnAttente();
    final enEchec = await _file.nombreEnEchec();
    _statut.value = _statut.value.copyWith(enAttente: enAttente, enEchec: enEchec);
  }

  /// À appeler quand l'application revient au premier plan : l'utilisateur a
  /// pu retrouver du réseau pendant qu'elle était en arrière-plan, sans qu'un
  /// événement système ne l'ait signalé.
  Future<void> auRetourAuPremierPlan() async {
    final etat = await _detecteur.verifier();
    if (etat == EtatReseau.enLigne) await synchroniser();
  }

  /// Vide la file d'attente. Sans effet si déjà en cours ou hors ligne.
  ///
  /// Ne traite QUE les tâches en attente (voir `FileAttente.aTraiter`) — les
  /// échecs définitifs n'y repartent jamais tout seuls. C'est le
  /// comportement AUTOMATIQUE, déclenché par le réseau ; [synchroniserTout]
  /// et [synchroniserUne] sont les équivalents EXPLICITES, actionnés par
  /// l'utilisateur depuis l'écran des tâches, qui eux relancent aussi les
  /// échecs définitifs.
  Future<void> synchroniser() async {
    if (_enCours) return;
    if (!_detecteur.estEnLigne) return;

    // Le verrou est posé AVANT le premier `await`, et non après la lecture de
    // la file. Dart n'interrompt pas une fonction async avant son premier
    // `await` : poser le drapeau ici garantit que deux appels rapprochés (un
    // réseau qui bascule plusieurs fois en une seconde) ne peuvent pas lire
    // la même file et envoyer chaque action en double.
    _enCours = true;
    try {
      await _executerPasse();
    } finally {
      // `finally` : une exception inattendue ne doit jamais laisser le verrou
      // fermé, sinon plus aucune synchronisation ne repartirait de la session.
      _enCours = false;
    }
  }

  /// Geste EXPLICITE « Synchroniser tout » de l'écran des tâches : remet
  /// aussi les échecs définitifs en attente avant de lancer la passe — un
  /// clic délibéré de l'utilisateur vaut pour un nouvel essai de tout ce
  /// qu'il voit à l'écran, contrairement à [synchroniser] qui les ignore.
  ///
  /// Retourne `true` si la file est entièrement vidée (aucun échec restant).
  Future<bool> synchroniserTout() async {
    if (_enCours) return false;

    await _file.remettreToutEnAttente();
    await rafraichirCompteurs();

    if (!_detecteur.estEnLigne) return false;

    _enCours = true;
    try {
      await _executerPasse();
    } finally {
      _enCours = false;
    }
    return _statut.value.enAttente == 0 && _statut.value.enEchec == 0;
  }

  /// Geste EXPLICITE « Synchroniser » sur UNE tâche précise de l'écran des
  /// tâches. Partage le même verrou que [synchroniser]/[synchroniserTout] —
  /// un envoi individuel ne doit pas se chevaucher avec une passe globale,
  /// sous peine d'envoyer deux fois la même action.
  ///
  /// Retourne `true` si la tâche est partie avec succès (et donc retirée de
  /// la file). Ne lève jamais — un échec se lit dans la valeur de retour et
  /// dans `FileAttente.parId` (message d'erreur mis à jour), pas via une
  /// exception que l'écran devrait attraper.
  Future<bool> synchroniserUne(String id) async {
    if (_enCours) return false;

    final action = await _file.parId(id);
    if (action == null) return false;

    _enCours = true;
    try {
      if (action.estDefinitivementEnEchec) {
        await _file.remettreEnAttente(id);
      }
      final resultat = await _tenterAction(action);
      if (resultat == _ResultatAction.coupureReseau) {
        // Le détecteur doit repasser en « hors ligne » pour que le bandeau
        // rouge réapparaisse immédiatement, sans attendre le sondage — même
        // logique que dans `_executerPasse`.
        await _detecteur.verifier();
      }
      await rafraichirCompteurs();
      return resultat == _ResultatAction.succes;
    } finally {
      _enCours = false;
    }
  }

  Future<void> _executerPasse() async {
    final actions = await _file.aTraiter();
    if (actions.isEmpty) {
      await rafraichirCompteurs();
      // Rien à envoyer ET rien en échec : c'est l'état « tout est à jour »
      // qui autorise le nettoyage (voir `entretien` et `_nettoyerSiTermine`).
      await _nettoyerSiTermine();
      return;
    }

    _statut.value = _statut.value.copyWith(synchro: EtatSynchro.enCours);

    var interrompu = false;
    for (final action in actions) {
      final resultat = await _tenterAction(action);
      if (resultat == _ResultatAction.coupureReseau) {
        // Le réseau est retombé en pleine synchro : on s'arrête là et on
        // garde le reste pour la prochaine reconnexion. Continuer ferait
        // échouer chaque action une par une, gonflant leur compteur de
        // tentatives pour rien.
        interrompu = true;
        break;
      }
    }

    // Le verrou est relâché par le `finally` de `synchroniser()` — surtout pas
    // ici, sinon il retomberait à faux avant la fin réelle du traitement.
    await rafraichirCompteurs();
    _statut.value = _statut.value.copyWith(
      synchro: interrompu ? EtatSynchro.echec : EtatSynchro.termine,
    );

    if (interrompu) {
      // Le détecteur doit repasser en « hors ligne » pour que le bandeau
      // rouge réapparaisse immédiatement, sans attendre le sondage.
      await _detecteur.verifier();
    } else {
      // Passe allée à son terme SANS interruption réseau : si en plus il ne
      // reste ni tâche en attente ni tâche en échec, tout est confirmé par
      // le serveur — c'est le seul moment sûr pour le nettoyage.
      await _nettoyerSiTermine();
    }
  }

  /// Exécute UNE action et met à jour son statut en base selon le résultat.
  /// Centralise la classification d'erreur (réseau / session / refus
  /// métier / panne serveur), partagée par [_executerPasse] (boucle
  /// automatique) et [synchroniserUne] (tentative isolée) — sans ce partage,
  /// les deux chemins finiraient inévitablement par diverger sur ce qui
  /// compte comme « à retenter » vs « abandonner ».
  Future<_ResultatAction> _tenterAction(ActionEnAttente action) async {
    try {
      await _executer(action);
      await _file.supprimer(action.id);
      return _ResultatAction.succes;
    } on NetworkException catch (_) {
      // Cas RÉEL en production : `ReserveRemoteDataSourceImpl` (et tout
      // datasource passant par `mapDioException`) convertit déjà la
      // `DioException` en `NetworkException` avant qu'elle n'atteigne ce
      // service — c'est donc CE type qu'il faut attraper ici, pas
      // `DioException` (voir la clause dédiée plus bas, gardée pour un
      // appelant qui lèverait une `DioException` brute, en test notamment).
      await _file.marquerEchecTemporaire(action.id, 'Connexion perdue');
      return _ResultatAction.coupureReseau;
    } on UnauthorizedException catch (e) {
      // Le rafraîchissement silencieux du jeton (voir dio_client_factory.dart)
      // a déjà échoué à ce stade. Rester en attente et non en échec
      // définitif : une reconnexion de l'utilisateur suffira à débloquer
      // l'action, inutile de la faire disparaître de la file.
      await _file.marquerEchecTemporaire(action.id, e.message);
      return _ResultatAction.echecTemporaire;
    } on ServerException catch (e) {
      final code = e.statusCode;
      if (code != null && code >= 400 && code < 500) {
        // 4xx : le serveur a compris et refuse (chantier supprimé, droits
        // retirés). Retenter indéfiniment ne changerait rien et bloquerait
        // la file derrière cette action.
        await _file.marquerEchecDefinitif(action.id, e.message);
        return _ResultatAction.echecDefinitif;
      }
      // 5xx ou statut indéterminé : la faute peut être passagère côté
      // serveur, on retentera.
      await _file.marquerEchecTemporaire(action.id, e.message);
      return _ResultatAction.echecTemporaire;
    } on DioException catch (e) {
      // Filet de sécurité : un `executer` qui laisserait fuir une
      // `DioException` brute (au lieu de la faire passer par
      // `mapDioException`, comme un test qui simule directement l'appel
      // réseau) est classé avec la même règle que ci-dessus.
      if (estCoupureReseau(e)) {
        await _file.marquerEchecTemporaire(action.id, 'Connexion perdue');
        return _ResultatAction.coupureReseau;
      }
      if (_estRefusMetier(e)) {
        await _file.marquerEchecDefinitif(action.id, _messageErreur(e));
        return _ResultatAction.echecDefinitif;
      }
      await _file.marquerEchecTemporaire(action.id, _messageErreur(e));
      return _ResultatAction.echecTemporaire;
    } catch (e) {
      await _file.marquerEchecTemporaire(action.id, e.toString());
      return _ResultatAction.echecTemporaire;
    }
  }

  /// Nettoyage sécurisé — voir `BaseLocale.purgerCacheAncien` pour la garantie
  /// qu'il n'est JAMAIS question des données pas encore envoyées (la colonne
  /// `en_attente` les exclut explicitement, quel que soit leur âge). Appelé
  /// UNIQUEMENT quand une passe se termine avec la file totalement vidée ET
  /// aucun échec restant — jamais après une interruption ni un échec, jamais
  /// « juste au cas où ».
  Future<void> _nettoyerSiTermine() async {
    if (_statut.value.enAttente == 0 && _statut.value.enEchec == 0) {
      await entretien();
    }
  }

  /// 4xx = refus compris par le serveur.
  ///
  /// 401 est EXCLU volontairement : l'intercepteur Dio rafraîchit le jeton et
  /// rejoue la requête. Si le rafraîchissement échoue vraiment, la session est
  /// terminée — l'action doit rester en attente pour repartir après une
  /// reconnexion, surtout pas être marquée définitivement perdue.
  static bool _estRefusMetier(DioException e) {
    final code = e.response?.statusCode;
    if (code == null) return false;
    if (code == 401) return false;
    return code >= 400 && code < 500;
  }

  static String _messageErreur(DioException e) {
    final donnees = e.response?.data;
    if (donnees is Map && donnees['message'] is String) return donnees['message'] as String;
    return e.message ?? 'Erreur inconnue';
  }

  /// Purge le cache ancien — appelé au démarrage, hors du chemin critique.
  Future<void> entretien() => _base.purgerCacheAncien();

  Future<void> arreter() async {
    await _abonnementReseau?.cancel();
    _statut.dispose();
  }
}
