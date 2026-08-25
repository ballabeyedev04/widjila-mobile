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

  Future<void> _creerReserve(ActionEnAttente action) async {
    final c = action.charge;
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
