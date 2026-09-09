import '../errors/exceptions.dart';
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

  // Paramètres nommés sans préfixe pour un appel lisible côté DI
  // (`ExecuteurActionsHorsLigne(reserves: ..., cache: ..., medias: ...)`) —
  // l'initializing formal que suggère l'analyseur imposerait le préfixe
  // souligné des champs jusque dans l'API publique.
  // ignore_for_file: prefer_initializing_formals
  ExecuteurActionsHorsLigne({
    required ReserveRemoteDataSource reserves,
    required CacheReserves cache,
    required StockageMedias medias,
  })  : _reserves = reserves,
        _cache = cache,
        _medias = medias;

  Future<void> executer(ActionEnAttente action) async {
    switch (action.type) {
      case TypeAction.creerReserve:
        await _creerReserve(action);
      case TypeAction.changerStatutReserve:
        await _changerStatut(action);
      case TypeAction.ajouterPhotoReserve:
        await _ajouterPhoto(action);
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
  /// ni bloquer la file.
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
          } catch (_) {
            // Serveur injoignable ou réserve disparue : on relâche au moins la
            // ligne, pour que le prochain rafraîchissement puisse l'écraser.
            await _cache.libererEnAttente(id);
          }

        case TypeAction.ajouterPhotoReserve:
          // Rien n'a été écrit dans le cache des réserves : seule la copie
          // locale du fichier subsiste. On la garde — c'est la seule trace de
          // la photo, et l'utilisateur peut vouloir la renvoyer.
          break;
      }
    } catch (_) {
      // Voir la note ci-dessus : l'annulation est un filet, jamais un point
      // de rupture supplémentaire.
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
    // Le serveur a confirmé : la ligne locale n'est plus « en attente ».
    // Même identifiant des deux côtés (voir `creerReserveSchema` côté back),
    // donc un simple ré-enregistrement suffit — pas de remplacement d'id.
    await _cache.enregistrer(reserve, enAttente: false);
  }

  Future<void> _changerStatut(ActionEnAttente action) async {
    final c = action.charge;
    final reserve = await _reserves.changerStatut(
      reserveId: c['reserveId'] as String,
      statut: ReserveStatutX.fromString(c['statut'] as String?),
      motif: c['motif'] as String?,
    );
    await _cache.enregistrer(reserve, enAttente: false);
  }

  Future<void> _ajouterPhoto(ActionEnAttente action) async {
    final c = action.charge;
    final chemin = action.cheminFichier;
    if (chemin == null) {
      // Rien à envoyer — l'action est incohérente (ne devrait jamais arriver,
      // `FileAttente.deposer` exige ce champ pour ce type). On la laisse
      // échouer proprement plutôt que de planter la passe de synchronisation.
      throw StateError('Action ajouterPhotoReserve sans chemin de fichier');
    }
    await _reserves.ajouterMedia(
      reserveId: c['reserveId'] as String,
      cheminFichier: chemin,
      type: c['type'] as String? ?? 'photo',
    );
    // Le serveur a la photo : la copie locale ne sert plus à rien.
    await _medias.supprimer(chemin);
  }
}
