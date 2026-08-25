import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/user_role.dart';
import '../../domain/usecases/ajouter_membre.dart';
import '../../domain/usecases/changer_statut_membre.dart';
import '../../domain/usecases/get_membres.dart';
import 'membres_state.dart';

class MembresCubit extends Cubit<MembresState> {
  final GetMembres getMembres;
  final AjouterMembre ajouterMembreUsecase;
  final ChangerStatutMembre changerStatutMembreUsecase;

  MembresCubit({
    required this.getMembres,
    required this.ajouterMembreUsecase,
    required this.changerStatutMembreUsecase,
  }) : super(const MembresState());

  void rechercher(String texte) => emit(state.copyWith(recherche: texte));

  void filtrerParStatut(String? statut) =>
      emit(state.copyWith(filtreStatut: statut, effacerFiltreStatut: statut == null));

  /// Bascule actif ↔ inactif.
  ///
  /// Renvoie le membre à jour, ou `null` en cas d'échec (le message est alors
  /// dans `state.statutErreur`). Le serveur REFUSE qu'un utilisateur change
  /// son propre statut : l'appelant doit masquer l'action sur sa propre fiche
  /// plutôt que de laisser découvrir le refus après coup.
  Future<bool> basculerStatut(String membreId, {required bool activer}) async {
    if (state.membreEnCoursDeMaj != null) return false;
    emit(state.copyWith(membreEnCoursDeMaj: membreId, effacerStatutErreur: true));

    final result = await changerStatutMembreUsecase(
      membreId: membreId,
      statut: activer ? ChangerStatutMembre.actif : ChangerStatutMembre.inactif,
    );
    if (isClosed) return false;

    return result.fold(
      (failure) {
        emit(state.copyWith(effacerMembreEnCoursDeMaj: true, statutErreur: failure.errorMessage));
        return false;
      },
      (membre) {
        // Remplacement en place : la liste garde son ordre et sa position de
        // défilement, contrairement à un rechargement complet.
        emit(state.copyWith(
          effacerMembreEnCoursDeMaj: true,
          membres: [
            for (final m in state.membres) m.id == membre.id ? membre : m,
          ],
        ));
        return true;
      },
    );
  }

  Future<void> charger() async {
    emit(state.copyWith(status: MembresStatus.chargement));
    final result = await getMembres();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(status: MembresStatus.erreur, erreur: failure.errorMessage)),
      (membres) => emit(state.copyWith(status: MembresStatus.succes, membres: membres)),
    );
  }

  Future<void> ajouter({
    required String nom,
    required String prenom,
    required String email,
    required UserRole role,
    String? telephone,
    String? fonction,
    String? motDePasse,
  }) async {
    // Verrou de double soumission : deux appuis créeraient deux comptes, le
    // second échouant sur l'unicité de l'email — mais après avoir consommé
    // une place et envoyé un second mot de passe temporaire.
    if (state.soumissionStatus == SoumissionStatus.enCours) return;
    emit(state.copyWith(soumissionStatus: SoumissionStatus.enCours, effacerSoumissionErreur: true));
    final result = await ajouterMembreUsecase(
      nom: nom,
      prenom: prenom,
      email: email,
      role: role,
      telephone: telephone,
      fonction: fonction,
      motDePasse: motDePasse,
    );
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(soumissionStatus: SoumissionStatus.erreur, soumissionErreur: failure.errorMessage)),
      (resultat) => emit(state.copyWith(
        soumissionStatus: SoumissionStatus.succes,
        dernierAjout: resultat,
        // Le nouveau membre apparaît immédiatement dans la liste, sans
        // attendre un rechargement réseau complet.
        membres: [resultat.membre, ...state.membres],
      )),
    );
  }

  /// À appeler une fois le popup de confirmation (mot de passe temporaire
  /// éventuel) fermé — évite qu'il réapparaisse à la prochaine reconstruction
  /// de l'écran, et repasse la soumission à l'état inactif pour un prochain
  /// ajout.
  void accuserReceptionAjout() {
    emit(state.copyWith(
      soumissionStatus: SoumissionStatus.inactif,
      effacerDernierAjout: true,
      effacerSoumissionErreur: true,
    ));
  }
}
