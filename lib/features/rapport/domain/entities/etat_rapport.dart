import '../../../../l10n/generated/app_localizations.dart';

/// Les sept états techniques d'un rapport — § 19 du cahier des charges.
///
///   brouillon   configuration enregistrée
///   enAttente   génération planifiée
///   generation  fichier en cours de création
///   genere      fichier disponible
///   envoye      diffusion effectuée
///   echec       erreur de génération ou d'envoi
///   archive     rapport conservé dans l'historique
enum EtatRapport { brouillon, enAttente, generation, genere, envoye, echec, archive }

extension EtatRapportX on EtatRapport {
  String get raw => switch (this) {
        EtatRapport.brouillon => 'brouillon',
        EtatRapport.enAttente => 'en_attente',
        EtatRapport.generation => 'generation',
        EtatRapport.genere => 'genere',
        EtatRapport.envoye => 'envoye',
        EtatRapport.echec => 'echec',
        EtatRapport.archive => 'archive',
      };

  /// Un rapport produit AVANT le module (sans colonne `statut`) a forcément
  /// été généré : c'est l'état par défaut, pas « brouillon », qui laisserait
  /// croire qu'il n'a jamais existé en fichier.
  static EtatRapport fromString(String? brut) {
    for (final e in EtatRapport.values) {
      if (e.raw == brut) return e;
    }
    return EtatRapport.genere;
  }

  String label(AppLocalizations l10n) => switch (this) {
        EtatRapport.brouillon => l10n.rapportEtatBrouillon,
        EtatRapport.enAttente => l10n.rapportEtatEnAttente,
        EtatRapport.generation => l10n.rapportEtatGeneration,
        EtatRapport.genere => l10n.rapportEtatGenere,
        EtatRapport.envoye => l10n.rapportEtatEnvoye,
        EtatRapport.echec => l10n.rapportEtatEchec,
        EtatRapport.archive => l10n.rapportEtatArchive,
      };
}
