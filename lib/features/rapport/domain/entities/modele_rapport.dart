import '../../../../l10n/generated/app_localizations.dart';
import 'configuration_rapport.dart';

/// Les modèles de rapport — § 5 du cahier des charges.
///
/// Miroir de `MODELES` dans `backend/src/modules/rapport/service/
/// rapportReferentiel.js`. Le « Rapport SAV » y est annoncé pour une version
/// ultérieure : il n'apparaît donc pas ici, plutôt que d'être proposé puis
/// refusé par le serveur.
enum ModeleRapport { global, batiment, etageZone, entreprise, corpsEtat, aTraiter, levees, opr }

/// Ce qu'un modèle exige de choisir avant de pouvoir être généré.
///
/// Un « rapport par bâtiment » sans bâtiment ne serait pas un rapport par
/// bâtiment : ce serait un rapport global qui en porte le titre, et il
/// partirait aux entreprises sous ce nom.
enum FiltreRequis { batiment, etageOuZone, entreprise, corpsEtat }

extension ModeleRapportX on ModeleRapport {
  String get raw => switch (this) {
        ModeleRapport.global => 'GLOBAL',
        ModeleRapport.batiment => 'BATIMENT',
        ModeleRapport.etageZone => 'ETAGE_ZONE',
        ModeleRapport.entreprise => 'ENTREPRISE',
        ModeleRapport.corpsEtat => 'CORPS_ETAT',
        ModeleRapport.aTraiter => 'A_TRAITER',
        ModeleRapport.levees => 'LEVEES',
        ModeleRapport.opr => 'OPR',
      };

  /// `null` pour une valeur inconnue — un modèle ajouté au serveur après
  /// cette version. L'appelant affiche alors la valeur brute plutôt qu'un
  /// libellé faux.
  static ModeleRapport? fromString(String? brut) {
    for (final m in ModeleRapport.values) {
      if (m.raw == brut?.toUpperCase()) return m;
    }
    return null;
  }

  String label(AppLocalizations l10n) => switch (this) {
        ModeleRapport.global => l10n.rapportModeleGlobal,
        ModeleRapport.batiment => l10n.rapportModeleBatiment,
        ModeleRapport.etageZone => l10n.rapportModeleEtageZone,
        ModeleRapport.entreprise => l10n.rapportModeleEntreprise,
        ModeleRapport.corpsEtat => l10n.rapportModeleCorpsEtat,
        ModeleRapport.aTraiter => l10n.rapportModeleATraiter,
        ModeleRapport.levees => l10n.rapportModeleLevees,
        ModeleRapport.opr => l10n.rapportModeleOpr,
      };

  String description(AppLocalizations l10n) => switch (this) {
        ModeleRapport.global => l10n.rapportModeleGlobalDesc,
        ModeleRapport.batiment => l10n.rapportModeleBatimentDesc,
        ModeleRapport.etageZone => l10n.rapportModeleEtageZoneDesc,
        ModeleRapport.entreprise => l10n.rapportModeleEntrepriseDesc,
        ModeleRapport.corpsEtat => l10n.rapportModeleCorpsEtatDesc,
        ModeleRapport.aTraiter => l10n.rapportModeleATraiterDesc,
        ModeleRapport.levees => l10n.rapportModeleLeveesDesc,
        ModeleRapport.opr => l10n.rapportModeleOprDesc,
      };

  Set<FiltreRequis> get filtresRequis => switch (this) {
        ModeleRapport.batiment => const {FiltreRequis.batiment},
        ModeleRapport.etageZone => const {FiltreRequis.etageOuZone},
        ModeleRapport.entreprise => const {FiltreRequis.entreprise},
        ModeleRapport.corpsEtat => const {FiltreRequis.corpsEtat},
        _ => const {},
      };

  /// Le périmètre que le modèle POSE — l'utilisateur peut le restreindre.
  List<StatutReserveRapport> get statutsParDefaut => switch (this) {
        ModeleRapport.aTraiter => const [
            StatutReserveRapport.aTraiter,
            StatutReserveRapport.enCours,
            StatutReserveRapport.aControler,
          ],
        ModeleRapport.levees => const [StatutReserveRapport.levee, StatutReserveRapport.cloturee],
        _ => const [],
      };

  /// Sections par défaut : l'historique est allumé pour les levées, dont le
  /// § 17 exige de montrer qui a demandé et qui a contrôlé la levée.
  SectionsRapport get sectionsParDefaut => this == ModeleRapport.levees
      ? const SectionsRapport(history: true)
      : const SectionsRapport();
}
