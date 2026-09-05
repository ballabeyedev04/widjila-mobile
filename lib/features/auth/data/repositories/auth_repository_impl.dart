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

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.tokenService,
    required this.userCache,
    required this.sessionLocale,
    required this.cacheHttp,
  });

  Future<void> _persisterSession(String? token, String? refreshToken, UserModel utilisateur) async {
    if (token != null) await tokenService.setToken(token);
    if (refreshToken != null) await tokenService.setRefreshToken(refreshToken);
    await userCache.saveJson(utilisateur.toJson());
    // AVANT que le moindre écran ne lise le cache : si les données locales
    // appartiennent à un AUTRE compte (appareil de chantier partagé, ou
    // déconnexion précédente interrompue par un kill), elles sont purgées
    // ici. Voir `SessionLocale` pour le raisonnement complet.
    //
    // Le `.timeout(...)` est un filet de sécurité DÉLIBÉRÉ : une base
    // locale qui met du temps à s'ouvrir (verrou SQLite, plateforme mal
    // supportée — c'est arrivé en pratique sur web, où `openDatabase` peut
    // rester indéfiniment en attente sans web/index.html configuré pour
    // charger sqlite3.wasm) ne doit JAMAIS pouvoir bloquer la CONNEXION
    // elle-même. Le cloisonnement du cache est une protection secondaire ;
    // se connecter est la fonctionnalité principale, elle ne doit jamais
    // dépendre de la première pour aboutir. Un dépassement est silencieux
    // ici : la purge n'a simplement pas pu être confirmée à temps, mais elle
    // sera rattrapée à la prochaine authentification réussie (voir
    // `SessionLocale.adopterUtilisateur`, qui revérifie le propriétaire à
    // chaque appel).
    try {
      await sessionLocale.adopterUtilisateur(utilisateur.id).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[session] Contrôle du propriétaire des données locales indisponible ($e) — '
          'connexion poursuivie, sera retenté à la prochaine authentification.');
    }
  }

  @override
  Future<Either<Failure, LoginResult>> login({
    required String identifiant,
    required String motDePasse,
  }) async {
    try {
      final response = await remoteDataSource.login(identifiant: identifiant, motDePasse: motDePasse);
      if (!response.mfaRequise) {
        await _persisterSession(response.token, response.refreshToken, response.utilisateur);
      }
      return Right(LoginResult(mfaRequise: response.mfaRequise, utilisateur: response.utilisateur));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
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
      return Right(message);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<void> logout() async {
    try {
      await remoteDataSource.logout();
    } catch (_) {
      // Best-effort — la révocation côté serveur ne doit jamais empêcher la
      // déconnexion locale (cohérent avec l'admin web, voir api.js).
    }
    // Purge ATTENDUE, et AVANT l'effacement du jeton : tant qu'elle n'a pas
    // rendu la main, la session reste techniquement ouverte. Si le process
    // est tué ici, les jetons sont encore là — l'utilisateur reste donc
    // connecté plutôt que de laisser ses données orphelines et lisibles par
    // le compte suivant.
    //
    // `.timeout(...)` : une base locale qui ne répond pas ne doit jamais
    // empêcher l'utilisateur de se DÉCONNECTER — le bloquer connecté serait
    // pire que le risque résiduel qu'elle protège. Si la purge n'aboutit pas
    // à temps ici, `SessionLocale.adopterUtilisateur` la rattrape à la
    // prochaine connexion (même compte : rien à purger ; compte différent :
    // purge exécutée avant de servir la moindre donnée).
    try {
      await sessionLocale.purger().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[session] Purge des données locales indisponible ($e) — déconnexion poursuivie.');
    }
    await tokenService.clearToken();
    await userCache.clear();
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
