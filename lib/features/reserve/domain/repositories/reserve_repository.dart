import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/chantier_structure.dart';
import '../entities/reserve.dart';
import '../entities/reserve_collaboration.dart';
import '../entities/reserve_evolution.dart';

/// Page de résultats — même contrat de pagination que les autres features
/// (`{ items, total }`, miroir de `middlewares/pagination.middleware.js`).
class ReservePage {
  final List<Reserve> items;
  final int total;
  const ReservePage({required this.items, required this.total});
}

/// Répartition des réserves d'un chantier par statut — chiffres bruts
/// renvoyés par le back (`GET /dashboard/chantiers/:id` → `stats.parStatut`).
/// Le mobile s'en sert pour (a) les compteurs des filtres et (b) le donut :
/// aucun calcul de statistique n'est refait côté client, seul le rendu
/// graphique l'est (voir `ReserveStatutDonut`).
class ReserveStatutsCount {
  final Map<ReserveStatut, int> parStatut;
  final int total;
  const ReserveStatutsCount({required this.parStatut, required this.total});

  int pour(ReserveStatut statut) => parStatut[statut] ?? 0;

  factory ReserveStatutsCount.vide() => const ReserveStatutsCount(parStatut: {}, total: 0);
}

abstract class ReserveRepository {
  Future<Either<Failure, ReservePage>> getReserves({
    required String chantierId,
    int page = 1,
    int limit = 20,
    String? search,
    ReserveStatut? statut,
  });

  /// Liste TRANSVERSALE (tous chantiers) — alimente l'onglet « Réserves »,
  /// écran de premier niveau. Distincte de [getReserves], qui reste la liste
  /// d'un chantier donné.
  Future<Either<Failure, ReservePage>> getToutesReserves({
    int page = 1,
    int limit = 20,
    String? search,
    ReserveStatut? statut,
  });

  Future<Either<Failure, ReserveStatutsCount>> getStatutsCount(String chantierId);

  /// Répartition par statut sur TOUTE l'organisation (`GET /dashboard`) —
  /// pendant transversal de [getStatutsCount], pour l'onglet « Réserves » qui
  /// n'appartient à aucun chantier.
  Future<Either<Failure, ReserveStatutsCount>> getStatutsCountGlobal();

  Future<Either<Failure, Reserve>> getReserveDetail(String id);

  /// Modifie une réserve (`PUT /reserves/:id`).
  ///
  /// Champs PARTIELS : seules les clés présentes sont modifiées côté serveur.
  /// Réservé à OPERATIONNEL_CONTROLE — la présentation masque l'action pour
  /// les autres rôles plutôt que de laisser découvrir un 403.
  Future<Either<Failure, Reserve>> modifierReserve({
    required String id,
    String? titre,
    String? description,
    ReserveSeverite? severite,
    ReserveCategorie? categorie,
    DateTime? dateLimite,
  });

  /// Supprime une réserve (`DELETE /reserves/:id`) — réservé à OPERATIONNEL.
  Future<Either<Failure, void>> supprimerReserve(String id);

  /// Fil de discussion d'une réserve (`/reserves/:id/commentaires`).
  Future<Either<Failure, List<CommentaireReserve>>> getCommentaires(String reserveId);
  Future<Either<Failure, CommentaireReserve>> ajouterCommentaire({
    required String reserveId,
    required String message,
  });

  /// Intervenants affectés à une réserve (`/reserves/:id/affectations`).
  ///
  /// Le serveur exige un utilisateur OU une entreprise, jamais les deux ni
  /// aucun (`affecterReserveSchema`).
  Future<Either<Failure, List<AffectationReserve>>> getAffectations(String reserveId);
  Future<Either<Failure, AffectationReserve>> affecter({
    required String reserveId,
    String? utilisateurId,
    String? entrepriseId,
  });
  Future<Either<Failure, void>> retirerAffectation({
    required String reserveId,
    required String affectationId,
  });

  /// Duplique une réserve (`POST /reserves/:id/dupliquer`) et renvoie la
  /// COPIE. Réservé à OPERATIONNEL_CONTROLE côté serveur.
  Future<Either<Failure, Reserve>> dupliquerReserve(String id);

  /// QR code de la réserve (`GET /reserves/:id/qr`), à imprimer et poser sur
  /// site : un scan ouvre la fiche directement.
  Future<Either<Failure, QrReserve>> getQr(String id);

  Future<Either<Failure, Reserve>> creerReserve({
    required String chantierId,
    required String titre,
    String? description,
    required ReserveSeverite priorite,
    required ReserveCategorie categorie,
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? lotId,
    DateTime? dateLimite,
  });

  Future<Either<Failure, Reserve>> changerStatut({
    required String reserveId,
    required ReserveStatut statut,
    String? motif,
  });

  Future<Either<Failure, List<ReserveMedia>>> getMedias(String reserveId);

  Future<Either<Failure, ReserveMedia>> ajouterMedia({
    required String reserveId,
    required String cheminFichier,
    String type = 'photo',
  });

  /// Structure du chantier (bâtiments/étages/zones/lots) — pour peupler les
  /// sélecteurs de localisation de l'assistant de création de réserve.
  Future<Either<Failure, ChantierStructure>> getStructure(String chantierId);

  /// Évolution mensuelle (créées/validées) — alimente la courbe du tableau
  /// de bord du chantier (`GET /dashboard/chantiers/:id/evolution`).
  Future<Either<Failure, ReserveEvolution>> getEvolution(String chantierId);
}
