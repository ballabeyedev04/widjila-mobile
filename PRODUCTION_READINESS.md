# Mise en production — guide des étapes hors code

Ce guide couvre tout ce qui **ne peut pas être fait par un agent ou un commit** : générer des secrets que vous seul devez détenir, remplir des formulaires sur les consoles Google Play/Firebase, prendre des décisions de contenu (captures d'écran, description, politique de confidentialité). Le code, lui, est déjà prêt à recevoir ces éléments — voir la section « Ce que le code attend de vous » sous chaque étape.

Suivez les étapes **dans l'ordre** : chacune dépend de la précédente.

---

## 1. Générer le keystore de release (BLOQUANT)

C'est LE point qui empêche aujourd'hui toute publication : le build release est actuellement signé avec la clé de debug (publique, non sécurisée). Personne d'autre que vous ne doit générer ni détenir ce keystore.

### Générer le keystore

Depuis un terminal, sur votre machine (PAS dans un environnement partagé/CI à ce stade).

**Windows** (`cmd.exe` ou PowerShell — `~` n'est PAS étendu par `cmd.exe`, utilisez un chemin explicite) :
```
keytool -genkey -v -keystore %USERPROFILE%\upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**macOS/Linux** :
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool` fait partie du JDK (déjà installé avec Android Studio). Il vous demandera :
- un mot de passe pour le keystore (notez-le dans un gestionnaire de mots de passe — **si vous le perdez, vous ne pourrez plus jamais publier de mise à jour de cette application**, il faudra republier sous un nouvel `applicationId`) ;
- des informations d'identité (nom, organisation, ville, pays...) — utilisées uniquement dans le certificat, pas affichées aux utilisateurs ;
- un mot de passe pour l'alias `upload` (peut être identique à celui du keystore).

### Sauvegarder le keystore en lieu sûr

- Copiez `upload-keystore.jks` vers **au moins deux emplacements séparés** (gestionnaire de secrets d'équipe, coffre-fort chiffré, etc.) — jamais uniquement sur le disque qui a servi à le générer.
- Ne le mettez **jamais** dans le dépôt git (déjà exclu par `android/.gitignore` — `**/*.jks`, `**/*.keystore`, `key.properties`).

### Créer `android/key.properties`

À la racine de `android/` (PAS dans `android/app/`), créez un fichier `key.properties` :

```properties
storePassword=<mot_de_passe_du_keystore>
keyPassword=<mot_de_passe_de_l_alias>
keyAlias=upload
storeFile=/chemin/absolu/vers/upload-keystore.jks
```

Sous Windows, le chemin peut s'écrire avec des barres obliques normales (Gradle les accepte telles quelles), par exemple :
```properties
storeFile=C:/Users/vPro/upload-keystore.jks
```

**Ce que le code attend de vous** : `android/app/build.gradle.kts` lit déjà ce fichier automatiquement (voir le bloc `keystoreProperties`/`signingConfigs` en haut du fichier). Dès que `key.properties` existe avec ces quatre clés, `flutter build appbundle --release` produira un artefact signé avec VOTRE clé, plus jamais avec la clé de debug. Sans ce fichier, un avertissement explicite s'affiche à chaque build Gradle (`android/key.properties ABSENT...`) — c'est voulu, pour qu'il soit impossible de rater l'oubli avant une publication.

### Vérifier avant de publier

```bash
cd android
./gradlew signingReport
```

Cherchez la variante `release` dans la sortie : son SHA-256 doit correspondre à votre keystore, pas à `androiddebugkey`.

---

## 2. Activer Firebase Crashlytics

Le code (`lib/main.dart`) envoie déjà toutes les erreurs Flutter/Dart et natives vers Crashlytics — mais Crashlytics doit être **activé côté Firebase Console** pour que ces rapports soient réellement collectés.

1. Allez sur [console.firebase.google.com](https://console.firebase.google.com), projet `widjila`.
2. Menu de gauche → **DevOps et engagement** → **Crashlytics**, puis « Activer Crashlytics »/« Commencer ».
   (Firebase proposera d'installer le SDK : c'est déjà fait — `firebase_crashlytics` dans `pubspec.yaml`,
   branché dans `main.dart`. Passez cette étape.)
   Crashlytics est inclus dans le plan gratuit **Spark**, aucune mise à niveau n'est nécessaire.
3. Si Crashlytics affiche « en attente de données » : c'est normal tant qu'aucun crash n'a été envoyé — provoquez un crash de test (voir ci-dessous), il apparaîtra en quelques minutes.
4. Assurez-vous que `google-services.json` déposé dans `android/app/` est bien celui du projet Firebase où Crashlytics est activé (vérifiable : le champ `project_id` dans ce fichier doit correspondre au projet ouvert dans la console).

### Provoquer un crash de test (à faire une fois, en interne)

Ajoutez temporairement un bouton quelque part dans un écran de debug qui appelle :
```dart
FirebaseCrashlytics.instance.crash();
```
Lancez l'app en mode **release** (`flutter run --release`), déclenchez le crash, relancez l'app (le rapport part au démarrage suivant), et vérifiez son apparition dans la console sous 5 minutes. Retirez ensuite ce bouton — il ne doit jamais atteindre la production.

**Ce que le code attend de vous** : rien de plus une fois Crashlytics activé côté console — la collecte est déjà désactivée automatiquement en mode debug (`setCrashlyticsCollectionEnabled(!kDebugMode)` dans `main.dart`), donc vos sessions de développement ne polluent pas les statistiques de production.

---

## 3. Certificate pinning — DÉCISION : ne pas l'activer

**Statut : tranché, aucune action requise.** Le code sait épingler un certificat
(`lib/core/network/dio_client_factory.dart` cherche `assets/certs/backend_ca.pem`),
ne le trouve pas, et retombe proprement sur la validation TLS standard du système.
C'est le comportement voulu — ne bundlez pas de certificat.

### Pourquoi (constaté sur la vraie infrastructure)

Inspection de `api.widjila.com` :
```
subject = CN=api.widjila.com
issuer  = C=US, O=Let's Encrypt, CN=YE2
```

L'API est servie derrière **Let's Encrypt**, ce qui rend les trois candidats à
l'épinglage inexploitables :

| Candidat | Problème |
|---|---|
| Certificat serveur (`CN=api.widjila.com`) | Renouvelé tous les **90 jours** → l'app cesserait de joindre l'API 4 fois par an, réparable seulement par une mise à jour Store |
| Intermédiaire (`CN=YE2`) | Let's Encrypt **déconseille explicitement** d'épingler ses intermédiaires et se réserve le droit de les changer sans préavis (historique : X3 → R3 → R10/R11, puis séries ECDSA) |
| Racine ISRG Root X1 | Stable jusqu'en 2035, mais revient à « j'accepte tout certificat Let's Encrypt » — bénéfice marginal, et casse à la moindre migration vers Cloudflare/AWS/autre émetteur |

### Ce qui protège le trafic aujourd'hui

Chiffrement TLS, validation de la chaîne de confiance système, vérification du nom
de domaine et de l'expiration — le même niveau qu'un navigateur. Le pinning n'aurait
ajouté qu'une protection contre une autorité de certification compromise : scénario
réel mais rare et ciblé, sans commune mesure avec la **certitude** d'une panne totale
à chaque rotation de certificat.

### Si l'infrastructure change un jour

Ce point ne redevient pertinent que si `api.widjila.com` migre vers une PKI interne
ou un certificat à validité longue (2 ans et plus) que vous contrôlez. Dans ce cas,
et seulement dans ce cas, reprendre : extraire la chaîne d'autorité
(`openssl s_client -connect api.widjila.com:443 -showcerts </dev/null 2>/dev/null | awk '/BEGIN CERT/{n++} n>1' > assets/certs/backend_ca.pem`),
la placer dans `assets/certs/`, déclarer `- assets/certs/` sous `assets:` dans
`pubspec.yaml`, et **noter la date d'expiration** (`openssl x509 -in ... -noout -dates`)
avec un rappel calendaire pour publier une mise à jour AVANT cette date.

---

## 4. Google Play Console — enrôlement et App Signing

1. Créez (ou ouvrez) l'application dans la [Google Play Console](https://play.google.com/console).
2. **App integrity** → laissez Google gérer la clé d'app signing (recommandé) : vous uploadez votre AAB signé avec la clé « upload » générée à l'étape 1, Google le re-signe avec sa propre clé pour la distribution — c'est le fonctionnement standard actuel, pas une option dépréciée.
3. Premier upload : `flutter build appbundle --release`, puis déposez le `.aab` généré (`build/app/outputs/bundle/release/app-release.aab`) dans un track de test interne d'abord (jamais directement en production).

**Ce que le code attend de vous** : rien de plus — le `versionCode`/`versionName` viennent de `pubspec.yaml` (`version: 1.0.0+1` actuellement). Incrémentez le nombre après le `+` à chaque nouvel upload (`1.0.0+2`, `1.0.0+3`...), Play Console refuse un `versionCode` déjà utilisé.

---

## 5. Data Safety (obligatoire avant publication)

Dans Play Console → **Politique de l'app** → **Sécurité des données**, déclarez ce que l'app collecte réellement. D'après ce qui est effectivement implémenté dans le code à date :

| Donnée | Collectée ? | Où / pourquoi |
|---|---|---|
| Email | Oui | Compte utilisateur (`Utilisateur.email`) |
| Nom, prénom, téléphone | Oui | Compte utilisateur |
| Photos | Oui | Réserves, documents, avatar |
| Localisation précise | Oui, si présente | Géolocalisation des photos/médias (`latitude`/`longitude` sur `Media`) — **uniquement si l'utilisateur laisse cette donnée dans l'EXIF de la photo/le device**, vérifiez avec votre équipe si une géolocalisation est explicitement demandée ailleurs |
| Identifiants d'appareil | Oui | Jeton FCM (push), `DeviceToken` |
| Données financières | Non | Aucun paiement dans le code actuel |
| Données de crash/diagnostic | Oui (nouveau) | Firebase Crashlytics — à déclarer maintenant que P2 est corrigé |

Cochez également : chiffrement des données en transit (oui, HTTPS), possibilité de suppression des données (oui — `DELETE /account/delete-account`, câblé dans l'écran Paramètres).

---

## 6. Privacy Policy et CGU — vérifier le contenu réel

Le code pointe déjà vers deux URLs bien réelles :
- `https://app.widjila.com/condition-utilisation`
- `https://app.widjila.com/politique-confidentialite`

Avant publication, **ouvrez ces deux pages et vérifiez** :
- qu'elles sont en ligne et accessibles publiquement (Google Play les vérifie) ;
- que le contenu mentionne explicitement les catégories de données du tableau ci-dessus (email, photos, localisation si applicable, jeton push, **et maintenant Crashlytics**) ;
- que la politique de confidentialité décrit la procédure de suppression de compte (déjà implémentée côté app, doit être documentée côté légal aussi).

Ce contenu est éditorial/juridique — ni moi ni un agent ne peut le rédiger de façon fiable à votre place ; faites-le valider par la personne responsable de la conformité RGPD de votre organisation.

---

## 7. Store listing

À préparer et renseigner dans Play Console → **Présence sur le Store** :

- **Icône** : déjà générée depuis `assets/launcher/app-icon.png` via `flutter_launcher_icons` (config dans `pubspec.yaml`) — régénérez avec `dart run flutter_launcher_icons` si le logo a changé depuis le dernier build.
- **Captures d'écran** : au moins 2 par format d'appareil (téléphone obligatoire, tablette recommandé). Prenez-les depuis un build release réel (`flutter build apk --release` puis installation sur device/émulateur), pas depuis le mode debug (bannières de debug visibles sinon).
- **Feature graphic** (1024×500) : bannière promotionnelle, à concevoir.
- **Description courte/longue** : en français a minima ; l'app étant traduite en 4 langues (fr/en/de/es), envisagez une fiche Store dans chaque langue pour cohérence.
- **Content rating** : questionnaire Play Console — pour une app professionnelle de suivi de chantier sans contenu utilisateur public ni violence/contenu adulte, la classification attendue est "Tout public"/"Everyone", à confirmer en répondant honnêtement au questionnaire.

---

## 8. Test interne avant production

1. Uploadez l'AAB signé dans le track **Internal testing**.
2. Ajoutez des testeurs (email) dans Play Console.
3. Installez depuis le lien de test interne sur au moins deux appareils Android physiques différents (pas seulement un émulateur) — vérifiez en particulier :
   - la demande de permission photo/caméra fonctionne (elle dépend de la fusion automatique des manifests `image_picker`/`file_picker`, jamais testée sur un build release dans le cadre de cette session) ;
   - les notifications push arrivent bien (nécessite un vrai appareil, FCM ne fonctionne pas sur certains émulateurs sans Google Play Services) ;
   - le flux MFA (activation, désactivation), sessions actives et suppression de compte dans l'écran Paramètres — fonctionnalités neuves de cette session, désormais couvertes par des tests automatisés mais jamais exercées manuellement contre un vrai backend.
4. Ne passez en production qu'après ce test interne concluant.

---

## 9. Après la mise en ligne

- Surveillez le tableau de bord Crashlytics dans les 48h suivant chaque release — c'est désormais votre seule fenêtre sur les crashs réels.
- `flutter pub outdated` régulièrement (52+ paquets avaient une version plus récente au moment de cet audit) — planifiez une passe de mise à jour trimestrielle plutôt que de laisser la dette s'accumuler indéfiniment.
- Le certificat pinné (si vous avez fait l'étape 3) doit être suivi : notez sa date d'expiration et planifiez son renouvellement dans l'app AVANT l'expiration côté serveur.
