import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/entities/rapport.dart';
import '../../domain/entities/suivi_rapport.dart';
import '../../domain/usecases/rapport_usecases.dart';

enum StatutDetailRapport { chargement, succes, erreur }

/// L'action en cours sur le rapport — une seule à la fois.
enum ActionDetailRapport { aucune, generation, duplication, archivage, parEntreprise, revocation }

/// Le message ponctuel à montrer après une action réussie.
enum EvenementDetailRapport { aucun, genere, nouvelleVersion, duplique, archive, parEntreprise, revoque }

class RapportDetailState extends Equatable {
  final StatutDetailRapport statut;
  final Rapport? rapport;
  final List<EntreeHistoriqueRapport> historique;
  final List<PartageRapport> partages;
  final ActionDetailRapport action;
  final EvenementDetailRapport evenement;
  final String? erreur;

  /// La copie produite par « Dupliquer » — la page l'ouvre pour édition.
  final Rapport? copie;

  /// Résultat de la génération par entreprise (§ 15).
  final ResultatParEntreprise? parEntreprise;

  const RapportDetailState({
    this.statut = StatutDetailRapport.chargement,
    this.rapport,
    this.historique = const [],
    this.partages = const [],
    this.action = ActionDetailRapport.aucune,
    this.evenement = EvenementDetailRapport.aucun,
    this.erreur,
    this.copie,
    this.parEntreprise,
  });

  bool get occupe => action != ActionDetailRapport.aucune;

  RapportDetailState copyWith({
    StatutDetailRapport? statut,
    Rapport? rapport,
    List<EntreeHistoriqueRapport>? historique,
    List<PartageRapport>? partages,
    ActionDetailRapport? action,
    EvenementDetailRapport? evenement,
    String? erreur,
    Rapport? copie,
    ResultatParEntreprise? parEntreprise,
  }) =>
      RapportDetailState(
        statut: statut ?? this.statut,
        rapport: rapport ?? this.rapport,
        historique: historique ?? this.historique,
        partages: partages ?? this.partages,
        action: action ?? this.action,
        // Ponctuels : ils décrivent l'action qui vient de se terminer, et
        // ne doivent pas se rejouer à l'émission suivante.
        evenement: evenement ?? EvenementDetailRapport.aucun,
        erreur: erreur,
        copie: copie,
        parEntreprise: parEntreprise,
      );

  @override
  List<Object?> get props => [statut, rapport, historique, partages, action, evenement, erreur, copie, parEntreprise];
}

/// Le détail d'un rapport : fichiers, diffusion, historique, versions.
class RapportDetailCubit extends Cubit<RapportDetailState> {
  final String rapportId;
  final GetDetailRapport getDetail;
  final GetHistoriqueRapport getHistorique;
  final GetPartagesRapport getPartages;
  final GenererRapportConfigure genererRapport;
  final DupliquerRapport dupliquerRapport;
  final ArchiverRapport archiverRapport;
  final GenererRapportsParEntreprise genererParEntreprise;
  final PartagerRapport partagerRapport;
  final RevoquerPartageRapport revoquerPartage;

  /// Les liens de partage exposent qui a consulté le rapport : le serveur les
  /// réserve au pilotage, et un autre rôle recevrait un refus. On ne les
  /// demande donc qu'à qui peut les voir.
  final bool avecPartages;

  RapportDetailCubit({
    required this.rapportId,
    required this.getDetail,
    required this.getHistorique,
    required this.getPartages,
    required this.genererRapport,
    required this.dupliquerRapport,
    required this.archiverRapport,
    required this.genererParEntreprise,
    required this.partagerRapport,
    required this.revoquerPartage,
    this.avecPartages = false,
  }) : super(const RapportDetailState());

  Future<void> charger() async {
    if (state.rapport == null) emit(state.copyWith(statut: StatutDetailRapport.chargement));

    final resultats = await Future.wait<Either<Failure, Object>>([
      getDetail(rapportId),
      getHistorique(rapportId),
      if (avecPartages) getPartages(rapportId),
    ]);
    if (isClosed) return;

    String? echec;
    Rapport? rapport;
    List<EntreeHistoriqueRapport>? historique;
    List<PartageRapport>? partages;
    resultats[0].fold((f) => echec = f.errorMessage, (r) => rapport = r as Rapport);
    // L'historique et les partages sont des COMPLÉMENTS : leur échec ne doit
    // pas masquer le rapport lui-même.
    resultats[1].fold((_) {}, (h) => historique = h as List<EntreeHistoriqueRapport>);
    if (avecPartages) resultats[2].fold((_) {}, (p) => partages = p as List<PartageRapport>);

    if (rapport == null) {
      emit(state.copyWith(statut: StatutDetailRapport.erreur, erreur: echec));
      return;
    }
    emit(state.copyWith(
      statut: StatutDetailRapport.succes,
      rapport: rapport,
      historique: historique ?? state.historique,
      partages: partages ?? state.partages,
    ));
  }

  /// Génère ou régénère. Sur un rapport DIFFUSÉ, le serveur crée une
  /// nouvelle version (§ 18) : l'écran bascule alors sur elle.
  Future<Rapport?> generer() async {
    if (state.occupe) return null;
    emit(state.copyWith(action: ActionDetailRapport.generation));
    final resultat = await genererRapport(rapportId);
    if (isClosed) return null;
    return resultat.fold(
      (f) {
        emit(state.copyWith(action: ActionDetailRapport.aucune, erreur: f.errorMessage));
        return null;
      },
      (rapport) {
        if (rapport.id == rapportId) {
          emit(state.copyWith(
            action: ActionDetailRapport.aucune,
            rapport: rapport,
            evenement: EvenementDetailRapport.genere,
          ));
          charger();
        } else {
          // Un identifiant DIFFÉRENT est, par définition, une nouvelle
          // version. Le serveur en crée une pour un rapport envoyé, mais
          // aussi dès qu'un lien de partage est actif : se fier à
          // `estDiffuse` annonçait « Rapport généré » dans ce second cas.
          emit(state.copyWith(
            action: ActionDetailRapport.aucune,
            evenement: EvenementDetailRapport.nouvelleVersion,
          ));
        }
        return rapport;
      },
    );
  }

  Future<void> dupliquer() async {
    if (state.occupe) return;
    emit(state.copyWith(action: ActionDetailRapport.duplication));
    final resultat = await dupliquerRapport(rapportId);
    if (isClosed) return;
    resultat.fold(
      (f) => emit(state.copyWith(action: ActionDetailRapport.aucune, erreur: f.errorMessage)),
      (copie) => emit(state.copyWith(
        action: ActionDetailRapport.aucune,
        evenement: EvenementDetailRapport.duplique,
        copie: copie,
      )),
    );
  }

  Future<void> archiver() async {
    if (state.occupe) return;
    emit(state.copyWith(action: ActionDetailRapport.archivage));
    final resultat = await archiverRapport(rapportId);
    if (isClosed) return;
    resultat.fold(
      (f) => emit(state.copyWith(action: ActionDetailRapport.aucune, erreur: f.errorMessage)),
      (rapport) {
        emit(state.copyWith(
          action: ActionDetailRapport.aucune,
          rapport: rapport,
          evenement: EvenementDetailRapport.archive,
        ));
        charger();
      },
    );
  }

  /// § 15 — un document distinct par entreprise.
  Future<void> genererRapportsParEntreprise() async {
    if (state.occupe) return;
    emit(state.copyWith(action: ActionDetailRapport.parEntreprise));
    final resultat = await genererParEntreprise(rapportId);
    if (isClosed) return;
    resultat.fold(
      (f) => emit(state.copyWith(action: ActionDetailRapport.aucune, erreur: f.errorMessage)),
      (r) => emit(state.copyWith(
        action: ActionDetailRapport.aucune,
        evenement: EvenementDetailRapport.parEntreprise,
        parEntreprise: r,
      )),
    );
  }

  /// § 14 — crée un lien. Rendu à l'appelant, qui l'affiche UNE fois.
  Future<Either<Failure, LienPartageRapport>> partager({int? expireDansJours, bool authentificationRequise = false}) async {
    final resultat = await partagerRapport(
      rapportId,
      expireDansJours: expireDansJours,
      authentificationRequise: authentificationRequise,
    );
    if (!isClosed && resultat.isRight()) charger();
    return resultat;
  }

  Future<void> revoquer(String partageId) async {
    if (state.occupe) return;
    emit(state.copyWith(action: ActionDetailRapport.revocation));
    final resultat = await revoquerPartage(rapportId, partageId);
    if (isClosed) return;
    resultat.fold(
      (f) => emit(state.copyWith(action: ActionDetailRapport.aucune, erreur: f.errorMessage)),
      (_) {
        emit(state.copyWith(action: ActionDetailRapport.aucune, evenement: EvenementDetailRapport.revoque));
        charger();
      },
    );
  }
}
