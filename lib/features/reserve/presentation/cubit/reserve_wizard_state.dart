import 'package:equatable/equatable.dart';
import '../../../corps_etat/domain/entities/corps_etat.dart';
import '../../../phase/domain/entities/phase_referentiel.dart';
import '../../domain/entities/chantier_structure.dart';
import '../../domain/entities/reserve.dart';

enum StructureStatus { chargement, succes, erreur }
enum SoumissionStatus { initial, enCours, succes, erreur }

class ReserveWizardState extends Equatable {
  final int etape; // 0, 1, 2
  final StructureStatus structureStatus;
  final ChantierStructure structure;
  final SoumissionStatus soumissionStatus;
  final String? erreur;

  // Étape 1 — informations générales
  final String titre;
  /// Catalogue des métiers servi par l'API, et métier retenu.
  ///
  /// Remplace l'ancienne énumération figée `ReserveCategorie` : la liste
  /// s'enrichit désormais depuis l'espace d'administration, sans livraison
  /// mobile.
  final List<CorpsEtat> corpsEtatDisponibles;
  final String? corpsEtatId;

  /// Référentiel des phases et phase retenue. La phase est OBLIGATOIRE :
  /// le serveur refuse une réserve sans, et [etape1Valide] l'exige.
  final List<PhaseReferentiel> phasesDisponibles;
  final String? phaseId;
  final ReserveSeverite priorite;
  final String description;

  // Étape 2 — localisation
  final BatimentStructure? batiment;
  final EtageStructure? etage;
  final ZoneStructure? zone;
  final StructureRef? lot;
  final DateTime? dateLimite;

  const ReserveWizardState({
    this.etape = 0,
    this.structureStatus = StructureStatus.chargement,
    this.structure = const ChantierStructure(),
    this.soumissionStatus = SoumissionStatus.initial,
    this.erreur,
    this.titre = '',
    this.corpsEtatDisponibles = const [],
    this.corpsEtatId,
    this.phasesDisponibles = const [],
    this.phaseId,
    this.priorite = ReserveSeverite.moyenne,
    this.description = '',
    this.batiment,
    this.etage,
    this.zone,
    this.lot,
    this.dateLimite,
  });

  /// Étape 1 valide (titre obligatoire — le reste a un défaut raisonnable).
  /// La PHASE fait partie de la validité de l'étape 1 : elle est
  /// obligatoire, et la bloquer ici évite d'aller jusqu'au refus serveur.
  bool get etape1Valide => titre.trim().length >= 2 && phaseId != null;


  /// Vrai dès que l'utilisateur a saisi quelque chose qui serait perdu en
  /// refermant l'assistant.
  ///
  /// Ne regarde PAS `corpsEtatId` ni `priorite` : le métier est facultatif et
  /// la priorité a une valeur par
  /// défaut dès l'ouverture, les compter reviendrait à considérer tout
  /// formulaire vierge comme entamé — et à poser une question inutile à
  /// chaque abandon immédiat.
  bool get aDesDonneesSaisies =>
      titre.trim().isNotEmpty ||
      description.trim().isNotEmpty ||
      batiment != null ||
      etage != null ||
      zone != null ||
      lot != null ||
      dateLimite != null;

  ReserveWizardState copyWith({
    int? etape,
    StructureStatus? structureStatus,
    ChantierStructure? structure,
    SoumissionStatus? soumissionStatus,
    String? erreur,
    String? titre,
    List<CorpsEtat>? corpsEtatDisponibles,
    String? corpsEtatId,
    bool effacerCorpsEtat = false,
    List<PhaseReferentiel>? phasesDisponibles,
    String? phaseId,
    ReserveSeverite? priorite,
    String? description,
    BatimentStructure? batiment,
    bool effacerBatiment = false,
    EtageStructure? etageValue,
    bool effacerEtage = false,
    ZoneStructure? zoneValue,
    bool effacerZone = false,
    StructureRef? lot,
    bool effacerLot = false,
    DateTime? dateLimite,
    bool effacerDateLimite = false,
  }) {
    return ReserveWizardState(
      etape: etape ?? this.etape,
      structureStatus: structureStatus ?? this.structureStatus,
      structure: structure ?? this.structure,
      soumissionStatus: soumissionStatus ?? this.soumissionStatus,
      erreur: erreur,
      titre: titre ?? this.titre,
      corpsEtatDisponibles: corpsEtatDisponibles ?? this.corpsEtatDisponibles,
      corpsEtatId: effacerCorpsEtat ? null : (corpsEtatId ?? this.corpsEtatId),
      phasesDisponibles: phasesDisponibles ?? this.phasesDisponibles,
      phaseId: phaseId ?? this.phaseId,
      priorite: priorite ?? this.priorite,
      description: description ?? this.description,
      batiment: effacerBatiment ? null : (batiment ?? this.batiment),
      etage: effacerEtage ? null : (etageValue ?? etage),
      zone: effacerZone ? null : (zoneValue ?? zone),
      lot: effacerLot ? null : (lot ?? this.lot),
      dateLimite: effacerDateLimite ? null : (dateLimite ?? this.dateLimite),
    );
  }

  @override
  List<Object?> get props => [
        etape, structureStatus, structure, soumissionStatus, erreur, titre,
        corpsEtatDisponibles, corpsEtatId, phasesDisponibles, phaseId, priorite, description,
        batiment, etage, zone, lot, dateLimite,
      ];
}
