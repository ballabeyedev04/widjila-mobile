import 'package:flutter/foundation.dart';

import '../errors/exceptions.dart';
import '../../features/rapport/data/datasources/rapport_remote_datasource.dart';
import '../../features/rapport/domain/entities/envoi_rapport.dart';
import '../../features/reserve/data/datasources/reserve_remote_datasource.dart';
import '../../features/reserve/domain/entities/reserve.dart';
import 'cache_reserves.dart';
import 'file_attente.dart';
import 'stockage_medias.dart';

/// Traduit une [ActionEnAttente] générique en VRAI appel réseau.
///
/// C'est le seul endroit qui connaît la correspondance entre un [TypeAction]
/// et la méthode de datasource à appeler — [SynchronisationService], lui, ne
/// sait qu'orchestrer (ordre, verrou, retentatives). Cette séparation est ce
/// qui permet d'étendre l'outbox à d'autres domaines (plans, documents) sans
/// toucher au moteur de synchronisation lui-même : il suffira d'ajouter un
/// `case` ici.
class ExecuteurActionsHorsLigne {
  final ReserveRemoteDataSource _reserves;
  final CacheReserves _cache;
  final StockageMedias _medias;

  /// Facultatif : seuls les envois de rapport en ont besoin, et les tests
  /// de la file des réserves n'ont pas à le fournir.
  final RapportRemoteDataSource? _rapports;

  /// Facultative : sert à savoir si d'AUTRES actions sur la même réserve
  /// attendent encore (voir [_confirmer]). Absente, une réserve confirmée par
  /// le serveur est toujours marquée « à jour » — le comportement d'origine.
  final FileAttente? _file;

  // Paramètres nommés sans préfixe pour un appel lisible côté DI
  // (`ExecuteurActionsHorsLigne(reserves: ..., cache: ..., medias: ...)`) —
  // l'initializing formal que suggère l'analyseur imposerait le préfixe
  // souligné des champs jusque dans l'API publique.
  // ignore_for_file: prefer_initializing_formals
  ExecuteurActionsHorsLigne({
    required ReserveRemoteDataSource reserves,
    required CacheReserves cache,
    required StockageMedias medias,
    RapportRemoteDataSource? rapports,
    FileAttente? file,
  })  : _reserves = reserves,
        _cache = cache,
        _medias = medias,
        _rapports = rapports,
        _file = file;

  Future<void> executer(ActionEnAttente action) async {
    switch (action.type) {
      case TypeAction.creerReserve:
        await _creerReserve(action);
      case TypeAction.changerStatutReserve:
        await _changerStatut(action);
      case TypeAction.ajouterPhotoReserve:
        await _ajouterPhoto(action);
      case TypeAction.envoyerRapport:
        await _envoyerRapport(action);
    }
  }

  /// Défait l'écriture OPTIMISTE portée par une action définitivement refusée.
  ///
  /// Sans cette contrepartie, un refus serveur laissait la base locale sur la
  /// valeur que l'utilisateur avait demandée : `enregistrerTous` épargne les
  /// lignes `en_attente = 1`, donc aucune réponse du serveur ne pouvait plus
  /// la corriger. L'écran montrait un statut que le serveur n'a jamais
  /// accepté, définitivement.
  ///
  /// Ne lève JAMAIS : elle est appelée alors qu'une erreur est déjà en cours
  /// de traitement, et son propre échec ne doit pas masquer la cause initiale
  /// ni bloquer la file. Son échec est en revanche JOURNALISÉ — le taire
  /// laisserait une ligne locale fausse sans la moindre trace.
  Future<void> annuler(ActionEnAttente action) async {
    try {
      switch (action.type) {
        case TypeAction.creerReserve:
          // Le serveur a refusé la création : la réserve n'existe pas de son
          // côté. La garder localement afficherait une réserve fantôme, avec
          // un numéro provisoire, que personne ne pourra jamais ouvrir.
          await _cache.supprimer(action.charge['id'] as String);

        case TypeAction.changerStatutReserve:
          // Le statut demandé est refusé. On rétablit la VÉRITÉ du serveur
          // plutôt que de deviner l'ancienne valeur — la réserve a pu changer
          // entre-temps, et une valeur inventée serait un second mensonge.
          final id = action.charge['reserveId'] as String;
          try {
            final aJour = await _reserves.getReserveDetail(id);
            await _cache.enregistrer(aJour, enAttente: false);
          } catch (e) {
            // Serveur injoignable ou réserve disparue : on relâche au moins la
            // ligne, pour que le prochain rafraîchissement puisse l'écraser.
            debugPrint('[sync] Relecture de la réserve $id impossible après refus ($e) — ligne relâchée');
            await _cache.libererEnAttente(id);
          }

        case TypeAction.ajouterPhotoReserve:
          // Rien n'a été écrit dans le cache des réserves : seule la copie
          // locale du fichier subsiste. On la garde — c'est la seule trace de
          // la photo, et l'utilisateur peut vouloir la renvoyer.
          break;

        case TypeAction.envoyerRapport:
          // Aucun effet optimiste à défaire : l'envoi n'avait rien écrit
          // localement. Le refus reste visible dans l'écran des tâches.
          break;
      }
    } catch (e) {
      // Voir la note ci-dessus : l'annulation est un filet, jamais un point
      // de rupture supplémentaire — mais jamais un silence non plus.
      debugPrint('[sync] Annulation de l’action ${action.id} (${action.type.code}) impossible : $e');
    }
  }

  Future<void> _creerReserve(ActionEnAttente action) async {
    final c = action.charge;

    // La phase est devenue OBLIGATOIRE côté serveur. Une action déposée dans
    // la file AVANT cette version n'en porte pas : la laisser partir vaudrait
    // un 400 « Veuillez sélectionner une phase », affiché dans l'écran de
    // synchronisation sans dire à l'utilisateur quoi faire de sa réserve.
    //
    // On échoue donc ici, avec un message qui indique la marche à suivre. Le
    // 400 est délibéré : il classe l'action en échec DÉFINITIF (voir
    // `SynchronisationService`), ce qui est exact — la retenter telle quelle
    // échouera toujours — et libère la file au lieu de la bloquer.
    //
    // Ne rien inventer ici : choisir une phase à la place de l'utilisateur
    // rattacherait la réserve à une étape de chantier qu'il n'a pas désignée.
    if (c['phaseId'] == null) {
      throw const ServerException(
        statusCode: 400,
        message: 'Cette réserve a été créée avant la mise à jour, sans phase de '
            'chantier. Ouvrez-la et créez-la à nouveau en choisissant sa phase.',
      );
    }

    final reserve = await _reserves.creerReserve(
      id: c['id'] as String,
      chantierId: c['chantierId'] as String,
      titre: c['titre'] as String,
      description: c['description'] as String?,
      priorite: ReserveSeveriteX.fromString(c['priorite'] as String?),
      categorie: ReserveCategorieX.fromString(c['categorie'] as String?),
      batimentId: c['batimentId'] as String?,
      etageId: c['etageId'] as String?,
      zoneId: c['zoneId'] as String?,
      lotId: c['lotId'] as String?,
      dateLimite: c['dateLimite'] != null ? DateTime.tryParse(c['dateLimite'] as String) : null,
      planId: c['planId'] as String?,
      positionX: (c['positionX'] as num?)?.toDouble(),
      positionY: (c['positionY'] as num?)?.toDouble(),
      positionPage: (c['positionPage'] as num?)?.toInt() ?? 1,
      partenaireId: c['partenaireId'] as String?,
      // Absente des actions déposées AVANT cette version : `fromString`
      // retombe alors sur la valeur par défaut, et le datasource sur la
      // priorité — une file existante se rejoue donc sans erreur.
      severite: c['severite'] != null ? ReserveSeveriteX.fromString(c['severite'] as String?) : null,
      // Absent des actions déposées avant cette version : la réserve part
      // alors sans métier, comme auparavant, au lieu d'échouer. Contrairement
      // à la phase, `corpsEtatId` reste FACULTATIF côté serveur.
      corpsEtatId: c['corpsEtatId'] as String?,
      // Non nul : vérifié en tête de méthode.
      phaseId: c['phaseId'] as String?,
    );
    // Même identifiant des deux côtés (voir `creerReserveSchema` côté back),
    // donc un simple ré-enregistrement suffit — pas de remplacement d'id.
    await _confirmer(reserve, action);
  }

  Future<void> _changerStatut(ActionEnAttente action) async {
    final c = action.charge;
    final reserve = await _reserves.changerStatut(
      reserveId: c['reserveId'] as String,
      statut: ReserveStatutX.fromString(c['statut'] as String?),
      motif: c['motif'] as String?,
    );
    await _confirmer(reserve, action);
  }

  /// Écrit la version CONFIRMÉE par le serveur dans le cache.
  ///
  /// CORRECTIF (audit synchronisation) — la ligne était toujours marquée « à
  /// jour » (`en_attente = 0`), même quand un AUTRE changement fait hors ligne
  /// sur la même réserve attendait encore son tour (création confirmée, mais
  /// passage en « corrigée » pas encore parti). Deux effets :
  ///  - le statut affiché retombait sur celui du serveur (« créée ») alors que
  ///    l'utilisateur avait déclaré la correction ;
  ///  - la ligne redevenait écrasable par un rafraîchissement de liste, qui
  ///    effaçait l'écriture optimiste avant son envoi.
  ///
  /// Désormais, tant qu'une action reste en file pour cette réserve, on garde
  /// la version serveur (numéro définitif, champs calculés) AVEC le statut
  /// local, et la ligne reste protégée. Le statut est le seul champ qu'une
  /// action hors ligne modifie : c'est donc une fusion exacte, pas une
  /// approximation.
  ///
  /// Seules comptent les actions qui RÉÉCRIVENT la ligne (création, statut).
  /// Une photo en file ne la modifie pas : la compter retenait la ligne « en
  /// attente » pour toujours, car l'envoi de la photo ne repasse jamais par
  /// ici pour la libérer (défaut trouvé par le test de chaos).
  static const _typesQuiReecriventLaLigne = {TypeAction.creerReserve, TypeAction.changerStatutReserve};

  Future<void> _confirmer(Reserve serveur, ActionEnAttente action) async {
    final file = _file;
    final encore = file != null &&
        await file.aDesActionsEnAttentePour(action.cleEntite, sauf: action.id, types: _typesQuiReecriventLaLigne);
    if (!encore) {
      await _cache.enregistrer(serveur, enAttente: false);
      return;
    }
    final locale = await _cache.lire(serveur.id);
    await _cache.enregistrer(
      locale == null ? serveur : serveur.copierAvecStatut(locale.statut),
      enAttente: true,
    );
  }

  Future<void> _ajouterPhoto(ActionEnAttente action) async {
    final c = action.charge;
    final chemin = action.cheminFichier;
    if (chemin == null) {
      // Rien à envoyer — l'action est incohérente (ne devrait jamais arriver,
      // `FileAttente.deposer` exige ce champ pour ce type). `ActionInvalide` :
      // la synchronisation la sort du cycle au lieu de la retenter en boucle.
      throw ActionInvalide('Action ajouterPhotoReserve sans chemin de fichier');
    }
    // Idempotent côté serveur : un même contenu sur une même réserve n'est
    // enregistré qu'une fois (empreinte SHA-256, voir `MediaService`).
    await _reserves.ajouterMedia(
      reserveId: c['reserveId'] as String,
      cheminFichier: chemin,
      type: c['type'] as String? ?? 'photo',
    );
    // Le serveur a la photo : la copie locale ne sert plus à rien.
    await _medias.supprimer(chemin);
  }

  /// Rejoue un envoi de rapport déposé hors ligne.
  ///
  /// La demande est celle que l'utilisateur a VALIDÉE, telle quelle : le
  /// serveur recalcule et vérifie les destinataires au moment de l'envoi, et
  /// refuse toute adresse étrangère au chantier — rejouer ne peut donc rien
  /// élargir.
  ///
  /// La clé d'idempotence est celle de la tentative d'ORIGINE (déposée avec
  /// l'action), à défaut l'identifiant de l'action : un envoi déjà parti
  /// avant que la réponse ne se perde n'est pas réexpédié.
  Future<void> _envoyerRapport(ActionEnAttente action) async {
    final rapports = _rapports;
    if (rapports == null) {
      throw ActionInvalide('Envoi de rapport en attente sans source de données rapports');
    }
    final c = action.charge;
    await rapports.envoyerRapport(
      c['rapportId'] as String,
      DemandeEnvoiRapport.fromJson((c['demande'] as Map?)?.cast<String, dynamic>() ?? const {}),
      cleIdempotence: c['cleIdempotence'] as String? ?? action.id,
    );
  }
}
