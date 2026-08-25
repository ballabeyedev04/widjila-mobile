import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/entities/reserve_collaboration.dart';
import '../../domain/repositories/reserve_repository.dart';
import '../../domain/usecases/ajouter_media_reserve.dart';
import '../../domain/usecases/changer_statut_reserve.dart';
import '../../domain/usecases/get_reserve_detail.dart';
import 'reserve_detail_state.dart';

class ReserveDetailCubit extends Cubit<ReserveDetailState> {
  final GetReserveDetail getReserveDetail;
  final ChangerStatutReserve changerStatutReserve;
  final AjouterMediaReserve ajouterMediaReserve;

  /// Appel DIRECT au repository pour les actions de collaboration (édition,
  /// suppression, commentaires, affectations) : ce sont de simples relais
  /// sans logique propre, un use case par action n'aurait fait qu'ajouter des
  /// fichiers — même arbitrage que `SettingsCubit`.
  final ReserveRepository repository;

  final String reserveId;

  ReserveDetailCubit({
    required this.getReserveDetail,
    required this.changerStatutReserve,
    required this.ajouterMediaReserve,
    required this.repository,
    required this.reserveId,
  }) : super(const ReserveDetailState());

  // -------------------- COLLABORATION --------------------

  /// Charge le fil de discussion et les affectations.
  ///
  /// Volontairement SÉPARÉ de [charger] et lancé en parallèle : deux requêtes
  /// de plus ne doivent pas retarder l'affichage de la réserve, qui est ce
  /// que l'utilisateur est venu voir.
  Future<void> chargerCollaboration() async {
    final commentairesFuture = repository.getCommentaires(reserveId);
    final affectationsFuture = repository.getAffectations(reserveId);

    final commentaires = await commentairesFuture;
    final affectations = await affectationsFuture;
    if (isClosed) return;

    // Un échec laisse la section vide et marquée « chargée » : mieux vaut une
    // section sans contenu qu'un tourniquet perpétuel, et la fiche reste
    // parfaitement lisible.
    emit(state.copyWith(
      commentaires: commentaires.fold((_) => state.commentaires, (v) => v),
      commentairesCharges: true,
      affectations: affectations.fold((_) => state.affectations, (v) => v),
      affectationsChargees: true,
    ));
  }

  /// Ajoute un commentaire. Renvoie `true` si le serveur a accepté.
  Future<bool> ajouterCommentaire(String message) async {
    if (state.commentaireStatus == ActionReserveStatus.enCours) return false;
    emit(state.copyWith(commentaireStatus: ActionReserveStatus.enCours));

    final result = await repository.ajouterCommentaire(reserveId: reserveId, message: message);
    if (isClosed) return false;

    return result.fold(
      (failure) {
        emit(state.copyWith(commentaireStatus: ActionReserveStatus.erreur, erreur: failure.errorMessage));
        return false;
      },
      (commentaire) {
        // Ajout en fin de liste : le back renvoie les commentaires par
        // `createdAt ASC`, le plus récent est donc en bas.
        emit(state.copyWith(
          commentaireStatus: ActionReserveStatus.succes,
          commentaires: [...state.commentaires, commentaire],
        ));
        return true;
      },
    );
  }

  Future<bool> affecter({String? utilisateurId, String? entrepriseId}) async {
    if (state.affectationStatus == ActionReserveStatus.enCours) return false;
    emit(state.copyWith(affectationStatus: ActionReserveStatus.enCours));

    final result = await repository.affecter(
      reserveId: reserveId,
      utilisateurId: utilisateurId,
      entrepriseId: entrepriseId,
    );
    if (isClosed) return false;

    return result.fold(
      (failure) {
        emit(state.copyWith(affectationStatus: ActionReserveStatus.erreur, erreur: failure.errorMessage));
        return false;
      },
      (affectation) {
        emit(state.copyWith(
          affectationStatus: ActionReserveStatus.succes,
          affectations: [affectation, ...state.affectations],
        ));
        return true;
      },
    );
  }

  Future<bool> retirerAffectation(String affectationId) async {
    if (state.affectationStatus == ActionReserveStatus.enCours) return false;
    emit(state.copyWith(affectationStatus: ActionReserveStatus.enCours));

    final result = await repository.retirerAffectation(
      reserveId: reserveId,
      affectationId: affectationId,
    );
    if (isClosed) return false;

    return result.fold(
      (failure) {
        emit(state.copyWith(affectationStatus: ActionReserveStatus.erreur, erreur: failure.errorMessage));
        return false;
      },
      (_) {
        emit(state.copyWith(
          affectationStatus: ActionReserveStatus.succes,
          affectations: state.affectations.where((a) => a.id != affectationId).toList(),
        ));
        return true;
      },
    );
  }

  /// Modifie la réserve. Renvoie `true` si le serveur a accepté.
  Future<bool> modifier({
    String? titre,
    String? description,
    ReserveSeverite? severite,
    ReserveCategorie? categorie,
    DateTime? dateLimite,
  }) async {
    if (state.actionEnCours) return false;
    emit(state.copyWith(actionEnCours: true));

    final result = await repository.modifierReserve(
      id: reserveId,
      titre: titre,
      description: description,
      severite: severite,
      categorie: categorie,
      dateLimite: dateLimite,
    );
    if (isClosed) return false;

    return result.fold(
      (failure) {
        emit(state.copyWith(erreur: failure.errorMessage));
        return false;
      },
      (reserve) {
        emit(state.copyWith(reserve: reserve, status: ReserveDetailStatus.succes));
        return true;
      },
    );
  }

  /// Duplique la réserve. Renvoie la COPIE, que l'appelant peut ouvrir.
  ///
  /// La fiche courante n'est PAS remplacée : on vient de créer une seconde
  /// réserve, l'originale existe toujours et reste à l'écran.
  Future<Reserve?> dupliquer() async {
    if (state.actionEnCours) return null;
    emit(state.copyWith(actionEnCours: true));

    final result = await repository.dupliquerReserve(reserveId);
    if (isClosed) return null;

    return result.fold(
      (failure) {
        emit(state.copyWith(erreur: failure.errorMessage));
        return null;
      },
      (reserve) {
        emit(state.copyWith());
        return reserve;
      },
    );
  }

  /// Récupère le QR code. Renvoie `null` en cas d'échec (message dans
  /// `state.erreur`).
  Future<QrReserve?> chargerQr() async {
    final result = await repository.getQr(reserveId);
    if (isClosed) return null;
    return result.fold(
      (failure) {
        emit(state.copyWith(erreur: failure.errorMessage));
        return null;
      },
      (qr) => qr,
    );
  }

  /// Supprime la réserve. En cas de succès, `state.supprimee` passe à `true`
  /// et l'écran appelant doit se refermer.
  Future<bool> supprimer() async {
    if (state.actionEnCours) return false;
    emit(state.copyWith(actionEnCours: true));

    final result = await repository.supprimerReserve(reserveId);
    if (isClosed) return false;

    return result.fold(
      (failure) {
        emit(state.copyWith(erreur: failure.errorMessage));
        return false;
      },
      (_) {
        emit(state.copyWith(supprimee: true));
        return true;
      },
    );
  }

  Future<void> charger() async {
    emit(state.copyWith(status: ReserveDetailStatus.chargement));
    final result = await getReserveDetail(reserveId);
    // L'utilisateur a pu revenir en arrière pendant le chargement : émettre
    // sur un cubit fermé lève une `StateError` non gérée, désormais remontée
    // comme crash fatal par `runZonedGuarded` (voir main.dart).
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(status: ReserveDetailStatus.erreur, erreur: failure.errorMessage)),
      (reserve) => emit(state.copyWith(status: ReserveDetailStatus.succes, reserve: reserve)),
    );
  }

  /// Retourne `true` si le changement a réussi (permet à l'UI d'afficher un
  /// message de succès distinct de l'erreur de transition renvoyée par le
  /// back — la matrice de transitions n'est pas dupliquée côté mobile,
  /// c'est le back qui reste juge de ce qui est autorisé).
  Future<bool> changerStatut(ReserveStatut statut, {String? motif}) async {
    // Verrou de double soumission : sans lui, un double appui sur une entrée
    // du sélecteur de statut envoie deux transitions. La seconde échouerait
    // côté back (la matrice de transitions interdit de repartir du nouvel
    // état) mais afficherait une erreur incompréhensible juste après un
    // succès.
    if (state.actionEnCours) return false;
    emit(state.copyWith(actionEnCours: true));
    final result = await changerStatutReserve(reserveId: reserveId, statut: statut, motif: motif);
    if (isClosed) return false;
    return result.fold(
      (failure) {
        emit(state.copyWith(actionEnCours: false, erreur: failure.errorMessage));
        return false;
      },
      (reserve) {
        emit(state.copyWith(actionEnCours: false, reserve: reserve, erreur: null));
        return true;
      },
    );
  }

  Future<bool> ajouterPhoto(String cheminFichier) async {
    // Même verrou : un double appui téléverserait deux fois la même photo,
    // qui apparaîtrait en double dans la galerie de la réserve.
    if (state.actionEnCours) return false;
    emit(state.copyWith(actionEnCours: true));
    final result = await ajouterMediaReserve(reserveId: reserveId, cheminFichier: cheminFichier, type: 'photo');
    if (isClosed) return false;
    if (result.isLeft()) {
      final erreur = result.fold((f) => f.errorMessage, (_) => null);
      emit(state.copyWith(actionEnCours: false, erreur: erreur));
      return false;
    }
    // Rafraîchit le détail complet pour récupérer la nouvelle galerie —
    // plus simple/fiable que de recomposer la liste de médias en mémoire.
    // `charger()` remet `actionEnCours` à false via son émission de statut.
    await charger();
    return true;
  }
}
