import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../plan/domain/entities/plan.dart';
import '../../../plan/domain/usecases/get_plans_chantier.dart';
import '../../../plan/domain/usecases/uploader_plan.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../referentiel/domain/usecases/creer_code_niveau.dart';
import '../../../referentiel/domain/usecases/get_codes_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../../../reserve/domain/usecases/get_chantier_structure.dart';
import '../../domain/usecases/creer_structure.dart';

enum DepotStatus { chargement, pret, erreur }

class DepotPlansState extends Equatable {
  final DepotStatus status;

  /// Bâtiments du chantier, avec leurs niveaux.
  final List<BatimentStructure> batiments;

  /// Plans déjà déposés, tous niveaux confondus. Sert à savoir ce qui est
  /// couvert et ce qui reste à fournir.
  final List<Plan> plans;

  /// Codes proposés à la saisie, toutes sections confondues.
  final List<CodeNiveau> codes;

  /// `true` pendant un envoi. La liste reste affichée : la remplacer par un
  /// squelette à chaque dépôt donnerait l'impression que l'écran redémarre.
  final bool envoiEnCours;

  final String? erreur;
  final String? messageSucces;

  const DepotPlansState({
    this.status = DepotStatus.chargement,
    this.batiments = const [],
    this.plans = const [],
    this.codes = const [],
    this.envoiEnCours = false,
    this.erreur,
    this.messageSucces,
  });

  /// Codes d'une section, dans l'ordre physique donné par le serveur.
  List<CodeNiveau> codesDe(TypeNiveau type) =>
      codes.where((c) => c.typeNiveau == type).toList();

  DepotPlansState copyWith({
    DepotStatus? status,
    List<BatimentStructure>? batiments,
    List<Plan>? plans,
    List<CodeNiveau>? codes,
    bool? envoiEnCours,
    String? erreur,
    String? messageSucces,
    bool effacerMessages = false,
  }) {
    return DepotPlansState(
      status: status ?? this.status,
      batiments: batiments ?? this.batiments,
      plans: plans ?? this.plans,
      codes: codes ?? this.codes,
      envoiEnCours: envoiEnCours ?? this.envoiEnCours,
      erreur: effacerMessages ? null : (erreur ?? this.erreur),
      messageSucces: effacerMessages ? null : (messageSucces ?? this.messageSucces),
    );
  }

  @override
  List<Object?> get props =>
      [status, batiments, plans, codes, envoiEnCours, erreur, messageSucces];
}

/// Dépôt des plans d'un chantier — plan global, bâtiments, niveaux.
///
/// ── Envoi immédiat, et non différé ────────────────────────────────────────
/// Chaque ajout part au serveur sur-le-champ, plutôt que d'accumuler un
/// brouillon envoyé à la fin. Sur un chantier, l'application se ferme, la
/// batterie tombe, le réseau saute : un brouillon de dix plans perdu à la
/// dernière seconde serait bien pire qu'un dépôt partiel, qui se complète en
/// rouvrant l'écran.
///
/// C'est aussi ce que demande le client : « les plans sont immédiatement
/// rattachés à ce chantier ».
class DepotPlansCubit extends Cubit<DepotPlansState> {
  final String chantierId;

  final GetChantierStructure getStructure;
  final GetPlansChantier getPlans;
  final GetCodesNiveau getCodes;
  final CreerCodeNiveau creerCode;
  final CreerBatiment creerBatiment;
  final CreerEtage creerEtage;
  final UploaderPlan uploaderPlan;

  DepotPlansCubit({
    required this.chantierId,
    required this.getStructure,
    required this.getPlans,
    required this.getCodes,
    required this.creerCode,
    required this.creerBatiment,
    required this.creerEtage,
    required this.uploaderPlan,
  }) : super(const DepotPlansState());

  Future<void> charger() async {
    emit(state.copyWith(status: DepotStatus.chargement, effacerMessages: true));

    final structure = await getStructure(chantierId);
    if (isClosed) return;

    final echec = structure.fold((e) => e, (_) => null);
    if (echec != null) {
      emit(state.copyWith(status: DepotStatus.erreur, erreur: echec.errorMessage));
      return;
    }

    // Plans et codes en parallèle : ni l'un ni l'autre ne dépend de l'autre,
    // et les enchaîner doublerait l'attente sur un réseau de chantier.
    final resultats = await Future.wait([getPlans(chantierId), getCodes()]);
    if (isClosed) return;

    emit(state.copyWith(
      status: DepotStatus.pret,
      batiments: structure.fold((_) => const <BatimentStructure>[], (s) => s.batiments),
      // Un échec sur les plans ou les codes n'empêche PAS de déposer : la
      // liste s'affiche vide, et l'essentiel — l'ajout — reste possible.
      plans: (resultats[0] as dynamic).fold((_) => const <Plan>[], (p) => p) as List<Plan>,
      codes: (resultats[1] as dynamic).fold((_) => const <CodeNiveau>[], (c) => c) as List<CodeNiveau>,
    ));
  }

  /// Dépose le plan GLOBAL — celui du chantier, sans bâtiment ni niveau.
  Future<void> deposerPlanGlobal({required String cheminFichier, required String nom}) async {
    await _envoyer(() async {
      final result = await uploaderPlan(
        chantierId: chantierId, cheminFichier: cheminFichier, nom: nom,
      );
      return result.fold((e) => e.errorMessage, (_) => null);
    });
  }

  Future<void> ajouterBatiment({required String nom, String? code}) async {
    await _envoyer(() async {
      final result = await creerBatiment(chantierId, nom: nom, code: code);
      return result.fold((e) => e.errorMessage, (_) => null);
    });
  }

  /// Crée un niveau et y dépose son plan.
  ///
  /// Les deux vont ENSEMBLE : un niveau sans plan n'a pas d'intérêt dans ce
  /// parcours, et un plan sans niveau n'a nulle part où se rattacher. Si le
  /// dépôt échoue après la création, le niveau subsiste — on le signale plutôt
  /// que de le supprimer, l'utilisateur n'ayant qu'à réessayer le fichier.
  Future<void> ajouterNiveau({
    required String batimentId,
    required TypeNiveau typeNiveau,
    required String codeNiveau,
    String? description,
    String? cheminFichier,
    String? nomFichier,
  }) async {
    await _envoyer(() async {
      final creation = await creerEtage(
        chantierId,
        batimentId,
        // Le code fait office de nom : c'est ainsi que le niveau sera lu sur
        // les écrans (« SS1 », « R+2 »), et demander un nom en plus du code
        // ferait saisir deux fois la même chose.
        nom: codeNiveau,
        typeNiveau: typeNiveau,
        codeNiveau: codeNiveau,
        description: description,
      );

      final echec = creation.fold((e) => e.errorMessage, (_) => null);
      if (echec != null) return echec;

      if (cheminFichier == null) return null;

      final etage = creation.fold((_) => null, (e) => e);
      final depot = await uploaderPlan(
        chantierId: chantierId,
        cheminFichier: cheminFichier,
        nom: nomFichier ?? codeNiveau,
        etageId: etage?.id,
      );
      return depot.fold((e) => e.errorMessage, (_) => null);
    });
  }

  /// Crée un code absent de la liste, et le rend immédiatement sélectionnable.
  ///
  /// Renvoie le code créé, ou `null` en cas d'échec — l'appelant s'en sert
  /// pour présélectionner ce que l'utilisateur vient de taper.
  Future<CodeNiveau?> ajouterCode({
    required TypeNiveau typeNiveau,
    required String code,
  }) async {
    final result = await creerCode(typeNiveau: typeNiveau, code: code);
    if (isClosed) return null;

    return result.fold(
      (echec) {
        emit(state.copyWith(erreur: echec.errorMessage));
        return null;
      },
      (cree) {
        emit(state.copyWith(codes: [...state.codes, cree], effacerMessages: true));
        return cree;
      },
    );
  }

  /// À appeler après affichage, pour qu'un rebuild ne rejoue pas la même
  /// notification.
  void effacerMessages() {
    if (state.erreur == null && state.messageSucces == null) return;
    emit(state.copyWith(effacerMessages: true));
  }

  /// Exécute un envoi, puis RECHARGE.
  ///
  /// Le rechargement plutôt qu'une insertion locale : le serveur attribue le
  /// numéro de version d'un plan et l'ordre des niveaux. Reconstituer ces
  /// valeurs à la main finirait par diverger de ce que renverra le prochain
  /// chargement.
  Future<void> _envoyer(Future<String?> Function() action) async {
    if (state.envoiEnCours) return;
    emit(state.copyWith(envoiEnCours: true, effacerMessages: true));

    final erreur = await action();
    if (isClosed) return;

    if (erreur != null) {
      emit(state.copyWith(envoiEnCours: false, erreur: erreur));
      return;
    }

    await charger();
    if (isClosed) return;
    emit(state.copyWith(envoiEnCours: false));
  }
}
