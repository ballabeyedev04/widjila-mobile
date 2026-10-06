import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/offline/session_locale.dart';
import '../../../../core/network/cache_reponses_get.dart';
import '../../../../core/services/token_service.dart';
import '../../../../core/services/user_cache.dart';
import '../../../../core/services/verificateur_hors_ligne.dart';
import '../../domain/entities/login_result.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final TokenService tokenService;
  final UserCache userCache;
  final SessionLocale sessionLocale;

  /// Cache memoire des reponses `GET` (30 s), a purger avec les jetons.
  ///
  /// La deconnexion est ENTIEREMENT LOCALE : aucune requete ne part, donc la
  /// purge automatique declenchee par toute ecriture (voir
  /// [CacheReponsesGet.onRequest]) ne s'execute jamais ici. Sans cette
  /// dependance, jusqu'a soixante reponses du compte precedent — tableau de
  /// bord, reserves, membres — restaient servibles pendant trente secondes au
  /// compte suivant. Les donnees SQLite et le cache utilisateur etaient deja
  /// purges juste a cote ; ce cache-ci manquait a la liste.
  final CacheReponsesGet cacheHttp;

  /// Preuve locale d'un compte déjà authentifié par le serveur — seule porte
  /// d'une connexion sans réseau. Voir `VerificateurHorsLigne`.
  final VerificateurHorsLigne verificateur;

  /// `true` quand la détection de connexion sait DÉJÀ le serveur injoignable.
  ///
  /// Évite d'attendre l'épuisement des délais et des relances du client HTTP
  /// (plus de 40 s sur un signal inexploitable) avant de proposer l'accès
  /// local. Ce n'est qu'un raccourci : si la vérification locale échoue, la
  /// requête réseau est quand même tentée, une sonde pouvant se tromper.
  final bool Function() serveurInjoignable;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.tokenService,
    required this.userCache,
    required this.sessionLocale,
    required this.cacheHttp,
    required this.verificateur,
    this.serveurInjoignable = _jamais,
  });

  static bool _jamais() => false;

  Future<void> _persisterSession(String? token, String? refreshToken, UserModel utilisateur) async {
    // ISOLATION ENTRE COMPTES — d'abord, et en échec FERMÉ.
    //
    // La déconnexion ne purge plus : les données du compte précédent (chantiers,
    // réserves, saisies en attente) survivent jusqu'ici, et c'est CETTE étape
    // qui les retire si le compte qui arrive est un AUTRE. Deux conséquences :
    //
    //  1. Elle passe AVANT l'enregistrement des jetons. Sinon, entre le jeton
    //     du nouveau compte et la purge, un retour du réseau suffirait à ce que
    //     la synchronisation automatique rejoue la file de l'ancien compte
    //     sous l'identité du nouveau (constats attribués à qui ne les a pas
    //     faits).
    //  2. Une purge qui échoue ou dépasse le délai INTERROMPT la connexion.
    //     Autrefois l'échec était ignoré parce que la déconnexion avait déjà
    //     purgé ; ce n'est plus vrai, poursuivre exposerait les données de
    //     l'ancien compte au nouveau. Aucun jeton n'est enregistré : réessayer
    //     est sans risque, et rien n'est perdu (le propriétaire n'est mis à
    //     jour qu'après une purge réussie).
    try {
      await sessionLocale.adopterUtilisateur(utilisateur.id).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[session] Isolation des données locales impossible ($e) — connexion interrompue.');
      throw const CacheException(
        message: "Impossible de préparer les données de ce compte sur l'appareil. Réessayez.",
      );
    }
    if (token != null) await tokenService.setToken(token);
    if (refreshToken != null) await tokenService.setRefreshToken(refreshToken);
    await userCache.saveJson(utilisateur.toJson());
  }

  @override
  Future<Either<Failure, LoginResult>> login({
    required String identifiant,
    required String motDePasse,
  }) async {
    // Serveur déjà connu pour injoignable : tenter l'accès local d'abord.
    Failure? refusLocal;
    if (serveurInjoignable()) {
      final local = await _connexionHorsLigne(identifiant, motDePasse);
      final reussite = local.fold((_) => null, (r) => r);
      if (reussite != null) return Right(reussite);
      refusLocal = local.fold((f) => f, (_) => null);
    }

    try {
      final response = await remoteDataSource.login(identifiant: identifiant, motDePasse: motDePasse);
      if (response.mfaRequise) {
        // Un second facteur ne se vérifie que sur le serveur : un compte qui
        // en exige un n'ouvre JAMAIS de session sans réseau (sinon le mot de
        // passe seul suffirait hors ligne). Tout enregistrement précédent est
        // effacé, il ne doit pas survivre à ce constat.
        await _effacerVerificateur();
      } else {
        await _persisterSession(response.token, response.refreshToken, response.utilisateur);
        await _enregistrerVerificateur(identifiant, motDePasse, response.utilisateur);
      }
      return Right(LoginResult(mfaRequise: response.mfaRequise, utilisateur: response.utilisateur));
    } on NetworkException {
      // SEUL le réseau absent ouvre l'accès local. Un refus du serveur
      // (mauvais mot de passe, compte désactivé…) est définitif : le serveur
      // a répondu, il fait foi, aucun repli.
      //
      // Déjà tenté plus haut (sonde « hors ligne ») : ne pas rejouer, et ne
      // pas masquer un refus précis derrière le message générique.
      if (refusLocal != null) return Left(refusLocal);
      return _connexionHorsLigne(identifiant, motDePasse);
    } catch (e) {
      // Compte suspendu / désactivé : l'accès local de ce compte est retiré.
      if (e is ServerException && e.statusCode == 403) await _effacerVerificateur();
      return Left(exceptionToFailure(e));
    }
  }

  static const _reseauRequis = 'Connexion Internet requise pour vous connecter sur cet appareil.';

  Future<void> _enregistrerVerificateur(String identifiant, String motDePasse, User utilisateur) async {
    // Best-effort : ne jamais empêcher une connexion en ligne réussie parce
    // que le stockage sécurisé a un souci. Sans enregistrement, la seule
    // conséquence est qu'une prochaine connexion sans réseau sera refusée.
    try {
      await verificateur.enregistrer(
        utilisateurId: utilisateur.id,
        identifiants: [identifiant, utilisateur.email],
        motDePasse: motDePasse,
      );
    } catch (e) {
      debugPrint('[session] Vérificateur hors ligne non enregistré ($e).');
      await _effacerVerificateur();
    }
  }

  Future<void> _effacerVerificateur() async {
    try {
      await verificateur.effacer();
    } catch (_) {}
  }

  /// Ouvre une session SANS serveur, uniquement si CE compte a déjà été
  /// authentifié par le serveur sur CET appareil (voir [VerificateurHorsLigne]).
  ///
  /// La session obtenue ne porte aucun jeton : elle donne accès au cache et à
  /// la saisie hors ligne, rien de plus. Aucune requête ne part tant que
  /// l'utilisateur ne s'est pas réauthentifié en ligne.
  Future<Either<Failure, LoginResult>> _connexionHorsLigne(String identifiant, String motDePasse) async {
    final ResultatVerification verdict;
    try {
      verdict = await verificateur.verifier(identifiant: identifiant, motDePasse: motDePasse);
    } catch (e) {
      debugPrint('[session] Vérification hors ligne indisponible ($e).');
      return const Left(NetworkFailure(errorMessage: _reseauRequis));
    }

    if (!verdict.accepte) {
      return Left(switch (verdict.refus!) {
        RefusHorsLigne.aucunCompte => const NetworkFailure(errorMessage: _reseauRequis),
        RefusHorsLigne.identifiantsInvalides =>
          const HorsLigneFailure(errorMessage: 'Identifiant ou mot de passe incorrect.'),
        RefusHorsLigne.verrouille => HorsLigneFailure(
            errorMessage: 'Trop de tentatives. Réessayez dans ${_formaterAttente(verdict.attente!)}, '
                'ou connectez-vous avec Internet.'),
        RefusHorsLigne.expire => const HorsLigneFailure(
            errorMessage: 'Votre accès hors ligne a expiré. Connectez-vous avec Internet pour le renouveler.'),
        RefusHorsLigne.horlogeIncoherente => const HorsLigneFailure(
            errorMessage: "L'heure de l'appareil est incohérente. Corrigez-la ou connectez-vous avec Internet."),
      });
    }

    final id = verdict.utilisateurId!;
    // Le profil vient du cache chiffré écrit lors de la dernière connexion
    // serveur ; il doit appartenir au compte vérifié.
    final Map<String, dynamic>? profil;
    try {
      profil = await userCache.readJson();
    } catch (_) {
      return const Left(NetworkFailure(errorMessage: _reseauRequis));
    }
    if (profil == null || profil['id'] != id) return const Left(NetworkFailure(errorMessage: _reseauRequis));
    final utilisateur = UserModel.fromJson(profil);
    if (utilisateur.statut != 'actif') return const Left(NetworkFailure(errorMessage: _reseauRequis));

    // Jamais de purge sans réseau : si les données locales sont à un AUTRE
    // compte, leur travail non synchronisé serait détruit sans recours.
    try {
      if (!await sessionLocale.estCompatible(id)) {
        return const Left(NetworkFailure(errorMessage: _reseauRequis));
      }
      await sessionLocale.adopterUtilisateur(id).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[session] Données locales indisponibles pour la connexion hors ligne ($e).');
      return const Left(NetworkFailure(errorMessage: _reseauRequis));
    }

    return Right(LoginResult(mfaRequise: false, utilisateur: utilisateur, horsLigne: true));
  }

  static String _formaterAttente(Duration d) {
    if (d.inMinutes >= 1) return '${d.inMinutes + (d.inSeconds % 60 > 0 ? 1 : 0)} min';
    return '${d.inSeconds + 1} s';
  }

  @override
  Future<Either<Failure, User>> verifierMfa({required String code}) async {
    try {
      final response = await remoteDataSource.verifierMfa(code: code);
      await _persisterSession(response.token, response.refreshToken, response.utilisateur);
      return Right(response.utilisateur);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, User>> register({
    required String nom,
    required String prenom,
    required String email,
    required String motDePasse,
    String? telephone,
    String? fonction,
    String? organisationNom,
    String? raisonSociale,
    /// Identifiants d'entreprise, indexés par la clé attendue par le serveur
    /// (`siret`, `ninea`, `nif`, `ncc`, `idu`, `rccm`, `num_tva`).
    ///
    /// Une carte plutôt que des paramètres nommés : les champs varient selon
    /// le pays, et les figer ici obligerait à modifier chaque couche à chaque
    /// pays ajouté.
    Map<String, String> identifiants = const {},
    String? organisationTelephone,
    String? organisationEmail,
    String? organisationAdresse,
    String? organisationVille,
    String? organisationPays,
  }) async {
    try {
      final utilisateur = await remoteDataSource.register({
        'nom': nom,
        'prenom': prenom,
        'email': email,
        'mot_de_passe': motDePasse,
        if (telephone != null && telephone.isNotEmpty) 'telephone': telephone,
        if (fonction != null && fonction.isNotEmpty) 'fonction': fonction,
        if (organisationNom != null && organisationNom.isNotEmpty) 'organisationNom': organisationNom,
        if (raisonSociale != null && raisonSociale.isNotEmpty) 'raison_sociale': raisonSociale,
        // Les identifiants partent sous leur clé serveur. Les valeurs vides
        // sont OMISES plutôt qu'envoyées à '' : le schéma les tolère, mais une
        // chaîne vide en base se relit ensuite comme une valeur renseignée.
        ...Map.fromEntries(
          identifiants.entries.where((e) => e.value.trim().isNotEmpty),
        ),
        if (organisationTelephone != null && organisationTelephone.isNotEmpty)
          'organisationTelephone': organisationTelephone,
        if (organisationEmail != null && organisationEmail.isNotEmpty) 'organisationEmail': organisationEmail,
        if (organisationAdresse != null && organisationAdresse.isNotEmpty)
          'organisationAdresse': organisationAdresse,
        if (organisationVille != null && organisationVille.isNotEmpty) 'organisationVille': organisationVille,
        if (organisationPays != null && organisationPays.isNotEmpty) 'organisationPays': organisationPays,
      });
      // L'inscription NE connecte PAS automatiquement (le backend exige la
      // vérification d'email avant login — voir REQUIRE_EMAIL_VERIFICATION) :
      // aucun token à stocker ici, contrairement à login/verifierMfa.
      return Right(utilisateur);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, String>> forgotPassword({required String email}) async {
    try {
      final message = await remoteDataSource.forgotPassword(email: email);
      return Right(message);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, String>> resetPassword({
    required String email,
    required String otp,
    required String nouveauMotDePasse,
  }) async {
    try {
      final message = await remoteDataSource.resetPassword(email: email, otp: otp, nouveauMotDePasse: nouveauMotDePasse);
      // L'ancien mot de passe ne doit plus rien ouvrir, même sans réseau.
      await _effacerVerificateur();
      return Right(message);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<void> logout() async {
    try {
      // Lu AVANT l'effacement plus bas : c'est lui que le serveur révoque.
      final refreshToken = await tokenService.getRefreshToken();
      await remoteDataSource.logout(refreshToken: refreshToken);
    } catch (_) {
      // Best-effort — la révocation côté serveur ne doit jamais empêcher la
      // déconnexion locale (cohérent avec l'admin web, voir api.js).
    }
    // La déconnexion retire les JETONS et les copies mémoire, rien d'autre :
    // l'accès hors ligne (empreinte du mot de passe), le profil chiffré et les
    // données locales — saisies en attente comprises — sont CONSERVÉS, pour
    // pouvoir rouvrir l'application sans réseau avec son mot de passe.
    //
    // Le compte suivant ne peut pourtant rien en lire : `adopterUtilisateur`
    // purge les données de l'ancien propriétaire à la connexion d'un AUTRE
    // compte, avant que le moindre écran ne soit servi, et l'accès hors ligne
    // est de toute façon remplacé par le sien (un seul compte par appareil).
    // L'accès local de ce compte disparaît avec : un changement ou une
    // réinitialisation de mot de passe, une suppression de compte, un refus
    // 403 du serveur, 10 essais ratés, ou 14 jours sans confirmation.
    await tokenService.clearToken();
    cacheHttp.vider();
  }

  @override
  Future<User?> restaurerSession() async {
    try {
      final refreshToken = await tokenService.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return null;

      // Le token en cache peut déjà être valide (pas encore expiré) — dans
      // ce cas pas besoin de refresh, mais on revalide TOUJOURS le profil
      // via /account/me pour repartir d'un rôle/statut à jour (ex : rôle
      // changé par un ChefProjet pendant que l'app était fermée).
      final utilisateur = await remoteDataSource.getMe();
      await userCache.saveJson(utilisateur.toJson());
      // Le serveur vient de reconfirmer ce compte : la fenêtre d'accès hors
      // ligne repart de zéro.
      try {
        await verificateur.marquerValide(utilisateur.id);
      } catch (_) {}
      // Même filet de sécurité que `_persisterSession` : une base locale qui
      // ne répond pas ne doit jamais empêcher la restauration de session au
      // démarrage — et surtout pas être interceptée par le `catch` ci-dessous
      // (prévu pour une session RÉELLEMENT invalide côté serveur), qui
      // effacerait le token pour un simple souci de stockage local.
      try {
        await sessionLocale.adopterUtilisateur(utilisateur.id).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[session] Contrôle du propriétaire des données locales indisponible ($e).');
      }
      return utilisateur;
    } on NetworkException catch (_) {
      // PAS DE RÉSEAU — surtout ne rien effacer.
      //
      // Ce cas tombait dans le `catch` ci-dessous et effaçait les jetons :
      // démarrer l'application sans signal DÉCONNECTAIT l'utilisateur, et lui
      // retirait du même coup l'accès à ses réserves hors ligne et à sa file
      // d'envoi. Exactement la situation pour laquelle le mode hors ligne
      // existe — un sous-sol, un chantier sans couverture.
      //
      // Le profil chiffré écrit à chaque connexion servait précisément à cela
      // et n'était jamais relu : `readJson()` n'avait aucun appelant. On s'en
      // sert ici plutôt que d'inventer un stockage de plus.
      //
      // Les jetons restent en place : ils seront revalidés au retour du
      // réseau, et c'est le serveur — jamais ce repli — qui décidera alors
      // si la session est encore valable.
      final profil = await userCache.readJson();
      if (profil == null) return null;
      return UserModel.fromJson(profil);
    } catch (_) {
      // Session non restaurable (jeton révoqué, compte désactivé…). On efface
      // les jetons, mais PAS les données locales : elles peuvent contenir du
      // travail hors ligne non synchronisé, que le même utilisateur doit
      // retrouver en se reconnectant. C'est l'arrivée d'un utilisateur
      // DIFFÉRENT qui déclenchera la purge — voir `SessionLocale`.
      await tokenService.clearToken();
      await userCache.clear();
      cacheHttp.vider();
      return null;
    }
  }
}
