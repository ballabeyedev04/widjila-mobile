import 'package:flutter/widgets.dart';

/// Une entrée du menu « Plus » de la barre de navigation.
///
/// Décrit CE QU'ON VEUT FAIRE, pas comment l'afficher : l'icône et la couleur
/// servent au rendu, les quatre autres champs disent au conteneur de menu
/// quelles étapes intercaler avant d'arriver à destination. C'est ce qui
/// permet à une même liste d'entrées de fonctionner quelle que soit la façon
/// dont on la présente.
typedef ActionRapide = ({
  IconData icon,
  String label,
  Color couleur,

  /// L'écran visé appartient-il à un chantier ? Si oui, le sélecteur de
  /// chantier s'intercale avant la navigation.
  bool besoinChantier,

  /// Le sélecteur propose-t-il de CRÉER un chantier ?
  ///
  /// Réservé aux actions qui peuvent viser un chantier qui n'existe pas
  /// encore — le dépôt de plans d'une entreprise qui n'en a aucun. Ailleurs,
  /// on cherche un chantier existant et proposer d'en créer un serait hors
  /// sujet.
  bool avecCreation,

  /// Le sélecteur joint-il les DEMANDES de chantier en attente ?
  ///
  /// Distinct de [avecCreation], et volontairement : créer une demande depuis
  /// le sélecteur est une chose, accepter d'en désigner une comme cible en est
  /// une autre. Le dépôt de plans veut les deux — c'est même le seul moment où
  /// une entreprise peut déposer. Une réserve, elle, ne se pose pas sur un
  /// chantier qui n'existe pas encore, tout en pouvant proposer d'en demander
  /// un : les deux drapeaux y prennent des valeurs opposées.
  bool avecDemandesEnAttente,

  /// `true` : route de la coquille applicative — la barre du bas reste
  /// affichée, on y va avec `context.go`.
  /// `false` : écran plein hors coquille, empilé avec `context.push`.
  bool dansCoquille,

  /// Construit la route. Reçoit l'identifiant du chantier choisi, ou `null`
  /// quand [besoinChantier] est faux.
  String Function(String? chantierId) route,
});
