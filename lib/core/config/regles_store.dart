import 'package:flutter/foundation.dart';

/// Ce que l'application a le droit de montrer selon la boutique qui la
/// distribue.
///
/// ## Le refus d'Apple (23/09/2026, version 1.0 (15))
///
/// L'App Store a refusé Widjila au titre de la directive 3.1.1 — deux griefs :
///
///  1. l'application donnait accès à un contenu payant (les formules
///     d'abonnement) achetable AILLEURS que par un achat intégré : l'écran
///     Abonnement affichait les tarifs et ouvrait la page de paiement Stripe
///     dans le navigateur ;
///  2. l'inscription d'une entreprise depuis l'application est considérée par
///     Apple comme un canal d'achat externe, et doit être retirée.
///
/// Le lien vers un paiement extérieur n'est toléré que sur la boutique
/// AMÉRICAINE. Widjila est distribuée en France, au Sénégal et au Mali : la
/// dérogation ne s'applique pas.
///
/// ## Ce que fait cette règle
///
/// Sur iOS, l'application devient un CLIENT de l'abonnement, jamais un point
/// de vente : ni tarif, ni bouton « Choisir cette formule », ni lien vers la
/// page de paiement. L'organisation souscrit par contrat avec nous (ou depuis
/// le portail web, hors de l'application), et l'application sert à travailler
/// — relever des réserves, annoter des plans, produire des rapports. C'est le
/// fonctionnement prévu par Apple pour les services vendus aux entreprises
/// (« Enterprise Services », directive 3.1.3).
///
/// L'INSCRIPTION, elle, reste ouverte sur iOS. Voir `inscriptionAutorisee` :
/// elle ne mène plus à un achat mais à l'offre gratuite permanente, et la
/// retirer rendrait l'application inutilisable pour qui la découvre sur
/// l'App Store.
///
/// Android et le web ne changent PAS : la vente y reste ouverte, sans
/// commission, et c'est là que les organisations souscrivent.
///
/// ## Pourquoi `defaultTargetPlatform` et pas `Platform.isIOS`
///
/// `defaultTargetPlatform` est surchargeable dans les tests
/// (`debugDefaultTargetPlatformOverride`) : les deux comportements se
/// vérifient sans appareil. `Platform` n'existe pas non plus sur le web.
class ReglesStore {
  ReglesStore._();

  /// Vrai si l'application peut présenter et engager un achat.
  ///
  /// Faux sur iOS tant que l'abonnement n'y est pas vendu par achat intégré
  /// (StoreKit). Le jour où il le sera, cette valeur redeviendra vraie et
  /// l'écran d'abonnement réapparaîtra — un seul endroit à changer.
  static bool get commerceAutorise => defaultTargetPlatform != TargetPlatform.iOS;

  /// Vrai si l'application peut proposer de CRÉER une organisation.
  ///
  /// Vrai PARTOUT, iOS compris, et c'est un choix mûri.
  ///
  /// Apple reprochait à l'inscription d'être un canal d'achat externe : on
  /// créait un compte, l'essai courait deux jours, puis un mur réclamait de
  /// payer — ailleurs que par un achat intégré. Le grief portait sur ce
  /// qu'elle MENAIT, pas sur elle-même.
  ///
  /// Ce qu'elle mène a changé. L'inscription donne maintenant accès à l'offre
  /// gratuite permanente : un chantier, deux utilisateurs, des réserves
  /// illimitées, sans date de fin et sans rien à payer. Rien n'est vendu dans
  /// l'application iOS — `commerceAutorise` y reste faux, aucun tarif, aucun
  /// bouton, aucun lien de paiement. L'inscription ne mène donc plus à un
  /// achat : elle mène à un produit utilisable.
  ///
  /// La retirer coûterait bien plus qu'elle ne rapporte : une entreprise qui
  /// découvre Widjila sur l'App Store n'a aucun compte, et sans inscription
  /// elle n'a aucun moyen d'en obtenir un. L'application serait installable
  /// mais inutilisable.
  static bool get inscriptionAutorisee => true;
}
