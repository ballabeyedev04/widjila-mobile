import 'dart:async';
import 'dart:io' show FileSystemException;

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
enum _ResultatAction {
  succes,

  /// Le réseau est tombé : inutile d'enchaîner, tout échouerait pareil.
  coupureReseau,

  /// Le SERVEUR demande d'attendre : limite de débit (429), session à
  /// renouveler (401), abonnement suspendu. Toutes les actions suivantes
  /// recevraient la même réponse — la passe s'arrête, la file est gardée
  /// intacte, une relance est planifiée.
  suspendu,

  echecDefinitif,
  echecTemporaire,
}

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
///  3. une action vient d'être déposée alors qu'on est déjà en ligne
///     ([FileAttente.depots]) ;
///  4. une RELANCE planifiée après un échec passager (panne serveur, limite de
///     débit), avec un délai croissant ([delaisRelanceParDefaut]).
///
/// Sans le 4ᵉ, un appareil resté « en ligne » pendant une panne serveur ne
/// retentait plus rien : aucun événement réseau ne venait relancer la file,
/// qui restait bloquée jusqu'au prochain passage en arrière-plan.
///
/// ## Garanties
///
///  - **Ordre** : les actions partent dans leur ordre de création, ce qui
///    permet à une photo de suivre la réserve à laquelle elle se rattache.
///  - **Dépendances** : une action dont une action PRÉCÉDENTE sur la même
///    entité n'a pas abouti n'est pas tentée (voir [ActionEnAttente.cleEntite])
///    — sinon la photo d'une réserve pas encore créée partait en 404 et était
///    grillée en échec définitif.
///  - **Pas de doublon** : un verrou interne empêche deux passes simultanées
///    (le réseau peut « revenir » plusieurs fois en quelques secondes).
///  - **Idempotence** : les identifiants étant générés côté mobile, rejouer
///    une action déjà reçue par le serveur est sans effet (voir
///    `ReserveService.creerReserve`, `changerStatut`, `MediaService` et
///    l'en-tête `Idempotency-Key` de l'envoi de rapport).
///  - **Rien n'est jeté pour une raison passagère** : 408, 425, 429, 401, 5xx,
///    abonnement suspendu et coupure réseau laissent l'action en file. Seul un
///    refus MÉTIER (4xx compris par le serveur) ou une action localement
///    impossible ([ActionInvalide], fichier disparu) la sort du cycle.
class SynchronisationService {
  final FileAttente _file;
  final DetecteurConnexion _detecteur;
  final BaseLocale _base;

  /// Exécute une action métier contre l'API. Injecté plutôt que codé ici :
  /// ce service ne connaît rien aux réserves, il orchestre seulement.
  final Future<void> Function(ActionEnAttente action) _executer;

  /// Défait l'écriture OPTIMISTE d'une action DÉFINITIVEMENT refusée.
  ///
  /// Symétrique de [_executer], et injectée pour la même raison : ce service
  /// ne sait pas ce qu'une action a écrit en local, seulement qu'elle a échoué
  /// sans appel.
  ///
  /// Sans elle, un refus serveur (transition illégale, preuves manquantes,
  /// droits retirés) laissait la base locale sur la valeur demandée par
  /// l'utilisateur — et `CacheReserves.enregistrerTous`, qui épargne les
  /// lignes « en attente », empêchait ensuite toute correction par le serveur.
  /// L'écran affichait indéfiniment un état que le serveur avait rejeté.
  ///
  /// Facultative : un appelant qui n'a rien à défaire n'a pas à la fournir.
  final Future<void> Function(ActionEnAttente action)? _annuler;

  /// Tirage des changements SERVEUR (voir `TirageReserves`), après une passe
  /// d'envoi aboutie. Facultatif.
  final Future<void> Function()? _tirer;

  final List<Duration> _delaisRelance;
  final Duration _delaiApresDepot;

  /// Délais de relance après un échec passager : 5 s, 15 s, 30 s, 1 min,
  /// 2 min, puis 5 min tant que l'échec dure. Remis à zéro dès qu'une passe
  /// aboutit sans échec.
  static const List<Duration> delaisRelanceParDefaut = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

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
    Future<void> Function(ActionEnAttente action)? annuler,
    Future<void> Function()? tirer,
    List<Duration> delaisRelance = delaisRelanceParDefaut,
    Duration delaiApresDepot = const Duration(milliseconds: 400),
  })  : _file = file,
        _detecteur = detecteur,
        _base = base,
        _executer = executer,
        _annuler = annuler,
        _tirer = tirer,
        _delaisRelance = delaisRelance,
        _delaiApresDepot = delaiApresDepot;

  final _statut = ValueNotifier<StatutOffline>(const StatutOffline());

  /// État observable par l'interface (bandeau).
  ValueListenable<StatutOffline> get statut => _statut;

  StreamSubscription<EtatReseau>? _abonnementReseau;
  StreamSubscription<void>? _abonnementDepots;

  /// Verrou anti-concurrence : sans lui, un réseau instable qui bascule
  /// plusieurs fois lancerait des passes parallèles, et la même action
  /// partirait deux fois.
  bool _enCours = false;

  /// Passe en cours, pour qu'[arreter] puisse l'attendre au lieu de fermer
  /// l'état sous ses pieds.
  Future<void>? _passeEnCours;

  /// Un déclencheur est arrivé PENDANT une passe : la file a pu recevoir une
  /// action que cette passe n'a pas lue. Une passe de plus est donc planifiée
  /// à la fin, au lieu de perdre le déclencheur.
  bool _passeDemandee = false;

  Timer? _relance;
  DateTime? _echeanceRelance;
  int _niveauRelance = 0;
  bool _arrete = false;

  String? _derniereErreurTirage;

  /// Dernier échec du tirage des changements serveur, `null` si le dernier a
  /// abouti. Diagnostic : le tirage ne touche jamais la file d'attente.
  String? get derniereErreurTirage => _derniereErreurTirage;

  /// `true` si une relance automatique est planifiée (diagnostic et tests).
  bool get relancePlanifiee => _relance != null;

  Future<void> demarrer() async {
    _abonnementReseau = _detecteur.flux.listen((etat) {
      _publier((s) => s.copyWith(reseau: etat));
      // LE déclencheur principal : le réseau revient, tout part.
      if (etat == EtatReseau.enLigne) {
        synchroniser();
      }
    });
    _abonnementDepots = _file.depots.listen((_) {
      // Troisième déclencheur. Hors ligne, rien à faire : c'est le retour du
      // réseau qui prendra le relais. Un court délai regroupe les dépôts
      // rapprochés (plusieurs photos d'affilée) en une seule passe.
      unawaited(rafraichirCompteurs());
      if (_detecteur.estEnLigne) _planifier(_delaiApresDepot);
    });

    _publier((s) => s.copyWith(reseau: _detecteur.etat));
    await rafraichirCompteurs();
    if (_detecteur.estEnLigne) await synchroniser();
  }

  /// Recompte les actions en attente et en échec.
  Future<void> rafraichirCompteurs() async {
    if (_arrete) return;
    final enAttente = await _file.nombreEnAttente();
    final enEchec = await _file.nombreEnEchec();
    _publier((s) => s.copyWith(enAttente: enAttente, enEchec: enEchec));
  }

  /// À appeler quand l'application revient au premier plan : l'utilisateur a
  /// pu retrouver du réseau pendant qu'elle était en arrière-plan, sans qu'un
  /// événement système ne l'ait signalé.
  Future<void> auRetourAuPremierPlan() async {
    final etat = await _detecteur.verifier();
    if (etat == EtatReseau.enLigne) await synchroniser();
  }

  /// Vide la file d'attente. Sans effet si hors ligne ; si une passe est déjà
  /// en cours, en planifie une autre à sa suite plutôt que d'en lancer une
  /// seconde en parallèle.
  ///
  /// Ne traite QUE les tâches en attente (voir `FileAttente.aTraiter`) — les
  /// échecs définitifs n'y repartent jamais tout seuls. C'est le
  /// comportement AUTOMATIQUE, déclenché par le réseau ; [synchroniserTout]
  /// et [synchroniserUne] sont les équivalents EXPLICITES, actionnés par
  /// l'utilisateur depuis l'écran des tâches, qui eux relancent aussi les
  /// échecs définitifs.
  Future<void> synchroniser() {
    if (_arrete) return Future<void>.value();
    if (_enCours) {
      _passeDemandee = true;
      return _passeEnCours ?? Future<void>.value();
    }
    if (!_detecteur.estEnLigne) return Future<void>.value();

    // Le verrou est posé de façon SYNCHRONE, avant tout `await` : deux appels
    // rapprochés (un réseau qui bascule plusieurs fois en une seconde) ne
    // peuvent pas lire la même file et envoyer chaque action en double.
    _enCours = true;
    _annulerRelance();
    return _passeEnCours = _verrouiller(_executerPasse);
  }

  /// Geste EXPLICITE « Synchroniser tout » de l'écran des tâches : remet
  /// aussi les échecs définitifs en attente avant de lancer la passe — un
  /// clic délibéré de l'utilisateur vaut pour un nouvel essai de tout ce
  /// qu'il voit à l'écran, contrairement à [synchroniser] qui les ignore.
  ///
  /// Retourne `true` si la file est entièrement vidée (aucun échec restant).
  Future<bool> synchroniserTout() async {
    if (_enCours || _arrete) return false;
    // Verrou posé AVANT le premier `await` : la version précédente le posait
    // après la remise en attente, laissant une passe automatique démarrer
    // entre les deux — et la même action partir deux fois.
    _enCours = true;
    var enLigne = false;
    final passe = _verrouiller(() async {
      await _file.remettreToutEnAttente();
      await rafraichirCompteurs();
      enLigne = _detecteur.estEnLigne;
      if (!enLigne) return;
      _annulerRelance();
      await _executerPasse();
    });
    _passeEnCours = passe;
    await passe;
    return enLigne && _statut.value.enAttente == 0 && _statut.value.enEchec == 0;
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
  ///
  /// Refuse (retourne `false`) une tâche dont une tâche PRÉCÉDENTE sur la même
  /// entité n'est pas encore passée : envoyer la photo d'une réserve que le
  /// serveur ne connaît pas encore la grillerait en 404.
  Future<bool> synchroniserUne(String id) async {
    if (_enCours || _arrete) return false;
    _enCours = true;
    var resultat = _ResultatAction.echecTemporaire;
    final passe = _verrouiller(() async {
      final action = await _file.parId(id);
      if (action == null) return;
      final taches = await _file.toutesLesTaches();
      final bloquee = taches.any((a) =>
          a.id != action.id && a.cleEntite == action.cleEntite && a.creeLe.isBefore(action.creeLe));
      if (bloquee) return;

      if (action.estDefinitivementEnEchec) {
        await _file.remettreEnAttente(id);
      }
      resultat = await _tenterAction(action);
      if (resultat == _ResultatAction.coupureReseau) {
        // Le détecteur doit repasser en « hors ligne » pour que le bandeau
        // rouge réapparaisse immédiatement, sans attendre le sondage — même
        // logique que dans `_executerPasse`.
        await _detecteur.verifier();
      }
      await rafraichirCompteurs();
    });
    _passeEnCours = passe;
    await passe;
    return resultat == _ResultatAction.succes;
  }

  /// Exécute [corps] sous le verrou (déjà posé par l'appelant) et le relâche
  /// quoi qu'il arrive — une exception inattendue ne doit jamais laisser le
  /// verrou fermé, sinon plus aucune synchronisation ne repartirait.
  Future<void> _verrouiller(Future<void> Function() corps) async {
    try {
      await corps();
    } finally {
      _enCours = false;
      _passeEnCours = null;
      if (_passeDemandee && !_arrete) {
        _passeDemandee = false;
        _planifier(_delaiApresDepot);
      }
    }
  }

  Future<void> _executerPasse() async {
    final actions = await _file.aTraiter();
    if (actions.isEmpty) {
      _niveauRelance = 0;
      await rafraichirCompteurs();
      await _tirerChangements();
      // Rien à envoyer ET rien en échec : c'est l'état « tout est à jour »
      // qui autorise le nettoyage (voir `entretien` et `_nettoyerSiTermine`).
      await _nettoyerSiTermine();
      return;
    }

    _publier((s) => s.copyWith(synchro: EtatSynchro.enCours));

    var interrompu = false;
    var suspendu = false;
    var echecsPassagers = 0;
    // Entités dont une action n'a pas abouti pendant CETTE passe : leurs
    // actions suivantes attendent la prochaine.
    final bloquees = <String>{};

    for (final action in actions) {
      if (bloquees.contains(action.cleEntite)) continue;
      final resultat = await _tenterAction(action);
      if (resultat == _ResultatAction.coupureReseau) {
        // Le réseau est retombé en pleine synchro : on s'arrête là et on
        // garde le reste pour la prochaine reconnexion. Continuer ferait
        // échouer chaque action une par une, gonflant leur compteur de
        // tentatives pour rien.
        interrompu = true;
        break;
      }
      if (resultat == _ResultatAction.suspendu) {
        suspendu = true;
        break;
      }
      if (resultat != _ResultatAction.succes) {
        bloquees.add(action.cleEntite);
        if (resultat == _ResultatAction.echecTemporaire) echecsPassagers++;
      }
    }

    // Le verrou est relâché par `_verrouiller` — surtout pas ici, sinon il
    // retomberait à faux avant la fin réelle du traitement.
    await rafraichirCompteurs();
    _publier((s) => s.copyWith(
          synchro: interrompu || suspendu ? EtatSynchro.echec : EtatSynchro.termine,
        ));

    if (interrompu) {
      // Le détecteur doit repasser en « hors ligne » pour que le bandeau
      // rouge réapparaisse immédiatement, sans attendre le sondage.
      await _detecteur.verifier();
      // Appareil toujours « en ligne » (API injoignable derrière un réseau qui
      // fonctionne) : aucun événement réseau ne viendra relancer. La relance
      // planifiée, si.
      if (_detecteur.estEnLigne) _planifierRelance();
      return;
    }

    if (suspendu || echecsPassagers > 0) {
      _planifierRelance();
    } else {
      _niveauRelance = 0;
    }

    // Serveur qui demande d'attendre : ne pas l'accabler d'un tirage en plus.
    if (!suspendu) await _tirerChangements();

    // Passe allée à son terme SANS interruption réseau : si en plus il ne
    // reste ni tâche en attente ni tâche en échec, tout est confirmé par
    // le serveur — c'est le seul moment sûr pour le nettoyage.
    await _nettoyerSiTermine();
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
      _journaliser(action, 'envoyée');
      return _ResultatAction.succes;
    } on NetworkException catch (_) {
      // Cas RÉEL en production : `ReserveRemoteDataSourceImpl` (et tout
      // datasource passant par `mapDioException`) convertit déjà la
      // `DioException` en `NetworkException` avant qu'elle n'atteigne ce
      // service — c'est donc CE type qu'il faut attraper ici, pas
      // `DioException` (voir la clause dédiée plus bas, gardée pour un
      // appelant qui lèverait une `DioException` brute, en test notamment).
      return _appliquer(action, _ResultatAction.coupureReseau, 'Connexion perdue');
    } on UnauthorizedException catch (e) {
      // Le rafraîchissement silencieux du jeton (voir dio_client_factory.dart)
      // a déjà échoué à ce stade. Rester en attente et non en échec
      // définitif : une reconnexion de l'utilisateur suffira à débloquer
      // l'action, inutile de la faire disparaître de la file. La passe
      // s'arrête : toutes les suivantes recevraient le même 401.
      return _appliquer(action, _ResultatAction.suspendu, e.message);
    } on ServerException catch (e) {
      return _appliquer(action, _classerRefus(e.statusCode, e.code), e.message);
    } on DioException catch (e) {
      // Filet de sécurité : un `executer` qui laisserait fuir une
      // `DioException` brute (au lieu de la faire passer par
      // `mapDioException`, comme un test qui simule directement l'appel
      // réseau) est classé avec la même règle que ci-dessus.
      if (estCoupureReseau(e)) {
        return _appliquer(action, _ResultatAction.coupureReseau, 'Connexion perdue');
      }
      final donnees = e.response?.data;
      final code = donnees is Map && donnees['code'] is String ? donnees['code'] as String : null;
      return _appliquer(action, _classerRefus(e.response?.statusCode, code), _messageErreur(e));
    } on FileSystemException catch (e) {
      // Le fichier local (photo) a disparu : aucun rejeu ne le fera revenir.
      // L'ancienne version le retentait indéfiniment.
      return _appliquer(action, _ResultatAction.echecDefinitif, 'Fichier local introuvable : ${e.path ?? e.message}');
    } on ActionInvalide catch (e) {
      return _appliquer(action, _ResultatAction.echecDefinitif, e.message);
    } catch (e) {
      // Erreur inattendue : on NE la classe PAS en définitif — elle peut venir
      // de l'analyse d'une réponse pourtant réussie, et défaire l'écriture
      // locale serait alors une perte. Elle reste visible (message, compteur
      // de tentatives) dans l'écran des tâches.
      return _appliquer(action, _ResultatAction.echecTemporaire, e.toString());
    }
  }

  /// Enregistre l'issue d'un échec dans la file, et la renvoie.
  Future<_ResultatAction> _appliquer(ActionEnAttente action, _ResultatAction resultat, String message) async {
    if (resultat == _ResultatAction.echecDefinitif) {
      // 4xx : le serveur a compris et refuse (chantier supprimé, droits
      // retirés). Retenter indéfiniment ne changerait rien et bloquerait
      // la file derrière cette action.
      //
      // On DÉFAIT d'abord ce que l'action avait écrit en local : sans cela,
      // l'écriture optimiste survivait au refus, et la protection des lignes
      // « en attente » interdisait au serveur de la corriger ensuite.
      await _annuler?.call(action);
      await _file.marquerEchecDefinitif(action.id, message);
    } else {
      await _file.marquerEchecTemporaire(action.id, message);
    }
    _journaliser(action, resultat.name, message);
    return resultat;
  }

  /// Classe une réponse HTTP d'ÉCHEC.
  ///
  /// La version précédente traitait TOUT 4xx sauf 401 en refus définitif,
  /// ce qui envoyait au rebut — et faisait EFFACER en local — une réserve
  /// créée hors ligne sur un simple 429 (limite de débit : 300 requêtes par
  /// quart d'heure et par compte, vite atteinte en vidant une journée de
  /// relevés) ou sur un 408.
  static _ResultatAction _classerRefus(int? statut, String? code) {
    if (statut == null) return _ResultatAction.echecTemporaire;
    if (statut == 401 || statut == 429) return _ResultatAction.suspendu;
    // Abonnement expiré ou plafond atteint : le travail de terrain n'est pas
    // en cause. Il reste en file jusqu'au renouvellement au lieu d'être
    // effacé du téléphone.
    if (code != null && code.startsWith('SUBSCRIPTION_')) return _ResultatAction.suspendu;
    // « Déjà en cours de traitement » (envoi de rapport rejoué pendant que le
    // premier part encore) : la réponse viendra, il suffit de réessayer.
    if (code == 'ENVOI_EN_COURS') return _ResultatAction.echecTemporaire;
    if (statut == 408 || statut == 425) return _ResultatAction.echecTemporaire;
    if (statut >= 400 && statut < 500) return _ResultatAction.echecDefinitif;
    // 5xx : la faute peut être passagère côté serveur.
    return _ResultatAction.echecTemporaire;
  }

  /// Planifie la prochaine relance selon le palier courant, puis le monte.
  void _planifierRelance() {
    if (_delaisRelance.isEmpty) return;
    final palier = _niveauRelance < _delaisRelance.length ? _niveauRelance : _delaisRelance.length - 1;
    if (_niveauRelance < _delaisRelance.length) _niveauRelance++;
    _planifier(_delaisRelance[palier]);
  }

  /// Planifie une passe dans [delai] — sauf si une passe PLUS PROCHE est déjà
  /// prévue, qui couvrira celle-ci.
  void _planifier(Duration delai) {
    if (_arrete) return;
    final echeance = DateTime.now().add(delai);
    final prevue = _echeanceRelance;
    if (_relance != null && prevue != null && !prevue.isAfter(echeance)) return;
    _relance?.cancel();
    _echeanceRelance = echeance;
    _relance = Timer(delai, () {
      _relance = null;
      _echeanceRelance = null;
      unawaited(synchroniser());
    });
  }

  void _annulerRelance() {
    _relance?.cancel();
    _relance = null;
    _echeanceRelance = null;
  }

  /// Tire les changements serveur, sans jamais faire échouer la passe.
  ///
  /// Le tirage ne touche pas la file d'attente et n'avance son curseur
  /// qu'avec une page appliquée : son échec ne perd rien. Il est donc
  /// consigné ([derniereErreurTirage] + journal) et retenté à la passe
  /// suivante, plutôt que de faire croire à un échec de l'ENVOI.
  Future<void> _tirerChangements() async {
    final tirer = _tirer;
    if (tirer == null || _arrete || !_detecteur.estEnLigne) return;
    try {
      await tirer();
      _derniereErreurTirage = null;
    } catch (e) {
      _derniereErreurTirage = e.toString();
      debugPrint('[sync] Tirage des changements serveur échoué : $e');
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

  static String _messageErreur(DioException e) {
    final donnees = e.response?.data;
    if (donnees is Map && donnees['message'] is String) return donnees['message'] as String;
    return e.message ?? 'Erreur inconnue';
  }

  /// Trace d'une tentative — observabilité en développement. L'identifiant
  /// de l'action et l'entité suffisent à suivre une action d'un bout à
  /// l'autre sans journaliser le contenu saisi par l'utilisateur.
  void _journaliser(ActionEnAttente action, String issue, [String? detail]) {
    if (!kDebugMode) return;
    debugPrint('[sync] ${action.type.code} ${action.id} (${action.cleEntite}) → $issue'
        '${detail != null ? ' — $detail' : ''} [tentative ${action.tentatives + 1}]');
  }

  /// Publie un nouvel état — sans effet une fois le service arrêté (un
  /// `ValueNotifier` libéré lève à la moindre écriture).
  void _publier(StatutOffline Function(StatutOffline s) maj) {
    if (_arrete) return;
    _statut.value = maj(_statut.value);
  }

  /// Purge le cache ancien — appelé au démarrage, hors du chemin critique.
  Future<void> entretien() => _base.purgerCacheAncien();

  Future<void> arreter() async {
    _arrete = true;
    _annulerRelance();
    await _abonnementReseau?.cancel();
    await _abonnementDepots?.cancel();
    // Attendre la passe en vol plutôt que de libérer l'état sous ses pieds.
    // Son éventuelle erreur a déjà été remise à SON appelant : ici on attend
    // seulement sa fin.
    final enCours = _passeEnCours;
    if (enCours != null) await enCours.then((_) {}, onError: (Object _) {});
    _statut.dispose();
  }
}
