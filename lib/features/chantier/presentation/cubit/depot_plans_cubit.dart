import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../plan/domain/entities/plan.dart';
import '../../../plan/domain/usecases/get_plans_chantier.dart';
import '../../../plan/domain/usecases/uploader_plan.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../referentiel/domain/entities/code_appartement.dart';
import '../../../referentiel/domain/usecases/codes_appartement.dart';
import '../../../referentiel/domain/usecases/creer_code_niveau.dart';
import '../../../referentiel/domain/usecases/get_codes_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../../../reserve/domain/usecases/get_chantier_structure.dart';
import '../../../plan/domain/usecases/gerer_plan.dart';
import '../../domain/usecases/creer_structure.dart';

enum DepotStatus { chargement, pret, erreur }

/// Un appartement saisi par l'utilisateur dans la feuille d'un niveau — un
/// code et, éventuellement, son plan.
///
/// Public : c'est ce que la feuille de saisie ([SaisieNiveau] dans
/// `niveau_sheet.dart`) construit et transmet à [DepotPlansCubit.ajouterNiveau].
class SaisieAppartement {
  final String code;
  final String? cheminFichier;
  final String? nomFichier;

  const SaisieAppartement({
    required this.code,
    this.cheminFichier,
    this.nomFichier,
  });
}

/// Un fichier de plan choisi pour un appartement — chemin et nom d'affichage.
///
/// Public : c'est ce que l'écran construit après une sélection de fichier et
/// transmet au cubit. Un appartement peut en porter plusieurs, le client l'a
/// demandé explicitement.
class SaisieFichierPlan {
  final String chemin;
  final String nom;

  const SaisieFichierPlan({required this.chemin, required this.nom});
}

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

  /// Les appartements du niveau, saisis dans la MÊME feuille — le client l'a
  /// demandé explicitement : ajouter plusieurs logements et leur plan avant
  /// de valider, pas un par un sur des écrans séparés.
  final List<_AppartementEnAttente> appartements;

  _NiveauEnAttente({
    required this.batimentTempId,
    required this.niveauTempId,
    required this.typeNiveau,
    required this.codeNiveau,
    this.description,
    this.cheminFichier,
    this.nomFichier,
    List<_AppartementEnAttente>? appartements,
  }) : appartements = appartements ?? <_AppartementEnAttente>[];
}

/// Un fichier de plan retenu pour un appartement, le temps du brouillon.
///
/// [idLocal] est l'identifiant du [Plan] d'affichage correspondant : c'est lui
/// qui permet de retrouver le fichier à retirer quand l'utilisateur supprime
/// une vignette, sans avoir à deviner par le nom — deux plans peuvent porter
/// le même.
class _FichierPlan {
  final String idLocal;
  final String chemin;
  final String nom;

  const _FichierPlan({required this.idLocal, required this.chemin, required this.nom});
}

/// Un appartement saisi avant que le chantier — et donc l'appartement —
/// n'existe côté serveur.
///
/// Mutable, contrairement au reste des structures en attente : le client veut
/// pouvoir renommer un appartement et lui ajouter des plans APRÈS l'avoir
/// créé, sans repasser par la feuille du niveau.
class _AppartementEnAttente {
  final String zoneTempId;
  String code;
  final List<_FichierPlan> plans;

  _AppartementEnAttente({
    required this.zoneTempId,
    required this.code,
    List<_FichierPlan>? plans,
  }) : plans = plans ?? <_FichierPlan>[];
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

  /// Codes d'APPARTEMENT proposés à la saisie — « A001 » à « A015 », plus
  /// ceux que l'organisation a ajoutés.
  ///
  /// Le code d'appartement était un champ libre : deux utilisateurs
  /// saisissaient « A001 » et « A-001 » pour le même logement. Le client a
  /// demandé la même liste que pour les niveaux.
  final List<CodeAppartement> codesAppartement;

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
    this.codesAppartement = const [],
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
    List<CodeAppartement>? codesAppartement,
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
      codesAppartement: codesAppartement ?? this.codesAppartement,
      envoiEnCours: envoiEnCours ?? this.envoiEnCours,
      erreur: effacerMessages ? null : (erreur ?? this.erreur),
      messageSucces: effacerMessages ? null : (messageSucces ?? this.messageSucces),
    );
  }

  @override
  List<Object?> get props =>
      [status, batiments, plans, codes, codesAppartement, envoiEnCours, erreur, messageSucces];
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
  final GetCodesAppartement getCodesAppartement;
  final CreerCodeAppartement creerCodeAppartement;
  final CreerBatiment creerBatiment;
  final CreerEtage creerEtage;
  final CreerZone creerZone;
  final ModifierZone modifierZone;
  final SupprimerZone supprimerZone;
  final SupprimerPlan supprimerPlan;
  final RemplacerFichierPlan remplacerFichierPlan;
  final UploaderPlan uploaderPlan;

  DepotPlansCubit({
    required this.chantierId,
    required this.getStructure,
    required this.getPlans,
    required this.getCodes,
    required this.creerCode,
    required this.getCodesAppartement,
    required this.creerCodeAppartement,
    required this.creerBatiment,
    required this.creerEtage,
    required this.creerZone,
    required this.modifierZone,
    required this.supprimerZone,
    required this.supprimerPlan,
    required this.remplacerFichierPlan,
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
      // Les DEUX référentiels : niveaux et appartements. Le second manquait —
      // la feuille de niveau aurait proposé une liste d'appartements vide en
      // mode brouillon, c'est-à-dire précisément dans le parcours « plans
      // d'abord, demande ensuite » que le client a décrit.
      final resultats = await Future.wait([getCodes(), getCodesAppartement()]);
      if (isClosed) return;
      emit(state.copyWith(
        status: DepotStatus.pret,
        codes: (resultats[0] as dynamic).fold((_) => const <CodeNiveau>[], (c) => c) as List<CodeNiveau>,
        codesAppartement: (resultats[1] as dynamic)
            .fold((_) => const <CodeAppartement>[], (c) => c) as List<CodeAppartement>,
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
    final resultats = await Future.wait([
      getPlans(chantierId!),
      getCodes(),
      getCodesAppartement(),
    ]);
    if (isClosed) return;

    emit(state.copyWith(
      status: DepotStatus.pret,
      batiments: structure.fold((_) => const <BatimentStructure>[], (s) => s.batiments),
      // Un échec sur les plans ou les codes n'empêche PAS de déposer : la
      // liste s'affiche vide, et l'essentiel — l'ajout — reste possible.
      plans: (resultats[0] as dynamic).fold((_) => const <Plan>[], (p) => p) as List<Plan>,
      codes: (resultats[1] as dynamic).fold((_) => const <CodeNiveau>[], (c) => c) as List<CodeNiveau>,
      codesAppartement: (resultats[2] as dynamic)
          .fold((_) => const <CodeAppartement>[], (c) => c) as List<CodeAppartement>,
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

  /// Crée un niveau, dépose éventuellement son plan, puis crée chacun de ses
  /// appartements avec le sien.
  ///
  /// Niveau et plan vont ENSEMBLE : un niveau sans plan n'a pas d'intérêt dans
  /// ce parcours, et un plan sans niveau n'a nulle part où se rattacher. Les
  /// appartements suivent la même logique, un cran plus bas — c'est le client
  /// qui l'a demandé : « pouvoir mettre les plans de chaque appartement avant
  /// d'enregistrer le tout », en un seul geste depuis la feuille du niveau.
  ///
  /// L'ordre est CONTRAINT : un appartement appartient au niveau, il ne peut
  /// donc être créé qu'une fois celui-ci enregistré et son identifiant connu.
  ///
  /// Si un dépôt échoue en cours de route, on s'arrête LÀ : le niveau et les
  /// appartements déjà créés subsistent — on le signale plutôt que de tout
  /// défaire, l'utilisateur n'ayant qu'à corriger et réessayer ce qui manque.
  Future<void> ajouterNiveau({
    required String batimentId,
    required TypeNiveau typeNiveau,
    required String codeNiveau,
    String? description,
    String? cheminFichier,
    String? nomFichier,
    List<SaisieAppartement> appartements = const [],
  }) async {
    if (brouillon) {
      _retenirNiveau(
        batimentId: batimentId,
        typeNiveau: typeNiveau,
        codeNiveau: codeNiveau,
        description: description,
        cheminFichier: cheminFichier,
        nomFichier: nomFichier,
        appartements: appartements,
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

      final echecNiveau = creation.fold((e) => e.errorMessage, (_) => null);
      if (echecNiveau != null) return echecNiveau;

      final etage = creation.fold((_) => null, (e) => e);

      if (cheminFichier != null) {
        final depot = await uploaderPlan(
          chantierId: chantierId!,
          cheminFichier: cheminFichier,
          nom: nomFichier ?? codeNiveau,
          etageId: etage?.id,
        );
        final echecPlan = depot.fold((e) => e.errorMessage, (_) => null);
        if (echecPlan != null) return echecPlan;
      }

      // Les appartements, un par un — chacun a besoin de l'identifiant DU
      // NIVEAU qui vient d'être créé, jamais d'un identifiant temporaire.
      for (final a in appartements) {
        final creationZone = await creerZone(
          chantierId!, batimentId, etage!.id, nom: a.code,
        );
        final echecZone = creationZone.fold((e) => e.errorMessage, (_) => null);
        if (echecZone != null) return echecZone;

        if (a.cheminFichier == null) continue;

        final zone = creationZone.fold((_) => null, (z) => z);
        final depotZone = await uploaderPlan(
          chantierId: chantierId!,
          cheminFichier: a.cheminFichier!,
          nom: a.nomFichier ?? a.code,
          zoneId: zone?.id,
        );
        final echecDepotZone = depotZone.fold((e) => e.errorMessage, (_) => null);
        if (echecDepotZone != null) return echecDepotZone;
      }

      return null;
    });
  }

  /// Crée un code d'appartement absent de la liste, et le rend immédiatement
  /// sélectionnable.
  ///
  /// Renvoie le code créé, ou `null` en cas d'échec — l'appelant s'en sert
  /// pour présélectionner ce que l'utilisateur vient de taper.
  Future<CodeAppartement?> ajouterCodeAppartement(String code) async {
    final result = await creerCodeAppartement(code: code);
    if (isClosed) return null;

    return result.fold(
      (echec) {
        emit(state.copyWith(erreur: echec.errorMessage));
        return null;
      },
      (cree) {
        emit(state.copyWith(
          codesAppartement: [...state.codesAppartement, cree],
          effacerMessages: true,
        ));
        return cree;
      },
    );
  }

  // ── Appartements d'un niveau, et leurs plans ─────────────────────────────
  //
  // Le client : « Alors là il faut qu'on puisse voir du R+1 avec tous les
  // plans des appartements à l'intérieur. Du R+2 avec tous les plans des
  // appartements à l'intérieur, ainsi de suite. »
  //
  // Les appartements VIENNENT DU SERVEUR (`EtageStructure.zones`, servi par la
  // structure du chantier) ; ces méthodes ne servent qu'à compléter ce qui
  // manque et à corriger ce qui est faux.

  /// Ajoute un appartement à un niveau, avec ses éventuels premiers plans.
  Future<void> ajouterAppartement({
    required String batimentId,
    required String etageId,
    required String code,
    List<SaisieFichierPlan> plans = const [],
  }) async {
    if (brouillon) {
      _retenirAppartement(
        batimentId: batimentId,
        etageId: etageId,
        code: code,
        plans: plans,
      );
      return;
    }

    await _envoyer(() async {
      final creation = await creerZone(chantierId!, batimentId, etageId, nom: code);
      final echec = creation.fold((e) => e.errorMessage, (_) => null);
      if (echec != null) return echec;

      final zone = creation.fold((_) => null, (z) => z);
      for (final f in plans) {
        final depot = await uploaderPlan(
          chantierId: chantierId!,
          cheminFichier: f.chemin,
          nom: f.nom,
          zoneId: zone?.id,
        );
        final rate = depot.fold((e) => e.errorMessage, (_) => null);
        if (rate != null) return rate;
      }
      return null;
    });
  }

  /// Renomme un appartement.
  Future<void> renommerAppartement({
    required String batimentId,
    required String etageId,
    required String zoneId,
    required String nom,
  }) async {
    if (brouillon) {
      for (final n in _niveauxEnAttente) {
        for (final a in n.appartements) {
          if (a.zoneTempId == zoneId) a.code = nom;
        }
      }
      emit(state.copyWith(batiments: _batimentsAvecZoneRenommee(zoneId, nom), effacerMessages: true));
      return;
    }

    await _envoyer(() async {
      final r = await modifierZone(chantierId!, batimentId, etageId, zoneId, nom: nom);
      return r.fold((e) => e.errorMessage, (_) => null);
    });
  }

  /// Supprime un appartement — et, côté serveur, les plans qui s'y rattachent.
  ///
  /// Le serveur REFUSE tant qu'une réserve pointe sur l'appartement ; son
  /// message remonte tel quel, c'est lui qui explique le blocage.
  Future<void> supprimerAppartement({
    required String batimentId,
    required String etageId,
    required String zoneId,
  }) async {
    if (brouillon) {
      for (final n in _niveauxEnAttente) {
        n.appartements.removeWhere((a) => a.zoneTempId == zoneId);
      }
      emit(state.copyWith(
        batiments: _batimentsSansZone(zoneId),
        plans: state.plans.where((p) => p.zone?.id != zoneId).toList(),
        effacerMessages: true,
      ));
      return;
    }

    await _envoyer(() async {
      final r = await supprimerZone(chantierId!, batimentId, etageId, zoneId);
      return r.fold((e) => e.errorMessage, (_) => null);
    });
  }

  /// Ajoute un plan À UN APPARTEMENT — le geste « + Ajouter un plan ».
  Future<void> ajouterPlanAppartement({
    required String zoneId,
    required String cheminFichier,
    required String nom,
  }) async {
    if (brouillon) {
      final idLocal = _prochainIdTemp();
      for (final n in _niveauxEnAttente) {
        for (final a in n.appartements) {
          if (a.zoneTempId != zoneId) continue;
          a.plans.add(_FichierPlan(idLocal: idLocal, chemin: cheminFichier, nom: nom));
        }
      }
      emit(state.copyWith(
        plans: [...state.plans, _planLocal(id: idLocal, nom: nom, zoneId: zoneId)],
        effacerMessages: true,
      ));
      return;
    }

    await _envoyer(() async {
      final r = await uploaderPlan(
        chantierId: chantierId!,
        cheminFichier: cheminFichier,
        nom: nom,
        zoneId: zoneId,
      );
      return r.fold((e) => e.errorMessage, (_) => null);
    });
  }

  /// REMPLACE le document d'un plan.
  ///
  /// Une nouvelle version côté serveur, jamais un second plan : le nom, le
  /// rattachement et les réserves déjà posées sont conservés.
  Future<void> remplacerPlan({
    required String planId,
    required String cheminFichier,
    required String nom,
  }) async {
    if (brouillon) {
      // Rien n'est encore parti : on échange simplement le fichier retenu.
      for (final n in _niveauxEnAttente) {
        for (final a in n.appartements) {
          final i = a.plans.indexWhere((f) => f.idLocal == planId);
          if (i < 0) continue;
          a.plans[i] = _FichierPlan(idLocal: planId, chemin: cheminFichier, nom: nom);
        }
      }
      emit(state.copyWith(
        plans: [
          for (final p in state.plans)
            if (p.id != planId)
              p
            else
              _planLocal(id: planId, nom: nom, zoneId: p.zone?.id, etageId: p.etage?.id),
        ],
        effacerMessages: true,
      ));
      return;
    }

    await _envoyer(() async {
      final r = await remplacerFichierPlan(planId, cheminFichier: cheminFichier);
      return r.fold((e) => e.errorMessage, (_) => null);
    });
  }

  /// Supprime un plan.
  Future<void> supprimerPlanFichier(String planId) async {
    if (brouillon) {
      for (final n in _niveauxEnAttente) {
        for (final a in n.appartements) {
          a.plans.removeWhere((f) => f.idLocal == planId);
        }
      }
      emit(state.copyWith(
        plans: state.plans.where((p) => p.id != planId).toList(),
        effacerMessages: true,
      ));
      return;
    }

    await _envoyer(() async {
      final r = await supprimerPlan(planId);
      return r.fold((e) => e.errorMessage, (_) => null);
    });
  }

  /// Retient un appartement ajouté à un niveau encore en brouillon.
  void _retenirAppartement({
    required String batimentId,
    required String etageId,
    required String code,
    required List<SaisieFichierPlan> plans,
  }) {
    final zoneTempId = _prochainIdTemp();
    final fichiers = [
      for (final f in plans)
        _FichierPlan(idLocal: _prochainIdTemp(), chemin: f.chemin, nom: f.nom),
    ];

    for (final n in _niveauxEnAttente) {
      if (n.niveauTempId != etageId) continue;
      n.appartements.add(
        _AppartementEnAttente(zoneTempId: zoneTempId, code: code, plans: fichiers),
      );
    }

    emit(state.copyWith(
      batiments: [
        for (final b in state.batiments)
          if (b.id != batimentId)
            b
          else
            BatimentStructure(
              id: b.id,
              nom: b.nom,
              etages: [
                for (final e in b.etages)
                  if (e.id != etageId)
                    e
                  else
                    EtageStructure(
                      id: e.id,
                      nom: e.nom,
                      niveau: e.niveau,
                      typeNiveau: e.typeNiveau,
                      codeNiveau: e.codeNiveau,
                      description: e.description,
                      zones: [...e.zones, ZoneStructure(id: zoneTempId, nom: code)],
                    ),
              ],
            ),
      ],
      plans: [
        ...state.plans,
        for (final f in fichiers) _planLocal(id: f.idLocal, nom: f.nom, zoneId: zoneTempId),
      ],
      effacerMessages: true,
    ));
  }

  /// La structure, avec un appartement renommé.
  List<BatimentStructure> _batimentsAvecZoneRenommee(String zoneId, String nom) => [
        for (final b in state.batiments)
          BatimentStructure(
            id: b.id,
            nom: b.nom,
            etages: [
              for (final e in b.etages)
                EtageStructure(
                  id: e.id,
                  nom: e.nom,
                  niveau: e.niveau,
                  typeNiveau: e.typeNiveau,
                  codeNiveau: e.codeNiveau,
                  description: e.description,
                  zones: [
                    for (final z in e.zones)
                      if (z.id == zoneId) ZoneStructure(id: z.id, nom: nom) else z,
                  ],
                ),
            ],
          ),
      ];

  /// La structure, privée d'un appartement.
  List<BatimentStructure> _batimentsSansZone(String zoneId) => [
        for (final b in state.batiments)
          BatimentStructure(
            id: b.id,
            nom: b.nom,
            etages: [
              for (final e in b.etages)
                EtageStructure(
                  id: e.id,
                  nom: e.nom,
                  niveau: e.niveau,
                  typeNiveau: e.typeNiveau,
                  codeNiveau: e.codeNiveau,
                  description: e.description,
                  zones: e.zones.where((z) => z.id != zoneId).toList(),
                ),
            ],
          ),
      ];

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
  /// niveau — ou d'un appartement — servi, et qui donne son nom au plan
  /// global. Son identifiant est préfixé « brouillon- » et son URL est
  /// vide — rien ici n'ira au serveur, seuls les chemins retenus à côté
  /// seront téléversés.
  ///
  /// Au plus un des deux rattachements : un plan d'appartement porte [zoneId],
  /// un plan de niveau porte [etageId], le plan global ne porte ni l'un ni
  /// l'autre.
  Plan _planLocal({required String nom, String? id, String? etageId, String? zoneId}) => Plan(
        id: id ?? _prochainIdTemp(),
        chantierId: '',
        nom: nom,
        fichierUrl: '',
        format: PlanFormat.pdf,
        etage: etageId == null ? null : PlanNiveauRef(id: etageId, nom: nom),
        zone: zoneId == null ? null : PlanNiveauRef(id: zoneId, nom: nom),
      );

  void _retenirNiveau({
    required String batimentId,
    required TypeNiveau typeNiveau,
    required String codeNiveau,
    String? description,
    String? cheminFichier,
    String? nomFichier,
    List<SaisieAppartement> appartements = const [],
  }) {
    final idNiveau = _prochainIdTemp();

    // Chaque appartement reçoit son identifiant temporaire, retenu pour le
    // rejeu et pour construire les zones affichées sous le niveau.
    final appartementsRetenus = [
      for (final a in appartements)
        _AppartementEnAttente(
          zoneTempId: _prochainIdTemp(),
          code: a.code,
          plans: [
            if (a.cheminFichier != null)
              _FichierPlan(
                idLocal: _prochainIdTemp(),
                chemin: a.cheminFichier!,
                nom: a.nomFichier ?? a.code,
              ),
          ],
        ),
    ];

    _niveauxEnAttente.add(_NiveauEnAttente(
      batimentTempId: batimentId,
      niveauTempId: idNiveau,
      typeNiveau: typeNiveau,
      codeNiveau: codeNiveau,
      description: description,
      cheminFichier: cheminFichier,
      nomFichier: nomFichier,
      appartements: appartementsRetenus,
    ));

    // Le niveau est inséré dans SON bâtiment pour que l'écran le montre
    // aussitôt, exactement comme un rechargement le ferait après un envoi —
    // avec SES appartements déjà dessous, comme le client l'a demandé.
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
                zones: [
                  for (final a in appartementsRetenus)
                    ZoneStructure(id: a.zoneTempId, nom: a.code),
                ],
              ),
            ],
          ),
    ];

    emit(state.copyWith(
      batiments: batiments,
      plans: [
        ...state.plans,
        if (cheminFichier != null)
          _planLocal(nom: nomFichier ?? codeNiveau, etageId: idNiveau),
        for (final a in appartementsRetenus)
          for (final f in a.plans)
            _planLocal(id: f.idLocal, nom: f.nom, zoneId: a.zoneTempId),
      ],
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

        final etage = creation.fold((_) => null, (e) => e);

        if (n.cheminFichier != null) {
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

        // Les appartements du niveau — chacun a besoin de l'identifiant RÉEL
        // du niveau, connu seulement maintenant.
        for (final a in n.appartements) {
          final creationZone = await creerZone(
            nouveauChantierId, batimentReel, etage!.id, nom: a.code,
          );
          final rateZone = creationZone.fold((e) => e.errorMessage, (_) => null);
          if (rateZone != null) {
            echec = rateZone;
            break;
          }

          final zone = creationZone.fold((_) => null, (z) => z);
          // TOUS les plans de l'appartement, pas seulement le premier : le
          // client en veut plusieurs par logement.
          for (final f in a.plans) {
            final depotZone = await uploaderPlan(
              chantierId: nouveauChantierId,
              cheminFichier: f.chemin,
              nom: f.nom,
              zoneId: zone?.id,
            );
            final rateDepotZone = depotZone.fold((e) => e.errorMessage, (_) => null);
            if (rateDepotZone != null) {
              echec = rateDepotZone;
              break;
            }
          }
          if (echec != null) break;
        }
        if (echec != null) break;
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
