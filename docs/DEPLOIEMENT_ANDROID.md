# 🚀 Déploiement Android — Google Play

> **En une phrase :** vous écrivez les nouveautés, vous poussez sur `release`,
> la chaîne vérifie tout, vous approuvez d'un clic, et l'app arrive chez vos
> testeurs — sans ouvrir Play Console.

---

## ⚡ Publier une nouvelle version (au quotidien)

| | Étape | Où |
|:---:|---|---|
| 1 | Écrire les nouveautés dans **`fastlane/notes/fr-FR.txt`** (500 caractères max) | éditeur |
| 2 | *Seulement pour une nouvelle version visible :* changer `version:` dans `pubspec.yaml` (ex. `1.0.6` → `1.0.7`) | éditeur |
| 3 | Committer et pousser sur `main`, puis lancer la publication | terminal |
| 4 | Attendre l'e-mail « review pending », vérifier le résumé, cliquer **Approve** | GitHub |
| 5 | Recevoir la confirmation — Google vérifie, puis les testeurs reçoivent l'app | e-mail |

```bash
git push origin main
git push origin main:release
```

**À savoir**

- Un push sur `main` seul ne publie **rien**. Seul `main:release` déclenche.
- Le **numéro de build** (16, 17, 18…) est automatique : dernier numéro connu
  de Google Play + 1. Le chiffre après le `+` dans `pubspec.yaml` est ignoré.
- La **version visible** (1.0.6) ne change que si vous la modifiez.
- Les notes doivent **changer** à chaque déploiement : on ne publie pas deux
  versions avec le même texte.

### 🧪 Essai à blanc

**Actions** › **Android — Google Play** › **Run workflow** (case cochée).
Toute la chaîne s'exécute et Google Play **valide** l'envoi, mais rien n'est
publié et aucun numéro de build n'est consommé. À faire après toute
modification de la configuration.

---

## 🛤️ La chaîne, étape par étape

```
 1 · Contrôles d'entrée
        │
        ├── 2a · Analyse & traductions ──┐
        ├── 2b · Tests & couverture ─────┤   en parallèle
        └── 2c · Sécurité ───────────────┘
                        │
 3 · Compilation & contrôle de l'AAB
                        │
 4 · Test de démarrage sur émulateur Android
                        │
 5 · ✋ VOTRE APPROBATION
                        │
 6 · Publication Google Play + vérification + trace
                        │
 7 · Bilan
```

Chaque étape doit être ✅ pour que la suivante démarre. Au premier ❌, **rien
n'est publié**.

| Étape | Ce qui est vérifié | Si ça échoue |
|---|---|---|
| **1 · Contrôles d'entrée** | le commit est bien sur `main` · notes présentes, ≤ 500 caractères, **nouvelles** · version lisible | ❌ bloque |
| **2a · Analyse** | `flutter analyze` : aucune erreur ni avertissement (les remarques de style sont affichées, pas bloquantes) | ❌ bloque |
| **2a · Traductions** | chaque texte existe en fr, en, es, de, avec les mêmes variables | ❌ bloque |
| **2b · Tests** | tous les tests passent · couverture du code mesurée | ❌ bloque |
| **2c · Secrets** | aucun mot de passe ni clé oublié dans le code (Gitleaks) | ❌ bloque |
| **2c · Dépendances** | failles connues dans les bibliothèques (OSV-Scanner, Google) | ⚠️ signale |
| **3 · Numéro de build** | lu sur Google Play · version visible pas plus ancienne que celle en ligne | ❌ bloque |
| **3 · Signature** | empreinte SHA-256 **identique** à votre clé d'importation | ❌ bloque |
| **3 · Identité** | package, numéro de build et version conformes | ❌ bloque |
| **3 · Android ciblé** | targetSdk ≥ minimum exigé par Google Play | ❌ bloque |
| **3 · Permissions** | nouvelle permission par rapport à la référence | ⚠️ signale, en tête du résumé |
| **3 · Taille** | hausse de plus de 20 % par rapport au déploiement précédent | ⚠️ signale |
| **3 · Configuration** | adresse de l'API de production et Firebase présentes | ⚠️ signale |
| **4 · Émulateur** | l'app de release s'installe et démarre sans planter sur Android 14 (capture d'écran jointe) | ❌ bloque |
| **5 · Approbation** | vous relisez le résumé et approuvez | ✋ vous décidez |
| **6 · Publication** | intégrité des fichiers · numéro toujours libre · envoi (3 essais si réseau) · **présence vérifiée** sur Google Play | ❌ bloque |
| **6 · Trace** | tag `android-v1.0.6-build17` + Release GitHub (AAB, mapping, empreintes) | — |

### ✋ Que regarder avant d'approuver

Sur la page du déploiement, le **résumé** rassemble tout :

1. **Encadré ⚠️ « À vérifier avant d'approuver »** — s'il existe, lisez-le
   (nouvelle permission, taille, etc.). Une permission que vous n'attendiez pas
   ? Cliquez **Reject**.
2. **📝 Notes de version** — le texte que verront vos testeurs.
3. **📱 Test de démarrage** — la capture d'écran est dans l'artefact
   `test-demarrage`.

Puis **Review deployments** › cocher `google-play` › **Approve and deploy**.

### 📦 Ce qui est conservé

| Artefact | Contenu | Durée |
|---|---|---|
| `aab` | AAB envoyé, fichier de désobfuscation (mapping), manifeste, permissions, empreintes SHA-256 | 90 jours |
| `test-demarrage` | capture d'écran + journal Android du démarrage | 30 jours |
| `couverture` | rapport de couverture des tests (`lcov.info`) | 30 jours |
| Release GitHub | la même chose, **sans limite de durée**, pour chaque vraie publication | permanent |

---

## 🔧 Configuration initiale (une seule fois)

### ✅ Déjà fait

- Projet Google Cloud `widjila-deploy` + API Google Play Android Developer.
- Compte de service `fastlane-deploy@widjila-deploy.iam.gserviceaccount.com`,
  invité dans Play Console (app Widjila uniquement : lecture, publication,
  canaux de test).
- Secrets GitHub : `PLAY_SERVICE_ACCOUNT_JSON`, `ANDROID_KEYSTORE_PROPERTIES`,
  `ANDROID_KEYSTORE_BASE64`, `GOOGLE_SERVICES_JSON_BASE64`.

### 1️⃣ Empreinte de la clé d'importation (variable GitHub)

La chaîne compare la signature de chaque AAB à cette empreinte : un mauvais
keystore est arrêté avant d'atteindre Google.

1. **Play Console** › Widjila › **Tester et publier** › **Intégrité de
   l'application** › **Signature de l'application**.
2. Section **« Certificat de la clé d'importation »** : copier l'empreinte
   **SHA-256** (`AB:CD:…`).
3. **GitHub** › `widjila-mobile` › **Settings** › **Secrets and variables** ›
   **Actions** › onglet **Variables** › **New repository variable** :
   - Name : `ANDROID_UPLOAD_CERT_SHA256`
   - Value : l'empreinte copiée.

### 2️⃣ Environnement d'approbation `google-play`

> ⚠️ **Indispensable.** Sans cette étape, GitHub crée l'environnement tout
> seul, **sans approbation** : la publication partirait sans votre clic.

1. **Settings** › **Environments** › **New environment** › nom :
   **`google-play`** (exactement).
2. Cocher **Required reviewers** › ajouter **votre compte**.
3. Laisser **Prevent self-review** décoché (vous êtes seul à approuver).
4. **Deployment branches and tags** › **Selected branches and tags** › ajouter
   `release` **et** `main` (l'essai à blanc se lance depuis `main`).
5. **Save protection rules**.

### 3️⃣ Protection de la branche `release`

1. **Settings** › **Rules** › **Rulesets** › **New ruleset** › **New branch
   ruleset**.
2. Nom : `release protégée` · Enforcement : **Active**.
3. Target branches › **Add target** › **Include by pattern** › `release`.
4. Cocher **Restrict deletions** et **Block force pushes**.
5. **Create**.

---

## 🛠️ Dépannage

| Message | Cause | Solution |
|---|---|---|
| `Seul du code présent sur main peut être publié` | `release` poussé depuis une autre branche | `git push origin main` puis `git push origin main:release` |
| `Les notes n'ont pas changé depuis …` | notes identiques au déploiement précédent | écrire les nouveautés dans `fastlane/notes/fr-FR.txt` |
| `L'analyse a trouvé des erreurs ou des avertissements` | problème dans le code | lancer `flutter analyze` en local et corriger |
| Étape **Traductions** ❌ | texte ajouté en français seulement | ajouter la clé dans `app_en.arb`, `app_es.arb`, `app_de.arb` |
| `Un secret … a été trouvé dans le code` | mot de passe ou clé committé | le retirer **et le changer** (considéré comme compromis) |
| `Secret GitHub manquant : …` / `Variable GitHub manquante : …` | configuration incomplète | voir « Configuration initiale » ci-dessus |
| `The caller does not have permission` | droits Play Console pas encore actifs | attendre 24 à 36 h après l'invitation, ou revoir les autorisations |
| Signature ❌ « empreinte ≠ attendue » | mauvais keystore dans `ANDROID_KEYSTORE_BASE64`, ou variable erronée | vérifier le secret et `ANDROID_UPLOAD_CERT_SHA256` |
| `Keystore was tampered with, or password was incorrect` | mot de passe erroné | corriger `ANDROID_KEYSTORE_PROPERTIES` |
| `pubspec.yaml annonce … plus ancienne que …` | version visible inférieure à celle en ligne | augmenter `version:` dans `pubspec.yaml` |
| `Le build N n'est plus libre` | envoi manuel pendant l'approbation | relancer le déploiement |
| **Émulateur** ❌ « l'app s'est arrêtée » | plantage au démarrage en release | ouvrir l'artefact `test-demarrage` (`logcat.txt`, capture) |

## ↩️ Revenir à une version précédente

Google Play n'accepte que des numéros de build croissants : on **annule le
changement fautif sur `main`**, puis on publie normalement — l'ancien
comportement repart avec un nouveau numéro de build.

```bash
git revert <commit-fautif>          # sur main
# notes : « Retour à la version précédente : … »
git push origin main
git push origin main:release
```

La branche `release` ne fait qu'avancer avec `main` : jamais de force-push.

## 🔮 Plus tard

- **Production** — quand Google ouvrira l'accès : promotion de la version
  validée en Tests fermés vers la production, **progressive** (10 % → 50 % →
  100 %), avec arrêt possible si Crashlytics signale une hausse des plantages.
- **Permissions** — `tool/ci/android_reference.json` liste les permissions
  acceptées. Après le premier déploiement, y recopier la liste affichée dans
  le résumé (section « Permissions de ce build »).

## 🗂️ Fichiers

| Fichier | Rôle |
|---|---|
| `.github/workflows/android-release.yml` | la chaîne (7 étapes) |
| `android/fastlane/Fastfile` | Google Play : numéro de build, compilation, envoi, vérification |
| `android/fastlane/Appfile` | package et clé du compte de service |
| `fastlane/notes/fr-FR.txt` | **vos notes de version** |
| `tool/ci/controle_aab.py` | contrôle de l'AAB (signature, identité, permissions, taille…) |
| `tool/ci/android_reference.json` | valeurs de référence de ce contrôle |
| `tool/ci/traductions.py` | contrôle des traductions |
| `tool/ci/test_demarrage.sh` | test de démarrage sur émulateur |
| `.gitleaks.toml` | règles de la recherche de secrets |
| `.github/dependabot.yml` | mises à jour de sécurité des outils de la chaîne |
