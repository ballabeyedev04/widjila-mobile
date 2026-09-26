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
/// page de paiement, ni création de compte. L'organisation souscrit par
/// contrat avec nous (ou depuis le portail web, hors de l'application), et
/// l'application sert à travailler — relever des réserves, annoter des plans,
/// produire des rapports. C'est le fonctionnement prévu par Apple pour les
/// services vendus aux entreprises (« Enterprise Services », directive
/// 3.1.3), et c'est aussi ce que la réponse d'Apple demande explicitement.
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
  /// Apple assimile cette inscription à un canal d'achat externe (grief n° 2).
  /// Sur iOS, on ne garde que la connexion : le compte est créé par
  /// l'entreprise, hors de l'application.
  static bool get inscriptionAutorisee => commerceAutorise;
}
