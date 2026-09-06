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

/// Un fichier choisi, pas encore téléversé.
class _FichierEnAttente {
  final String chemin;
  final String nom;
  const _FichierEnAttente({required this.chemin, required this.nom});
}

/// Un niveau saisi avant que le chantier n'existe.
///
/// On retient le CHEMIN du fichier, pas son contenu : les octets restent sur
/// l'appareil, et la mémoire de l'application ne grossit pas avec le nombre de
/// plans.
class _NiveauEnAttente {
  final String batimentTempId;
  final String niveauTempId;
  final TypeNiveau typeNiveau;
  final String codeNiveau;
  final String? description;
  final String? cheminFichier;
  final String? nomFichier;

  const _NiveauEnAttente({
    required this.batimentTempId,
    required this.niveauTempId,
    required this.typeNiveau,
    required this.codeNiveau,
    this.description,
    this.cheminFichier,
    this.nomFichier,
  });
}

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
/// ── Deux modes, et pourquoi ───────────────────────────────────────────────
///
/// **Chantier existant** ([chantierId] renseigné) : chaque ajout part au
/// serveur sur-le-champ. Sur un chantier, l'application se ferme, la batterie
/// tombe, le réseau saute — un dépôt partiel se complète en rouvrant l'écran,
/// là où un brouillon perdu à la dernière seconde ne se rattrape pas.
///
/// **Brouillon** ([chantierId] nul) : le parcours décrit par le client
/// commence par les PLANS et finit par le formulaire de chantier —
/// « Envoyer → Plans envoyés → formulaire de demande ». Or un plan ne peut
/// pas être envoyé avant que le chantier n'existe : `POST
/// /chantiers/:chantierId/plans` exige un identifiant. La saisie est donc
/// retenue ici, puis rejouée d'un bloc par [envoyerVers] dès que la demande
/// est créée.
///
/// Ce mode apporte autre chose que l'ordre demandé : le courriel des
/// valideurs part UNE fois, sur une demande complète. Avec le formulaire en
/// premier, il annonçait un chantier vide, les plans arrivant après.
///
/// Ce qui est retenu, ce sont des CHEMINS de fichiers, pas leur contenu : les
/// fichiers restent sur l'appareil. Une application tuée avant l'envoi fait
/// perdre la sélection — le code, la description, le fichier choisi — jamais
/// les fichiers eux-mêmes.
class DepotPlansCubit extends Cubit<DepotPlansState> {
  /// Chantier visé, ou `null` tant qu'il n'existe pas (mode brouillon).
  ///
  /// Non final : [envoyerVers] le renseigne au moment où la demande est créée,
  /// et l'écran continue alors sa vie en mode normal.
  String? chantierId;

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

  /// Saisie retenue tant que le chantier n'existe pas.
  final List<_NiveauEnAttente> _niveauxEnAttente = [];
  _FichierEnAttente? _globalEnAttente;
  final Map<String, String> _nomsBatimentsTemp = {};

  /// Compteur des identifiants LOCAUX. Préfixés pour qu'un identifiant
  /// temporaire ne puisse jamais être confondu avec un identifiant serveur.
  int _compteurTemp = 0;
  String _prochainIdTemp() => 'brouillon-${++_compteurTemp}';

  /// Le chantier reste-t-il à créer ?
  bool get brouillon => chantierId == null;

  /// Y a-t-il quelque chose à envoyer ? Une demande sans le moindre plan
  /// n'aurait rien à faire examiner.
  bool get aQuelqueChoseAEnvoyer =>
      _globalEnAttente != null || _niveauxEnAttente.isNotEmpty;

  Future<void> charger() async {
    // En brouillon il n'y a ni structure ni plans à relire : rien n'existe
    // encore côté serveur. Seuls les CODES viennent de la base — ils sont
    // partagés par toute l'organisation, et c'est justement ce qui permet à
    // l'entreprise d'en créer un que le suivant retrouvera.
    if (brouillon) {
      emit(state.copyWith(status: DepotStatus.chargement, effacerMessages: true));
      final codes = await getCodes();
      if (isClosed) return;
      emit(state.copyWith(
        status: DepotStatus.pret,
        codes: codes.fold((_) => const <CodeNiveau>[], (c) => c),
      ));
      return;
    }

    return _chargerDepuisServeur();
  }

  Future<void> _chargerDepuisServeur() async {
    emit(state.copyWith(status: DepotStatus.chargement, effacerMessages: true));

    final structure = await getStructure(chantierId!);
    if (isClosed) return;

    final echec = structure.fold((e) => e, (_) => null);
    if (echec != null) {
      emit(state.copyWith(status: DepotStatus.erreur, erreur: echec.errorMessage));
      return;
    }

    // Plans et codes en parallèle : ni l'un ni l'autre ne dépend de l'autre,
    // et les enchaîner doublerait l'attente sur un réseau de chantier.
    final resultats = await Future.wait([getPlans(chantierId!), getCodes()]);
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
    if (brouillon) {
      // Un seul plan global : le second REMPLACE le premier, comme le ferait
      // le serveur en créant une nouvelle version. Empiler deux fichiers
      // laisserait l'utilisateur devant deux lignes sans savoir laquelle part.
      _globalEnAttente = _FichierEnAttente(chemin: cheminFichier, nom: nom);
      emit(state.copyWith(
        plans: [
          ...state.plans.where((p) => !_estGlobal(p)),
          _planLocal(nom: nom, etageId: null),
        ],
        effacerMessages: true,
      ));
      return;
    }

    await _envoyer(() async {
      final result = await uploaderPlan(
        chantierId: chantierId!, cheminFichier: cheminFichier, nom: nom,
      );
      return result.fold((e) => e.errorMessage, (_) => null);
    });
  }

  Future<void> ajouterBatiment({required String nom, String? code}) async {
    if (brouillon) {
      final id = _prochainIdTemp();
      _nomsBatimentsTemp[id] = nom;
      emit(state.copyWith(
        batiments: [...state.batiments, BatimentStructure(id: id, nom: nom)],
        effacerMessages: true,
      ));
      return;
    }

    await _envoyer(() async {
      final result = await creerBatiment(chantierId!, nom: nom, code: code);
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
    if (brouillon) {
      _retenirNiveau(
        batimentId: batimentId,
        typeNiveau: typeNiveau,
        codeNiveau: codeNiveau,
        description: description,
        cheminFichier: cheminFichier,
        nomFichier: nomFichier,
      );
      return;
    }

    await _envoyer(() async {
      final creation = await creerEtage(
        chantierId!,
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
        chantierId: chantierId!,
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


  // ── Mode brouillon : retenir, puis rejouer ───────────────────────────────

  /// Un plan sans bâtiment ni niveau : le plan global du chantier.
  static bool _estGlobal(Plan p) => p.batiment == null && p.etage == null && p.zone == null;

  /// Un plan LOCAL, le temps du brouillon.
  ///
  /// Il n'existe que pour l'affichage : c'est lui qui coche la pastille d'un
  /// niveau servi et qui donne son nom au plan global. Son identifiant est
  /// préfixé « brouillon- » et son URL est vide — rien ici n'ira au serveur,
  /// seuls les chemins retenus à côté seront téléversés.
  Plan _planLocal({required String nom, required String? etageId}) => Plan(
        id: _prochainIdTemp(),
        chantierId: '',
        nom: nom,
        fichierUrl: '',
        format: PlanFormat.pdf,
        etage: etageId == null ? null : PlanNiveauRef(id: etageId, nom: nom),
      );

  void _retenirNiveau({
    required String batimentId,
    required TypeNiveau typeNiveau,
    required String codeNiveau,
    String? description,
    String? cheminFichier,
    String? nomFichier,
  }) {
    final idNiveau = _prochainIdTemp();
    _niveauxEnAttente.add(_NiveauEnAttente(
      batimentTempId: batimentId,
      niveauTempId: idNiveau,
      typeNiveau: typeNiveau,
      codeNiveau: codeNiveau,
      description: description,
      cheminFichier: cheminFichier,
      nomFichier: nomFichier,
    ));

    // Le niveau est inséré dans SON bâtiment pour que l'écran le montre
    // aussitôt, exactement comme un rechargement le ferait après un envoi.
    final batiments = [
      for (final b in state.batiments)
        if (b.id != batimentId)
          b
        else
          BatimentStructure(
            id: b.id,
            nom: b.nom,
            etages: [
              ...b.etages,
              EtageStructure(
                id: idNiveau,
                // Le code fait office de nom, comme côté serveur.
                nom: codeNiveau,
                typeNiveau: typeNiveau,
                codeNiveau: codeNiveau,
                description: description,
              ),
            ],
          ),
    ];

    emit(state.copyWith(
      batiments: batiments,
      plans: cheminFichier == null
          ? state.plans
          : [...state.plans, _planLocal(nom: nomFichier ?? codeNiveau, etageId: idNiveau)],
      effacerMessages: true,
    ));
  }

  /// Rejoue tout ce qui a été retenu sur le chantier qui vient d'être créé.
  ///
  /// L'ordre est imposé : un niveau appartient à un bâtiment, un plan de
  /// niveau a besoin de l'identifiant que le serveur vient d'attribuer. Les
  /// identifiants temporaires sont donc traduits au fur et à mesure.
  ///
  /// S'arrête au PREMIER échec et le renvoie. Ce qui est déjà passé reste en
  /// place : la demande existe, avec une partie de ses plans, et l'écran
  /// rouvert sur ce chantier — qui existe désormais — permet de compléter.
  /// Tout défaire serait pire : on effacerait un travail que rien ne
  /// permettrait de retrouver.
  ///
  /// @returns un message d'erreur, ou `null` si tout est parti.
  Future<String?> envoyerVers(String nouveauChantierId) async {
    if (state.envoiEnCours) return null;
    emit(state.copyWith(envoiEnCours: true, effacerMessages: true));

    String? echec;

    if (_globalEnAttente != null) {
      final r = await uploaderPlan(
        chantierId: nouveauChantierId,
        cheminFichier: _globalEnAttente!.chemin,
        nom: _globalEnAttente!.nom,
      );
      echec = r.fold((e) => e.errorMessage, (_) => null);
    }

    // Traduction des identifiants temporaires en identifiants serveur.
    final idsReels = <String, String>{};

    if (echec == null) {
      for (final entree in _nomsBatimentsTemp.entries) {
        final r = await creerBatiment(nouveauChantierId, nom: entree.value);
        final rate = r.fold((e) => e.errorMessage, (_) => null);
        if (rate != null) {
          echec = rate;
          break;
        }
        final cree = r.fold((_) => null, (b) => b);
        if (cree != null) idsReels[entree.key] = cree.id;
      }
    }

    if (echec == null) {
      for (final n in _niveauxEnAttente) {
        final batimentReel = idsReels[n.batimentTempId];
        if (batimentReel == null) continue;

        final creation = await creerEtage(
          nouveauChantierId,
          batimentReel,
          nom: n.codeNiveau,
          typeNiveau: n.typeNiveau,
          codeNiveau: n.codeNiveau,
          description: n.description,
        );
        final rate = creation.fold((e) => e.errorMessage, (_) => null);
        if (rate != null) {
          echec = rate;
          break;
        }

        if (n.cheminFichier == null) continue;
        final etage = creation.fold((_) => null, (e) => e);
        final depot = await uploaderPlan(
          chantierId: nouveauChantierId,
          cheminFichier: n.cheminFichier!,
          nom: n.nomFichier ?? n.codeNiveau,
          etageId: etage?.id,
        );
        final rateDepot = depot.fold((e) => e.errorMessage, (_) => null);
        if (rateDepot != null) {
          echec = rateDepot;
          break;
        }
      }
    }

    if (isClosed) return echec;

    // Le chantier existe : l'écran quitte le brouillon quoi qu'il arrive, et
    // un rechargement montrera l'état RÉEL du serveur — y compris ce qui n'est
    // pas passé.
    chantierId = nouveauChantierId;
    _globalEnAttente = null;
    _niveauxEnAttente.clear();
    _nomsBatimentsTemp.clear();

    emit(state.copyWith(envoiEnCours: false, erreur: echec));
    await _chargerDepuisServeur();
    return echec;
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
