#!/usr/bin/env bash
# Test de démarrage — l'APK construit depuis l'AAB de release, sur un vrai
# émulateur Android. Lancé par le workflow (android-emulator-runner).
#
# Vérifie ce qu'aucun test unitaire ne voit : l'app compilée en release
# (obfuscation, Firebase, signature) s'installe, démarre, et tient debout.
#
#   tool/ci/test_demarrage.sh <apk> <dossier-de-sortie>

set -euo pipefail

APK="$1"
SORTIE="$2"
PACKAGE="com.widjila.suivichantier"
ATTENTE=30 # secondes laissées à l'app pour démarrer et afficher son écran

mkdir -p "$SORTIE"
resume() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"; echo "$1"; }

echo "▶ Installation de $APK"
adb install -r "$APK"

adb logcat -c
echo "▶ Démarrage de $PACKAGE"
adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 > /dev/null
sleep "$ATTENTE"

PID="$(adb shell pidof "$PACKAGE" | tr -d '\r' || true)"
adb exec-out screencap -p > "$SORTIE/ecran-demarrage.png"
adb logcat -d > "$SORTIE/logcat.txt"

PLANTAGE="$(grep -E "FATAL EXCEPTION|Process: $PACKAGE" "$SORTIE/logcat.txt" || true)"
ERREURS_DART="$(grep -E "E/flutter.*(Unhandled Exception|\[ERROR)" "$SORTIE/logcat.txt" || true)"

resume "### 📱 Test de démarrage sur émulateur"
resume ""
resume "| Contrôle | Résultat | |"
resume "|---|---|:---:|"
resume "| Installation | APK installé | ✅ |"

ECHEC=0
if [ -n "$PID" ] && [ -z "$PLANTAGE" ]; then
  resume "| Démarrage | l'app tourne après ${ATTENTE} s (PID $PID) | ✅ |"
else
  resume "| Démarrage | l'app s'est arrêtée ou a planté | ❌ |"
  ECHEC=1
fi

if [ -n "$ERREURS_DART" ]; then
  resume "| Erreurs Dart | $(echo "$ERREURS_DART" | wc -l) erreur(s) non gérée(s) au démarrage — voir logcat | ⚠️ |"
else
  resume "| Erreurs Dart | aucune au démarrage | ✅ |"
fi
resume ""
resume "Capture d'écran et journal complets : artefact **test-demarrage** (en bas de la page)."
resume ""

if [ "$ECHEC" -ne 0 ]; then
  echo "::error::L'app ne démarre pas en release — extrait du journal :"
  echo "$PLANTAGE" | head -40
  exit 1
fi
