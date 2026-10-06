import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Pourquoi une vérification a été REFUSÉE hors ligne.
enum RefusHorsLigne {
  /// Aucun compte n'a jamais été authentifié par le serveur sur cet appareil
  /// (première utilisation, déconnexion volontaire, compte avec second
  /// facteur…). Seule une connexion Internet peut alors ouvrir une session.
  aucunCompte,

  /// Identifiant ou mot de passe qui ne correspond pas. Volontairement
  /// indistinct : on ne révèle pas quel compte vit sur l'appareil.
  identifiantsInvalides,

  /// Trop d'essais ratés d'affilée — attendre [ResultatVerification.attente].
  verrouille,

  /// Le serveur n'a pas confirmé ce compte depuis trop longtemps.
  expire,

  /// L'heure de l'appareil est antérieure à une heure déjà observée : retour
  /// en arrière du réglage horaire, seul moyen de prolonger la fenêtre
  /// d'expiration.
  horlogeIncoherente,
}

class ResultatVerification {
  /// Compte reconnu — `null` en cas de refus.
  final String? utilisateurId;
  final RefusHorsLigne? refus;

  /// Délai restant avant de pouvoir réessayer (refus [RefusHorsLigne.verrouille]).
  final Duration? attente;

  const ResultatVerification.accepte(String id)
      : utilisateurId = id,
        refus = null,
        attente = null;

  const ResultatVerification.refuse(RefusHorsLigne this.refus, {this.attente}) : utilisateurId = null;

  bool get accepte => utilisateurId != null;
}

/// Preuve locale qu'un compte a DÉJÀ été authentifié par le serveur sur cet
/// appareil — ce qui, seul, autorise une connexion sans réseau.
///
/// ## Ce que ce service n'est PAS
///
/// Ce n'est pas un mode « hors ligne = connecté ». Le serveur reste l'unique
/// autorité : l'enregistrement n'est écrit qu'APRÈS une authentification
/// serveur réussie ([enregistrer]), et il ne sert qu'à rouvrir l'application
/// pour consulter le cache et saisir des relevés. Une session ouverte ainsi
/// ne détient AUCUN jeton : rien ne part vers le serveur tant que l'utilisateur
/// ne s'est pas réauthentifié en ligne.
///
/// ## Ce qui est stocké
///
/// Jamais le mot de passe : un condensat PBKDF2-HMAC-SHA256 salé (sel aléatoire
/// de 16 octets, nombre d'itérations conservé avec l'enregistrement pour
/// pouvoir le relever plus tard), dans le stockage sécurisé de la plateforme
/// (Keystore Android / Trousseau iOS), lié à l'appareil.
///
/// ## Garde-fous
///
///  - **Limitation des essais** : à partir du 3e échec consécutif, délai
///    croissant (5 s, 10 s, 20 s… plafonné à 15 min), persistant — relancer
///    l'application ne remet rien à zéro. Au 10e échec, l'enregistrement est
///    EFFACÉ : seule une connexion en ligne peut alors rouvrir l'accès.
///  - **Péremption** : [validite] sans confirmation du serveur (connexion ou
///    restauration de session réussie) et l'accès hors ligne se ferme.
///  - **Horloge** : la plus grande heure déjà observée est mémorisée ; une
///    heure antérieure (moins la tolérance) refuse la connexion.
///  - **Comparaison à temps constant** du condensat.
///  - **Un seul compte par appareil** : un nouvel enregistrement remplace le
///    précédent (cohérent avec `SessionLocale`, propriétaire unique des
///    données locales).
class VerificateurHorsLigne {
  final FlutterSecureStorage _stockage;
  final DateTime Function() _maintenant;
  final int _iterations;
  final Duration validite;

  VerificateurHorsLigne({
    required FlutterSecureStorage secureStorage,
    DateTime Function()? maintenant,
    int iterations = iterationsParDefaut,
    this.validite = const Duration(days: 14),
  })  : _stockage = secureStorage,
        _maintenant = maintenant ?? DateTime.now,
        _iterations = iterations;

  static const _cle = 'sc_verifieur_hors_ligne';

  /// Recommandation OWASP 2023 pour PBKDF2-HMAC-SHA256 : 600 000. On reste
  /// plus bas car le calcul tourne en Dart pur sur des téléphones de chantier
  /// d'entrée de gamme ; la protection principale est le stockage sécurisé de
  /// l'appareil plus le plafond d'essais — le condensat n'est jamais exposé.
  static const iterationsParDefaut = 150000;

  static const _toleranceHorloge = Duration(minutes: 10);
  static const _essaisSansDelai = 2;
  static const _essaisAvantEffacement = 10;
  static const _delaiMax = Duration(minutes: 15);

  /// Forme canonique d'un identifiant : casse et espaces ne distinguent pas
  /// deux saisies d'un même compte.
  static String normaliser(String identifiant) => identifiant.trim().toLowerCase();

  // ── Écriture ────────────────────────────────────────────────────────────

  /// Enregistre la preuve d'un compte que le SERVEUR vient d'authentifier.
  ///
  /// [identifiants] : tout ce que l'utilisateur pourra saisir pour se
  /// connecter (ce qu'il a tapé, l'email du profil…).
  Future<void> enregistrer({
    required String utilisateurId,
    required Iterable<String> identifiants,
    required String motDePasse,
  }) async {
    final sel = _octetsAleatoires(16);
    final condensat = await _condenser(motDePasse, sel, _iterations);
    final maintenant = _maintenant().millisecondsSinceEpoch;
    await _ecrire(_Enregistrement(
      utilisateurId: utilisateurId,
      identifiants: identifiants.map(normaliser).where((i) => i.isNotEmpty).toSet().toList(),
      sel: sel,
      condensat: condensat,
      iterations: _iterations,
      valideLe: maintenant,
      vuLe: maintenant,
      echecs: 0,
      bloqueJusqua: 0,
    ));
  }

  /// Le serveur vient de reconfirmer ce compte (restauration de session
  /// réussie) : la fenêtre de validité repart de zéro.
  Future<void> marquerValide(String utilisateurId) async {
    final e = await _lire();
    if (e == null || e.utilisateurId != utilisateurId) return;
    final maintenant = _maintenant().millisecondsSinceEpoch;
    await _ecrire(e.copie(valideLe: maintenant, vuLe: max(e.vuLe, maintenant)));
  }

  Future<void> effacer() async {
    try {
      await _stockage.delete(key: _cle);
    } catch (e) {
      debugPrint('[hors-ligne] Effacement du vérificateur impossible : $e');
    }
  }

  // ── Lecture ─────────────────────────────────────────────────────────────

  /// Un compte est-il connu de l'appareil ? Sert à adapter le message quand
  /// le réseau manque, sans rien vérifier.
  Future<bool> get aUnCompte async => await _lire() != null;

  Future<ResultatVerification> verifier({
    required String identifiant,
    required String motDePasse,
  }) async {
    final e = await _lire();
    if (e == null) return const ResultatVerification.refuse(RefusHorsLigne.aucunCompte);

    final maintenantDt = _maintenant();
    final maintenant = maintenantDt.millisecondsSinceEpoch;

    // 1. Verrou d'essais — avant tout calcul coûteux.
    if (e.bloqueJusqua > maintenant) {
      return ResultatVerification.refuse(
        RefusHorsLigne.verrouille,
        attente: Duration(milliseconds: e.bloqueJusqua - maintenant),
      );
    }

    // 2. Horloge. Une heure en retard sur la plus grande heure déjà vue ne
    //    peut venir que d'un réglage manuel : on refuse plutôt que de laisser
    //    la fenêtre de péremption se prolonger.
    if (maintenant < e.vuLe - _toleranceHorloge.inMilliseconds) {
      return const ResultatVerification.refuse(RefusHorsLigne.horlogeIncoherente);
    }

    // 3. Péremption.
    if (maintenant - e.valideLe > validite.inMilliseconds) {
      return const ResultatVerification.refuse(RefusHorsLigne.expire);
    }

    // 4. Condensat TOUJOURS calculé, même si l'identifiant ne correspond pas :
    //    le temps de réponse ne dit pas lequel des deux champs était faux.
    final condensat = await _condenser(motDePasse, e.sel, e.iterations);
    final identifiantOk = e.identifiants.contains(normaliser(identifiant));
    final ok = _egalConstant(condensat, e.condensat) && identifiantOk;

    if (ok) {
      await _ecrire(e.copie(echecs: 0, bloqueJusqua: 0, vuLe: max(e.vuLe, maintenant)));
      return ResultatVerification.accepte(e.utilisateurId);
    }

    final echecs = e.echecs + 1;
    if (echecs >= _essaisAvantEffacement) {
      await effacer();
      return const ResultatVerification.refuse(RefusHorsLigne.aucunCompte);
    }
    final delai = echecs <= _essaisSansDelai
        ? Duration.zero
        : Duration(seconds: 5 * (1 << (echecs - _essaisSansDelai - 1)));
    final borne = delai > _delaiMax ? _delaiMax : delai;
    await _ecrire(e.copie(
      echecs: echecs,
      bloqueJusqua: borne == Duration.zero ? 0 : maintenant + borne.inMilliseconds,
      vuLe: max(e.vuLe, maintenant),
    ));
    return borne == Duration.zero
        ? const ResultatVerification.refuse(RefusHorsLigne.identifiantsInvalides)
        : ResultatVerification.refuse(RefusHorsLigne.verrouille, attente: borne);
  }

  // ── Interne ─────────────────────────────────────────────────────────────

  Future<_Enregistrement?> _lire() async {
    try {
      final brut = await _stockage.read(key: _cle);
      if (brut == null || brut.isEmpty) return null;
      return _Enregistrement.depuisJson(jsonDecode(brut) as Map<String, dynamic>);
    } catch (e) {
      // Illisible ou corrompu : traité comme absent. Refuser l'accès hors
      // ligne est le côté sûr de l'erreur.
      debugPrint('[hors-ligne] Enregistrement illisible, ignoré : $e');
      await effacer();
      return null;
    }
  }

  Future<void> _ecrire(_Enregistrement e) async {
    await _stockage.write(key: _cle, value: jsonEncode(e.toJson()));
  }

  static Uint8List _octetsAleatoires(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  /// PBKDF2 hors du fil d'interface : 150 000 itérations de HMAC bloqueraient
  /// l'écran de connexion plusieurs centaines de millisecondes.
  static Future<Uint8List> _condenser(String motDePasse, Uint8List sel, int iterations) {
    return compute(_pbkdf2, _ParametresKdf(utf8.encode(motDePasse), sel, iterations));
  }

  static bool _egalConstant(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _ParametresKdf {
  final List<int> motDePasse;
  final Uint8List sel;
  final int iterations;
  const _ParametresKdf(this.motDePasse, this.sel, this.iterations);
}

/// PBKDF2-HMAC-SHA256, un seul bloc (32 octets) — RFC 8018 §5.2.
Uint8List _pbkdf2(_ParametresKdf p) {
  final hmac = Hmac(sha256, p.motDePasse);
  var u = hmac.convert([...p.sel, 0, 0, 0, 1]).bytes;
  final t = List<int>.from(u);
  for (var i = 1; i < p.iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return Uint8List.fromList(t);
}

class _Enregistrement {
  final String utilisateurId;
  final List<String> identifiants;
  final Uint8List sel;
  final Uint8List condensat;
  final int iterations;
  final int valideLe;
  final int vuLe;
  final int echecs;
  final int bloqueJusqua;

  const _Enregistrement({
    required this.utilisateurId,
    required this.identifiants,
    required this.sel,
    required this.condensat,
    required this.iterations,
    required this.valideLe,
    required this.vuLe,
    required this.echecs,
    required this.bloqueJusqua,
  });

  _Enregistrement copie({int? valideLe, int? vuLe, int? echecs, int? bloqueJusqua}) => _Enregistrement(
        utilisateurId: utilisateurId,
        identifiants: identifiants,
        sel: sel,
        condensat: condensat,
        iterations: iterations,
        valideLe: valideLe ?? this.valideLe,
        vuLe: vuLe ?? this.vuLe,
        echecs: echecs ?? this.echecs,
        bloqueJusqua: bloqueJusqua ?? this.bloqueJusqua,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'uid': utilisateurId,
        'ids': identifiants,
        'sel': base64Encode(sel),
        'h': base64Encode(condensat),
        'it': iterations,
        'valide': valideLe,
        'vu': vuLe,
        'echecs': echecs,
        'bloque': bloqueJusqua,
      };

  factory _Enregistrement.depuisJson(Map<String, dynamic> j) {
    if (j['v'] != 1) throw const FormatException('version inconnue');
    return _Enregistrement(
      utilisateurId: j['uid'] as String,
      identifiants: (j['ids'] as List).cast<String>(),
      sel: base64Decode(j['sel'] as String),
      condensat: base64Decode(j['h'] as String),
      iterations: j['it'] as int,
      valideLe: j['valide'] as int,
      vuLe: j['vu'] as int,
      echecs: j['echecs'] as int,
      bloqueJusqua: j['bloque'] as int,
    );
  }
}
