import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../reserve/domain/entities/chantier_structure.dart';
import '../../../reserve/domain/usecases/get_chantier_structure.dart';
import '../../domain/entities/configuration_rapport.dart';
import '../../domain/entities/modele_rapport.dart';
import '../../domain/entities/option_filtre.dart';
import '../../domain/entities/rapport.dart';
import '../../domain/entities/suivi_rapport.dart';
import '../../domain/usecases/rapport_usecases.dart';

/// Les étapes du parcours du § 3 :
///
///   + Nouveau rapport → Choisir le projet → Choisir un modèle →
///   Choisir les filtres → Choisir les sections → Prévisualiser → Générer
///
/// L'étape « projet » n'existe que si l'assistant est ouvert HORS d'un
/// chantier (depuis le tableau de bord) : depuis la fiche d'un chantier, le
/// projet est déjà choisi, et le redemander serait un geste inutile.
enum EtapeRapport { projet, modele, filtres, sections, apercu }

enum ChargementWizard { inactif, enCours, pret, erreur }

/// L'opération réseau en cours — une seule à la fois.
enum ActionWizard { aucune, enregistrement, resume, generation }

class NouveauRapportState extends Equatable {
  final String? chantierId;
  final String? chantierNom;
  final bool avecEtapeProjet;

  final List<OptionFiltre> projets;
  final ChargementWizard projetsStatut;

  final EtapeRapport etape;
  final ModeleRapport? modele;
  final String nom;
  final FiltresRapport filtres;
  final SectionsRapport sections;
  final Set<FormatRapport> formats;

  final ChargementWizard optionsStatut;
  final ChantierStructure? structure;
  final List<OptionFiltre> entreprises;
  final List<OptionFiltre> corpsEtat;

  /// Le brouillon enregistré sur le serveur — nul tant qu'il ne l'est pas.
  final String? rapportId;

  /// La configuration a changé depuis le dernier enregistrement.
  final bool modifie;

  final ResumeRapport? resume;
  final String? resumeErreur;
  final ActionWizard action;

  /// Message ponctuel (échec réseau, refus du serveur).
  final String? erreur;

  /// Ce que le modèle exige et qui manque — affiché à l'étape des filtres.
  final List<FiltreRequis> manquants;
  final bool formatManquant;

  /// Le rapport généré — la page s'en sert pour passer à son détail.
  final Rapport? rapportGenere;

  const NouveauRapportState({
    this.chantierId,
    this.chantierNom,
    this.avecEtapeProjet = false,
    this.projets = const [],
    this.projetsStatut = ChargementWizard.inactif,
    this.etape = EtapeRapport.modele,
    this.modele,
    this.nom = '',
    this.filtres = const FiltresRapport(),
    this.sections = const SectionsRapport(),
    this.formats = const {FormatRapport.pdf},
    this.optionsStatut = ChargementWizard.inactif,
    this.structure,
    this.entreprises = const [],
    this.corpsEtat = const [],
    this.rapportId,
    this.modifie = true,
    this.resume,
    this.resumeErreur,
    this.action = ActionWizard.aucune,
    this.erreur,
    this.manquants = const [],
    this.formatManquant = false,
    this.rapportGenere,
  });

  List<EtapeRapport> get etapes => [
        if (avecEtapeProjet) EtapeRapport.projet,
        EtapeRapport.modele,
        EtapeRapport.filtres,
        EtapeRapport.sections,
        EtapeRapport.apercu,
      ];

  int get indexEtape => etapes.indexOf(etape);
  bool get occupe => action != ActionWizard.aucune;

  ConfigurationRapport? get configuration => chantierId == null || modele == null
      ? null
      : ConfigurationRapport(
          chantierId: chantierId!,
          nom: nom,
          modele: modele!,
          filtres: filtres,
          sections: sections,
          formats: formats,
        );

  /// Les niveaux proposés : ceux des bâtiments choisis, ou tous.
  List<({EtageStructure etage, BatimentStructure batiment})> get etagesProposes {
    final choisis = filtres.batiments;
    return [
      for (final b in structure?.batiments ?? const <BatimentStructure>[])
        if (choisis.isEmpty || choisis.contains(b.id))
          for (final e in b.etages) (etage: e, batiment: b),
    ];
  }

  /// Les appartements / zones proposés : ceux des niveaux choisis, ou de
  /// tous les niveaux proposés.
  List<({ZoneStructure zone, EtageStructure etage})> get zonesProposees {
    final choisis = filtres.etages;
    return [
      for (final p in etagesProposes)
        if (choisis.isEmpty || choisis.contains(p.etage.id))
          for (final z in p.etage.zones) (zone: z, etage: p.etage),
    ];
  }

  NouveauRapportState copyWith({
    String? chantierId,
    String? chantierNom,
    List<OptionFiltre>? projets,
    ChargementWizard? projetsStatut,
    EtapeRapport? etape,
    ModeleRapport? modele,
    String? nom,
    FiltresRapport? filtres,
    SectionsRapport? sections,
    Set<FormatRapport>? formats,
    ChargementWizard? optionsStatut,
    ChantierStructure? structure,
    List<OptionFiltre>? entreprises,
    List<OptionFiltre>? corpsEtat,
    String? rapportId,
    bool? modifie,
    ResumeRapport? resume,
    bool effacerResume = false,
    String? resumeErreur,
    ActionWizard? action,
    String? erreur,
    List<FiltreRequis>? manquants,
    bool? formatManquant,
    Rapport? rapportGenere,
  }) {
    return NouveauRapportState(
      chantierId: chantierId ?? this.chantierId,
      chantierNom: chantierNom ?? this.chantierNom,
      avecEtapeProjet: avecEtapeProjet,
      projets: projets ?? this.projets,
      projetsStatut: projetsStatut ?? this.projetsStatut,
      etape: etape ?? this.etape,
      modele: modele ?? this.modele,
      nom: nom ?? this.nom,
      filtres: filtres ?? this.filtres,
      sections: sections ?? this.sections,
      formats: formats ?? this.formats,
      optionsStatut: optionsStatut ?? this.optionsStatut,
      structure: structure ?? this.structure,
      entreprises: entreprises ?? this.entreprises,
      corpsEtat: corpsEtat ?? this.corpsEtat,
      rapportId: rapportId ?? this.rapportId,
      modifie: modifie ?? this.modifie,
      resume: effacerResume ? null : (resume ?? this.resume),
      // Le message d'erreur du résumé et l'erreur ponctuelle ne survivent
      // pas à l'émission suivante : ils décrivent l'opération qui vient
      // d'échouer, pas l'état durable de l'écran.
      resumeErreur: resumeErreur,
      action: action ?? this.action,
      erreur: erreur,
      manquants: manquants ?? this.manquants,
      formatManquant: formatManquant ?? this.formatManquant,
      rapportGenere: rapportGenere ?? this.rapportGenere,
    );
  }

  @override
  List<Object?> get props => [
        chantierId, chantierNom, avecEtapeProjet, projets, projetsStatut, etape, modele, nom,
        filtres, sections, formats, optionsStatut, structure?.batiments, entreprises, corpsEtat,
        rapportId, modifie, resume, resumeErreur, action, erreur, manquants, formatManquant,
        rapportGenere,
      ];
}

/// L'assistant « + Nouveau rapport » — § 3, § 4, § 5, § 10, § 11 et § 20.
///
/// La configuration n'est enregistrée sur le serveur qu'à l'entrée de
/// l'APERÇU : c'est là qu'il faut un rapport réel pour calculer le
/// périmètre et produire la prévisualisation. Avant, tout reste local — un
/// utilisateur qui abandonne à l'étape des filtres ne laisse pas de
/// brouillon orphelin derrière lui.
class NouveauRapportCubit extends Cubit<NouveauRapportState> {
  final GetChantierStructure getStructure;
  final GetOptionsFiltresRapport getOptions;
  final GetProjetsRapport getProjets;
  final CreerRapport creerRapport;
  final ModifierRapport modifierRapport;
  final CalculerResumeRapport calculerResume;
  final GenererRapportConfigure genererRapport;

  NouveauRapportCubit({
    required this.getStructure,
    required this.getOptions,
    required this.getProjets,
    required this.creerRapport,
    required this.modifierRapport,
    required this.calculerResume,
    required this.genererRapport,
    String? chantierId,
    String? chantierNom,
    Rapport? existant,
  }) : super(_etatInitial(chantierId, chantierNom, existant));

  static NouveauRapportState _etatInitial(String? chantierId, String? chantierNom, Rapport? existant) {
    if (existant != null) {
      // § 20 — revenir sur un rapport : sa configuration est reprise telle
      // quelle, et l'enregistrement se fera par modification, pas création.
      return NouveauRapportState(
        chantierId: existant.chantierId,
        chantierNom: chantierNom,
        etape: EtapeRapport.filtres,
        modele: existant.modele ?? ModeleRapport.global,
        nom: existant.nom ?? '',
        filtres: existant.filtres,
        sections: existant.sections,
        formats: existant.formats,
        rapportId: existant.id,
        modifie: false,
      );
    }
    return NouveauRapportState(
      chantierId: chantierId,
      chantierNom: chantierNom,
      avecEtapeProjet: chantierId == null,
      etape: chantierId == null ? EtapeRapport.projet : EtapeRapport.modele,
    );
  }

  /// Charge ce que l'étape courante demande : la liste des projets, ou les
  /// listes du chantier pour les filtres.
  Future<void> demarrer() async {
    if (state.chantierId == null) {
      await chargerProjets();
    } else {
      await chargerOptions();
    }
  }

  Future<void> chargerProjets() async {
    emit(state.copyWith(projetsStatut: ChargementWizard.enCours));
    final resultat = await getProjets();
    if (isClosed) return;
    resultat.fold(
      (f) => emit(state.copyWith(projetsStatut: ChargementWizard.erreur, erreur: f.errorMessage)),
      (projets) => emit(state.copyWith(projetsStatut: ChargementWizard.pret, projets: projets)),
    );
  }

  Future<void> choisirProjet(OptionFiltre projet) async {
    // Changer de projet invalide tous les filtres : un bâtiment d'un autre
    // chantier serait refusé par le serveur.
    emit(NouveauRapportState(
      chantierId: projet.id,
      chantierNom: projet.nom,
      avecEtapeProjet: true,
      projets: state.projets,
      projetsStatut: state.projetsStatut,
      etape: EtapeRapport.modele,
      modele: state.modele,
      nom: state.nom,
      sections: state.sections,
      formats: state.formats,
    ));
    await chargerOptions();
  }

  Future<void> chargerOptions() async {
    final chantierId = state.chantierId;
    if (chantierId == null) return;
    emit(state.copyWith(optionsStatut: ChargementWizard.enCours));

    final resultats = await Future.wait([getStructure(chantierId), getOptions(chantierId)]);
    if (isClosed) return;

    String? echec;
    ChantierStructure? structure;
    OptionsFiltresRapport? options;
    resultats[0].fold((f) => echec = f.errorMessage, (s) => structure = s as ChantierStructure);
    resultats[1].fold((f) => echec ??= f.errorMessage, (o) => options = o as OptionsFiltresRapport);

    if (structure == null || options == null) {
      emit(state.copyWith(optionsStatut: ChargementWizard.erreur, erreur: echec));
      return;
    }
    emit(state.copyWith(
      optionsStatut: ChargementWizard.pret,
      structure: structure,
      entreprises: options!.entreprises,
      corpsEtat: options!.corpsEtat,
    ));
  }

  /// Choisir un modèle POSE son périmètre et ses sections par défaut
  /// (§ 5) — sans écraser un choix déjà fait par l'utilisateur sur les
  /// statuts.
  void choisirModele(ModeleRapport modele) {
    final statuts = state.filtres.statuts.isEmpty || state.modele != null
        ? modele.statutsParDefaut
        : state.filtres.statuts;
    emit(state.copyWith(
      modele: modele,
      sections: modele.sectionsParDefaut,
      filtres: state.filtres.copyWith(statuts: statuts),
      manquants: const [],
      modifie: true,
      effacerResume: true,
    ));
  }

  void definirNom(String nom) => emit(state.copyWith(nom: nom, modifie: true));

  List<T> _basculer<T>(List<T> liste, T valeur) =>
      liste.contains(valeur) ? liste.where((v) => v != valeur).toList() : [...liste, valeur];

  void _filtrer(FiltresRapport filtres) => emit(state.copyWith(
        filtres: filtres,
        modifie: true,
        effacerResume: true,
        // Revérifié à chaque changement : l'avertissement disparaît dès que
        // le filtre exigé est posé.
        manquants: state.manquants.isEmpty || state.modele == null ? const [] : filtres.manquantsPour(state.modele!),
      ));

  /// Retirer un bâtiment retire aussi ses niveaux et ses zones : garder un
  /// niveau d'un bâtiment désélectionné poserait un filtre que plus rien
  /// n'affiche à l'écran.
  void basculerBatiment(String id) {
    final f = state.filtres;
    if (!f.batiments.contains(id)) {
      _filtrer(f.copyWith(batiments: [...f.batiments, id]));
      return;
    }
    final batiment = state.structure?.batiments.where((b) => b.id == id).firstOrNull;
    final etagesRetires = {for (final e in batiment?.etages ?? const <EtageStructure>[]) e.id};
    final zonesRetirees = {
      for (final e in batiment?.etages ?? const <EtageStructure>[])
        for (final z in e.zones) z.id,
    };
    _filtrer(f.copyWith(
      batiments: f.batiments.where((b) => b != id).toList(),
      etages: f.etages.where((e) => !etagesRetires.contains(e)).toList(),
      zones: f.zones.where((z) => !zonesRetirees.contains(z)).toList(),
    ));
  }

  void basculerEtage(String id) {
    final f = state.filtres;
    if (!f.etages.contains(id)) {
      _filtrer(f.copyWith(etages: [...f.etages, id]));
      return;
    }
    final etage = state.etagesProposes.where((p) => p.etage.id == id).firstOrNull?.etage;
    final zonesRetirees = {for (final z in etage?.zones ?? const <ZoneStructure>[]) z.id};
    _filtrer(f.copyWith(
      etages: f.etages.where((e) => e != id).toList(),
      zones: f.zones.where((z) => !zonesRetirees.contains(z)).toList(),
    ));
  }

  void basculerZone(String id) => _filtrer(state.filtres.copyWith(zones: _basculer(state.filtres.zones, id)));
  void basculerEntreprise(String id) =>
      _filtrer(state.filtres.copyWith(entreprises: _basculer(state.filtres.entreprises, id)));
  /// Une entreprise vient d'être ajoutée à l'annuaire du chantier depuis
  /// cet écran : elle rejoint la liste ET se trouve cochée.
  ///
  /// Cochée, parce que c'est la raison de l'ajout — on crée l'entreprise pour
  /// faire SON rapport. Sans cela, l'utilisateur devait encore la retrouver
  /// dans les puces et la sélectionner lui-même.
  void ajouterEntreprise(OptionFiltre entreprise) {
    final dejaLa = state.entreprises.any((e) => e.id == entreprise.id);
    emit(state.copyWith(
      entreprises: dejaLa ? state.entreprises : [...state.entreprises, entreprise],
    ));
    if (!state.filtres.entreprises.contains(entreprise.id)) basculerEntreprise(entreprise.id);
  }

  void basculerCorpsEtat(String id) =>
      _filtrer(state.filtres.copyWith(corpsEtat: _basculer(state.filtres.corpsEtat, id)));
  void basculerStatut(StatutReserveRapport s) =>
      _filtrer(state.filtres.copyWith(statuts: _basculer(state.filtres.statuts, s)));
  void basculerGravite(GraviteRapport g) =>
      _filtrer(state.filtres.copyWith(gravites: _basculer(state.filtres.gravites, g)));

  void definirPeriode({DateTime? debut, DateTime? fin}) =>
      _filtrer(state.filtres.copyWith(dateDebut: debut, dateFin: fin));

  void effacerPeriode() => _filtrer(state.filtres.copyWith(effacerPeriode: true));

  void definirSections(SectionsRapport sections) =>
      emit(state.copyWith(sections: sections, modifie: true, effacerResume: true));

  void basculerFormat(FormatRapport format) {
    final formats = {...state.formats};
    if (!formats.remove(format)) formats.add(format);
    emit(state.copyWith(formats: formats, modifie: true, formatManquant: false));
  }

  /// Passe à l'étape suivante si l'étape courante est complète.
  Future<void> suivant() async {
    switch (state.etape) {
      case EtapeRapport.projet:
        if (state.chantierId == null) return;
        emit(state.copyWith(etape: EtapeRapport.modele));
      case EtapeRapport.modele:
        if (state.modele == null) return;
        emit(state.copyWith(etape: EtapeRapport.filtres));
      case EtapeRapport.filtres:
        final manquants = state.filtres.manquantsPour(state.modele!);
        if (manquants.isNotEmpty) {
          emit(state.copyWith(manquants: manquants));
          return;
        }
        emit(state.copyWith(etape: EtapeRapport.sections, manquants: const []));
      case EtapeRapport.sections:
        if (state.formats.isEmpty) {
          emit(state.copyWith(formatManquant: true));
          return;
        }
        emit(state.copyWith(etape: EtapeRapport.apercu));
        await actualiserResume();
      case EtapeRapport.apercu:
        return;
    }
  }

  void precedent() {
    final i = state.indexEtape;
    if (i <= 0 || state.occupe) return;
    emit(state.copyWith(etape: state.etapes[i - 1]));
  }

  /// Enregistre la configuration sur le serveur — création au premier
  /// passage, modification ensuite. Renvoie l'identifiant, ou `null` si
  /// l'enregistrement a échoué (le message est alors dans l'état).
  Future<String?> enregistrer() async {
    final configuration = state.configuration;
    if (configuration == null) return null;
    if (state.rapportId != null && !state.modifie) return state.rapportId;

    emit(state.copyWith(action: ActionWizard.enregistrement));
    final resultat = state.rapportId == null
        ? await creerRapport(configuration)
        : await modifierRapport(state.rapportId!, configuration);
    if (isClosed) return null;

    return resultat.fold(
      (f) {
        emit(state.copyWith(action: ActionWizard.aucune, erreur: f.errorMessage));
        return null;
      },
      (rapport) {
        emit(state.copyWith(action: ActionWizard.aucune, rapportId: rapport.id, modifie: false));
        return rapport.id;
      },
    );
  }

  /// Le périmètre chiffré — « combien de réserves sortiraient ».
  Future<void> actualiserResume() async {
    final id = await enregistrer();
    if (id == null || isClosed) return;
    emit(state.copyWith(action: ActionWizard.resume));
    final resultat = await calculerResume(id);
    if (isClosed) return;
    resultat.fold(
      (f) => emit(state.copyWith(action: ActionWizard.aucune, resumeErreur: f.errorMessage)),
      (resume) => emit(state.copyWith(action: ActionWizard.aucune, resume: resume)),
    );
  }

  /// Chemin de la prévisualisation (§ 20), après enregistrement.
  Future<String?> cheminPrevisualisation() async {
    final id = await enregistrer();
    return id == null ? null : '/reports/$id/preview';
  }

  /// Verrou SYNCHRONE de la génération.
  ///
  /// `state.occupe` ne suffit pas : il ne passe à vrai qu'après
  /// l'enregistrement, donc après un premier `await`. Deux appuis rapprochés
  /// franchissaient tous deux la garde avant qu'aucun n'ait émis — et
  /// produisaient deux générations, donc deux versions du même rapport.
  bool _generationEnCours = false;

  /// § 11 — génère le rapport. Un seul appui compte : la génération est
  /// longue, et deux appuis produiraient deux versions.
  Future<void> generer() async {
    if (_generationEnCours || state.occupe) return;
    _generationEnCours = true;
    try {
      final id = await enregistrer();
      if (id == null || isClosed) return;

      emit(state.copyWith(action: ActionWizard.generation));
      final resultat = await genererRapport(id);
      if (isClosed) return;
      resultat.fold(
        (f) => emit(state.copyWith(action: ActionWizard.aucune, erreur: f.errorMessage)),
        (rapport) => emit(state.copyWith(action: ActionWizard.aucune, rapportGenere: rapport)),
      );
    } finally {
      _generationEnCours = false;
    }
  }
}
