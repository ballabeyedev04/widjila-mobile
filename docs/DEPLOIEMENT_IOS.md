# 🍏 Déploiement iOS — App Store Connect (TestFlight)

La chaîne `iOS — App Store` fait tout ce qu'une machine peut faire sans
décider à votre place : elle contrôle, compile, signe, vérifie, puis attend
votre approbation avant d'envoyer la version sur **TestFlight**.

Elle **ne soumet pas** la version à l'examen d'Apple. C'est volontaire : la
soumission demande des notes pour l'examinateur, un compte de démonstration
et, après un refus, une réponse écrite. Cela se fait depuis App Store
Connect, en connaissance de cause.

---

## ⚡ Publier une nouvelle version (au quotidien)

1. **Écrire les nouveautés** dans `fastlane/notes/fr-FR.txt` (500 caractères
   au maximum — le fichier est partagé avec Google Play, dont la limite est
   la plus basse). Elles servent de « Nouveautés à tester » sur TestFlight.
2. **Mettre à jour la version** dans `pubspec.yaml` si elle change
   (`version: 1.0.7+18` → seul `1.0.7` compte, le numéro de build est fixé
   par App Store Connect).
3. **Pousser sur `main`**, puis déclencher le déploiement :

```bash
git push origin main:release-ios
```

4. **Suivre** dans l'onglet *Actions* → `iOS — App Store`.
5. **Approuver** quand la chaîne le demande (étape 5-6) : GitHub envoie un
   courriel, le travail attend votre clic.
6. **Soumettre à l'examen** depuis App Store Connect quand vous êtes prêt :
   l'app → la version → *Ajouter à l'examen*.

### 🧪 Essai à blanc

*Actions* → `iOS — App Store` → *Run workflow* : toute la chaîne s'exécute,
Apple valide réellement l'IPA (`altool --validate-app`), **rien n'est
publié**. À faire au moindre doute — c'est gratuit en conséquences.

---

## 🛤️ La chaîne, étape par étape

| # | Étape | Machine | Ce qu'elle refuse |
|---|---|---|---|
| 1 | Contrôles d'entrée | Linux | commit absent de `main`, notes vides, trop longues, ou identiques au dernier déploiement iOS |
| 2a | Analyse & traductions | Linux | erreur ou avertissement d'analyse, traduction manquante |
| 2b | Tests & couverture | Linux | un test en échec |
| 2c | Sécurité | Linux | un secret oublié dans le code |
| 3-4 | Compilation, contrôle de l'IPA & démarrage | **macOS** | Xcode trop ancien, profil de développement au lieu d'App Store, profil expiré, mauvais bundle, app non signée, autorisation nouvelle non déclarée, app qui ne démarre pas |
| 5-6 | ✋ Approbation & publication | **macOS** | numéro de build pris entre-temps, IPA refusé par Apple, build absent de TestFlight après l'envoi |
| 7 | Bilan | Linux | — |

### ✋ Que regarder avant d'approuver

Le résumé du travail 3-4 donne tout :

- **Profil d'approvisionnement** — « App Store », bonne équipe, pas expiré ;
- **Autorisations demandées** — aucune nouveauté inattendue. Apple refuse une
  app qui demande un accès (caméra, position, micro) dont l'explication ne
  correspond pas à l'usage réel ;
- **Taille de l'IPA** — une hausse brutale signale un fichier embarqué par
  erreur ;
- **Test de démarrage** — la capture d'écran du simulateur montre le premier
  écran, sur une installation neuve ;
- **Déclaration de chiffrement** — sans elle, App Store Connect bloque la
  distribution en attendant votre réponse.

### 📦 Ce qui est conservé

| Artefact | Durée | Contenu |
|---|---|---|
| `ipa` | 90 jours | l'IPA envoyé, ses autorisations, ses symboles (dSYMs), les empreintes SHA-256 |
| `test-demarrage-ios` | 30 jours | capture d'écran et journal du simulateur |
| `couverture` | 30 jours | `lcov.info` |

Chaque déploiement réel crée en plus un tag et une *Release* GitHub
`ios-v<version>-build<numéro>` : le lien entre un build sur TestFlight et le
commit exact qui l'a produit.

---

## 🔧 Configuration initiale (une seule fois)

Rien de tout cela n'est dans le code : ce sont des comptes, des clés et des
réglages. Comptez une heure, sur un Mac pour la partie 2.

### 1️⃣ Clé API App Store Connect

C'est ce qui remplace votre identifiant Apple : pas de mot de passe sur une
machine d'intégration, pas de double authentification à déjouer.

1. [App Store Connect](https://appstoreconnect.apple.com) →
   **Utilisateurs et accès** → onglet **Intégrations** → **Clés API**
   (section *App Store Connect API*) ;
2. **+** → nom : `GitHub Actions`, accès : **App Manager** ;
3. notez l'**Issuer ID** (en haut de la page, le même pour toutes vos clés)
   et le **Key ID** de la ligne créée ;
4. **téléchargez le fichier `AuthKey_XXXXXXXX.p8`** — Apple ne le propose
   **qu'une seule fois**. Rangez-le dans votre gestionnaire de mots de passe.

### 2️⃣ Signature : certificat de distribution + profil

À faire sur un Mac, avec Xcode connecté à votre compte Apple Developer.

**Le certificat** (`.p12`) :

1. Xcode → *Settings* → *Accounts* → votre équipe (DR54MH4Z4J) →
   *Manage Certificates* → **+** → **Apple Distribution** ;
2. Trousseau d'accès → *Mes certificats* → votre certificat
   « Apple Distribution: … » → clic droit → **Exporter** → format
   `.p12` → **mettez un mot de passe** (vous en aurez besoin juste après).

**Le profil** (`.mobileprovision`) :

1. [developer.apple.com](https://developer.apple.com/account/resources/profiles/list)
   → *Profiles* → **+** ;
2. type : **App Store Connect** (sous *Distribution*) ;
3. App ID : `com.widjila.suivichantier` ;
4. certificat : celui créé juste avant ;
5. nom : `Widjila App Store`, puis **téléchargez** le fichier.

> Le profil doit porter la capacité **Push Notifications** (l'app déclare
> `aps-environment = production`). La chaîne vous avertit si elle manque :
> les notifications ne fonctionneraient pas dans ce build.

> Un certificat de distribution vaut **1 an**, un profil **1 an** aussi.
> La chaîne avertit 30 jours avant expiration, puis refuse de publier.

### 3️⃣ Secrets GitHub

*Settings* → *Secrets and variables* → *Actions* → **New repository secret**.

Les trois fichiers doivent être convertis en base64 **sur une seule ligne**.

Sur macOS ou Linux :

```bash
base64 -i AuthKey_XXXXXXXX.p8 | tr -d '\n' | pbcopy
base64 -i distribution.p12 | tr -d '\n' | pbcopy
base64 -i Widjila_App_Store.mobileprovision | tr -d '\n' | pbcopy
```

Sur Windows (PowerShell) :

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXXXX.p8")) | Set-Clipboard
```

| Secret | Contenu |
|---|---|
| `APP_STORE_CONNECT_KEY_BASE64` | le fichier `.p8`, en base64 |
| `APP_STORE_CONNECT_KEY_ID` | le *Key ID* (10 caractères) |
| `APP_STORE_CONNECT_ISSUER_ID` | l'*Issuer ID* (un UUID) |
| `IOS_DIST_CERT_BASE64` | le fichier `.p12`, en base64 |
| `IOS_DIST_CERT_PASSWORD` | le mot de passe donné à l'export du `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | le `.mobileprovision`, en base64 |

### 4️⃣ Environnement d'approbation `app-store`

*Settings* → *Environments* → **New environment** → nom exact :
`app-store`.

- **Required reviewers** : vous (sans cela, la publication part sans
  approbation) ;
- **Deployment branches** : *Selected branches* → `release-ios`.

### 5️⃣ Protection de la branche `release-ios`

*Settings* → *Branches* → **Add rule** → `release-ios` :

- *Restrict who can push* : vous seul ;
- *Allow force pushes* : **oui** (c'est ainsi qu'on repousse un même commit).

### 6️⃣ L'app doit exister sur App Store Connect

La chaîne lit le dernier numéro de build sur App Store Connect : la fiche de
l'app doit donc déjà y être, avec le bundle `com.widjila.suivichantier`.
C'est le cas dès la première soumission, même refusée.

### 💰 Ce que ça coûte

Une minute de machine **macOS est facturée dix fois** une minute Linux.
Un déploiement complet occupe une machine macOS 35 à 55 minutes (dont 5 à
20 minutes d'attente du traitement d'Apple), soit **350 à 550 minutes
facturées**. À comparer aux 2 000 minutes incluses par mois du forfait
gratuit, et aux ~20 minutes Linux du reste de la chaîne.

Deux leviers si cela devient gênant :

- l'essai à blanc coûte la même chose : ne le lancez pas par réflexe ;
- dans `ios/fastlane/Fastfile`, `skip_waiting_for_build_processing: true`
  supprime l'attente du traitement d'Apple — au prix de la vérification
  après envoi et des « Nouveautés à tester ».

---

## 🛠️ Dépannage

| Message | Cause | Geste |
|---|---|---|
| `Secret GitHub manquant : …` | un secret de la liste ci-dessus n'existe pas | le créer (§3) |
| `Aucune identité « Apple Distribution » dans le trousseau` | le `.p12` est un certificat de **développement**, ou le mot de passe est faux | réexporter (§2) |
| `Le profil « … » liste des appareils` | profil *Development* ou *Ad Hoc* au lieu d'*App Store Connect* | recréer le profil (§2) |
| `Le profil « … » a expiré` | plus d'un an | régénérer sur developer.apple.com |
| `Le build N n'est plus libre` | un envoi est parti d'ailleurs entre la compilation et l'approbation | relancer le déploiement |
| `pubspec.yaml annonce X, plus ancienne que …` | version en recul | corriger `pubspec.yaml` |
| `Xcode … Apple refuse les envois construits avec un SDK antérieur` | image macOS trop ancienne | changer `runs-on` pour une image plus récente |
| `Les notes n'ont pas changé depuis ios-v…` | notes identiques au dernier déploiement iOS | écrire les nouveautés |
| `l'app ne démarre pas sur simulateur` | plantage au démarrage sur installation neuve | lire `test-demarrage-ios` (capture + journal) |

---

## ↩️ Revenir à une version précédente

Il n'y a pas de « retrait » sur TestFlight : on publie un build plus récent.

```bash
# revenir au code de la version précédente, corriger, puis
# notes : « Retour à la version précédente : … »
git push origin main:release-ios
```

Si la version fautive est déjà **en ligne sur l'App Store**, c'est App Store
Connect qui décide : retirer la version de la vente, ou soumettre une mise à
jour corrective en demandant un **examen accéléré**.

---

## 🗂️ Fichiers

| Fichier | Rôle |
|---|---|
| `.github/workflows/ios-release.yml` | la chaîne |
| `ios/fastlane/Fastfile` | les trois étapes : préparer, compiler, publier |
| `ios/fastlane/Appfile` | bundle et équipe |
| `tool/ci/controle_ipa.py` | contrôle de l'IPA avant envoi |
| `tool/ci/ios_reference.json` | ce que l'IPA doit contenir (bundle, équipe, autorisations acceptées) |
| `tool/ci/test_demarrage_ios.sh` | test de démarrage sur simulateur |
| `fastlane/notes/fr-FR.txt` | notes de version, partagées avec Google Play |

Chaîne Android : `docs/DEPLOIEMENT_ANDROID.md`.
