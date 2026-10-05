# Réponse à App Review — Submission ID 586475e3-064a-48ee-9c8e-1501771ae96a

> Deux textes : le message à envoyer dans App Store Connect (« Reply to this
> message »), et les notes à coller dans **App Review Information → Notes**
> de la nouvelle version. Adapter les identifiants de démonstration avant
> d'envoyer.
>
> ⚠️ Ces textes décrivent le build **1.0.7**, où **l'inscription est
> présente**. Ne pas les utiliser pour le build 1.0.6 (16), où elle avait été
> retirée — l'examinateur vérifie ce qu'on lui annonce.

---

## 1. Message de réponse (anglais)

Hello,

Thank you for the detailed review. Both issues are resolved in build
**1.0.7 (17)**.

**Guideline 3.1.1 — access to paid content outside In-App Purchase**

The iOS app no longer offers, displays or links to any purchase:

- the "Abonnement" (Subscription) screen has been removed from the iOS app —
  no plans, no prices, no "Choose this plan" button;
- the link that opened our website's payment page in Safari has been removed;
- when a limit is reached, the app simply states the limit and invites the
  user to contact their organisation's administrator. No price, no purchase
  link, no website address is shown.

**Guideline 3.1.1 — account registration**

Account registration is still available in the app, and we would like to
explain why we believe it is now appropriate.

In the reviewed build, registration started a 2-day trial. When that trial
ended, every screen was blocked by a message asking the user to subscribe —
which could only be done outside the app. That was the real problem, and we
have removed it.

Widjila now includes a **permanent free tier**. Creating an account gives
immediate and unlimited-in-time access to: one construction site, two user
accounts, and an unlimited number of defects, with photos, annotated plans
and PDF reports. There is no trial period, no expiry, and no point at which
the app asks for payment. A user can install the app, create an account and
work with it indefinitely without ever paying anything.

Larger volumes (several sites, more users) are sold as a B2B service, under a
contract negotiated directly with the company, outside the application. The
iOS app never presents, prices or links to that offer.

Registration is essential to the app: a construction company discovering
Widjila on the App Store has no account, and no way to obtain one if the app
cannot create it. Without it the app would be installable but unusable.

Demo credentials to test the full app are provided in App Review Information.

Please let us know if anything else is needed.

Best regards,
Balla Beye — Widjila

---

## 2. Notes pour App Review Information

Widjila is a defect/snag tracking app for construction professionals.

**No purchase of any kind exists in the iOS app**: no subscription screen, no
prices, no payment flow, no link to an external payment page or website.

**Registration leads to a permanent free tier**, not to a purchase. A new
account gets, for free and with no time limit: 1 construction site, 2 user
accounts, unlimited defects, photos, annotated plans and PDF reports. The app
never asks for payment at any point. Larger volumes are contracted directly
with us, outside the application.

Demo account (full access):
  Email:    demo-apple@widjila.com
  Password: <à compléter>

Suggested walkthrough: sign in → "Chantiers" → open a site → "Plans" → tap
anywhere on a plan to log a defect → take a photo → "Réserves" to see the list.

You may also create a new account from the welcome screen to verify that it
gives immediate working access, with no payment requested.

Contact for any question: contact@widjila.com

---

## 3. À vérifier avant de soumettre

- [ ] Build **1.0.7 (17 ou plus)** — le refus portait sur 1.0 (15).
- [ ] **Le backend est déployé** avec l'offre gratuite. C'est le point le plus
      important : tant que `checkSubscription` bloque, un compte neuf voit
      « Votre période d'essai de 2 jours est terminée » et toute la réponse
      ci-dessus devient fausse sous les yeux de l'examinateur.
- [ ] **Créer un compte neuf depuis l'app**, attendre la fin de l'essai (ou
      tester avec une organisation dont l'essai est échu) et vérifier que
      Chantiers, Plans et Réserves restent accessibles.
- [ ] Ouvrir l'app sur un iPad (l'examen s'est fait sur iPad Air 11" M3) et
      confirmer : menu « Plus » **sans** tuile « Abonnement », profil
      **sans** « Voir les formules », et écran d'accueil **avec** « Créer un
      compte ».
- [ ] Le compte de démonstration se connecte et montre des chantiers avec des
      réserves — vérifié le jour de l'envoi.
- [ ] Captures d'écran de la fiche App Store : aucune ne doit montrer les
      tarifs ni l'écran d'abonnement.
- [ ] Description App Store : pas de mention de tarifs ni de « souscrire sur
      notre site ».
