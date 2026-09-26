# Réponse à App Review — Submission ID 586475e3-064a-48ee-9c8e-1501771ae96a

> Deux textes : le message à envoyer dans App Store Connect (« Reply to this
> message »), et les notes à coller dans **App Review Information → Notes**
> de la nouvelle version. Adapter les identifiants de démonstration avant
> d'envoyer.

---

## 1. Message de réponse (anglais)

Hello,

Thank you for the detailed review. We have removed both issues in build **1.0.7 (17)**.

**Guideline 3.1.1 — access to paid content outside In-App Purchase**

Widjila is a B2B construction-site defect-tracking service, sold directly by us
to construction companies and project owners under a company contract. It is
not sold to individual consumers.

In this build, the iOS app no longer offers, displays or links to any purchase:

- the "Abonnement" (Subscription) screen has been removed from the iOS app —
  no plans, no prices, no "Choose this plan" button;
- the link that opened our website's payment page in Safari has been removed;
- when a feature is unavailable because the company's contract does not cover
  it, the app simply states that the organisation's administrator should be
  contacted. No price, no purchase link, no website address is shown.

The iOS app is now solely a client for a service the company has contracted
with us. We believe this matches the Enterprise Services provision of
guideline 3.1.3 and your instructions above.

**Guideline 3.1.1 — account registration for businesses and organizations**

The account registration feature has been removed from the iOS app. The sign-up
button is gone from both the welcome screen and the sign-in screen, and the
registration screen is unreachable. iOS users can only sign in with credentials
created for them by their company.

Demo credentials to test the full app are provided in App Review Information.

Please let us know if anything else is needed.

Best regards,
Balla Beye — Widjila

---

## 2. Notes pour App Review Information

Widjila is a B2B service for construction professionals (defect/snag tracking
on building sites). It is sold directly by us to construction companies and
project owners under a company contract; it is not available to individual
consumers.

The iOS app is a client only: it contains no purchase flow, no pricing, no
subscription screen, no link to any external payment page, and no account
registration. Accounts are created by the customer company outside the app.

Demo account (full access, no purchase needed):
  Email:    demo-apple@widjila.com
  Password: <à compléter>

Suggested walkthrough: sign in → "Chantiers" → open a site → "Plans" → tap
anywhere on a plan to log a defect → take a photo → "Réserves" to see the list.

Contact for any question: contact@widjila.com

---

## 3. À vérifier avant de soumettre

- [ ] Build **1.0.7 (17)** (le refus portait sur 1.0 (15)).
- [ ] Ouvrir l'app sur un iPad (l'examen s'est fait sur iPad Air 11" M3) et
      confirmer : menu « Plus » **sans** tuile « Abonnement », écran de
      connexion **sans** « Créer un compte », profil **sans** « Voir les
      formules ».
- [ ] Le compte de démonstration a un abonnement ACTIF (sans quoi le mur de
      fin d'essai s'affiche et l'examinateur ne voit rien de l'application).
- [ ] Captures d'écran de la fiche App Store : aucune ne doit montrer les
      tarifs ni l'écran d'abonnement.
- [ ] Description App Store : pas de mention de tarifs ni de « souscrire sur
      notre site ».
