# Déploiement Android automatique (Google Play)

Un push sur la branche `release` compile l'app, lui donne le numéro de build
suivant, et l'envoie en **Tests fermés - Alpha** sur Google Play avec les
notes de version en français. Plus besoin de créer la version, déposer l'AAB
ni coller les notes à la main dans Play Console.

## Publier une nouvelle version

1. Écrire les nouveautés dans `fastlane/notes/fr-FR.txt` (500 caractères
   maximum — c'est le bloc `<fr-FR>` de Play Console).
2. Si la version visible change (1.0.6 → 1.0.7), modifier `version:` dans
   `pubspec.yaml`. Le numéro après le `+` n'a **pas** besoin d'être touché :
   le déploiement prend le dernier numéro connu de Google Play et ajoute 1.
3. Committer sur `main`, puis publier :

   ```bash
   git push origin main
   git push origin main:release
   ```

4. Suivre le déploiement dans l'onglet **Actions** du dépôt GitHub
   (environ 10 à 15 minutes). GitHub envoie un e-mail en cas d'échec.
5. Google vérifie ensuite la version (quelques heures), puis vos testeurs la
   reçoivent.

Un push sur `main` seul ne publie **rien**.

### Essai à blanc

Onglet **Actions** > « Android — Google Play » > **Run workflow** (case
« Essai à blanc » cochée) : tout est fait, Google Play valide l'envoi, mais
rien n'est publié et aucun numéro de build n'est consommé.

## Ce que fait le déploiement

`.github/workflows/android-release.yml` puis `android/fastlane/Fastfile` :

1. installe Flutter 3.44.8, Java 17 et Fastlane ;
2. lance **tous les tests** — rien ne part si l'un échoue ;
3. recrée depuis les secrets GitHub : keystore, `android/key.properties`,
   `android/app/google-services.json`, clé du compte de service ;
4. vérifie les notes (non vides, 500 caractères max) et la signature ;
5. demande à Google Play le dernier numéro de build (tous canaux) et ajoute 1 ;
6. `flutter build appbundle --release` ;
7. refuse l'envoi si l'AAB est signé avec la clé de debug ;
8. envoie l'AAB, le fichier de désobfuscation (mapping) et les notes fr-FR en
   Tests fermés - Alpha ;
9. efface les secrets de la machine.

La fiche Play Store, les captures et les autres langues ne sont jamais
modifiées.

## Configuration initiale (une seule fois)

### Google Cloud et Play Console — FAIT

- Projet Google Cloud `widjila-deploy`, API « Google Play Android Developer
  API » activée.
- Compte de service `fastlane-deploy@widjila-deploy.iam.gserviceaccount.com`,
  clé JSON téléchargée.
- Invité dans Play Console, limité à l'app Widjila, avec : afficher les
  informations de l'application, publier en production, déployer sur les
  canaux de test, gérer les canaux de test.

### Secrets GitHub

Dépôt `widjila-mobile` > **Settings** > **Secrets and variables** >
**Actions** > **New repository secret**. Quatre secrets :

| Nom | Contenu |
|---|---|
| `PLAY_SERVICE_ACCOUNT_JSON` | le contenu du fichier JSON du compte de service (ouvrir avec le Bloc-notes, tout copier) |
| `ANDROID_KEYSTORE_PROPERTIES` | le contenu de `android/key.properties` (tout copier) |
| `ANDROID_KEYSTORE_BASE64` | le keystore `.jks`, converti en texte (commande ci-dessous) |
| `GOOGLE_SERVICES_JSON_BASE64` | `android/app/google-services.json`, converti en texte (commande ci-dessous) |

Conversion en texte, dans **Git Bash** depuis le dossier `mobile/` (le fichier
produit contient le texte à coller dans le secret) :

```bash
base64 -w0 android/app/google-services.json > google-services.b64.txt
base64 -w0 android/<chemin du keystore .jks> > keystore.b64.txt
```

Le chemin du keystore est la valeur `storeFile=` de `android/key.properties`
(relative au dossier `android/`). Une fois les secrets enregistrés,
**supprimer** les deux fichiers `.b64.txt` — ils ne doivent pas être committés.

Le secret `API_BASE_URL` est facultatif : l'app vise déjà
`https://api.widjila.com/api/v1` par défaut (`lib/core/config/env.dart`).

## Dépannage

| Message | Cause | Solution |
|---|---|---|
| `Secret GitHub manquant : …` | secret absent ou mal nommé | le créer (noms exacts ci-dessus) |
| `The caller does not have permission` | droits Play Console pas encore actifs | attendre 24 à 36 h après l'invitation, ou revoir les autorisations |
| `Version code N has already been used` | envoi manuel en parallèle | relancer : le numéro est recalculé |
| `L'AAB est signé avec la clé de DEBUG` | `ANDROID_KEYSTORE_PROPERTIES` incomplet | vérifier le secret (storePassword, keyPassword, keyAlias) |
| `Keystore was tampered with, or password was incorrect` | mot de passe erroné | corriger `ANDROID_KEYSTORE_PROPERTIES` |
| `fastlane/notes/fr-FR.txt est vide` / `… caractères` | notes absentes ou trop longues | les écrire, 500 caractères max |

## Plus tard : la production

L'app est encore en phase de test (pas d'accès production). Quand Google
l'ouvrira, on ajoutera une étape « promouvoir la version de Tests fermés en
production » — le même AAB que les testeurs ont validé, sans recompiler.
