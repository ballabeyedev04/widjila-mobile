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
/// L'INSCRIPTION est elle aussi retirée sur iOS. Voir `inscriptionAutorisee`.
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
  /// Faux sur iOS. Deuxième refus d'Apple (13/10/2026, version 1.0 (20)) :
  /// malgré l'offre gratuite permanente, l'inscription d'une entreprise
  /// reste considérée comme un accès à un achat externe (directive 3.1.1),
  /// et Apple demande explicitement de la retirer.
  ///
  /// Sur iOS, l'application ne fait donc que la CONNEXION : les entreprises
  /// s'inscrivent sur Android ou le web, puis se connectent sur iPhone.
  /// Le code de l'inscription reste en place — Android et le web s'en
  /// servent toujours.
  static bool get inscriptionAutorisee => defaultTargetPlatform != TargetPlatform.iOS;
}
