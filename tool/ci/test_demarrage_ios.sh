#!/usr/bin/env bash
# Test de démarrage — l'app sur un vrai simulateur iOS. Lancé par le workflow
# .github/workflows/ios-release.yml.
#
# Vérifie ce qu'aucun test unitaire ne voit : sur une installation NEUVE,
# l'app s'installe, démarre, et tient debout — plugins iOS enregistrés, base
# locale créée, premier écran affiché.
#
# Limite assumée : un simulateur n'exécute pas de build « release » (Flutter
# ne le produit pas pour simulateur) ni de code signé. Ce test répond à
# « l'app démarre-t-elle ? » ; la conformité du binaire envoyé à Apple est
# contrôlée séparément par tool/ci/controle_ipa.py.
#
#   tool/ci/test_demarrage_ios.sh <app-simulateur> <dossier-de-sortie>

set -euo pipefail

APP="$1"
SORTIE="$2"
BUNDLE="com.widjila.suivichantier"
ATTENTE=30 # secondes laissées à l'app pour démarrer et afficher son écran

mkdir -p "$SORTIE"
resume() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"; echo "$1"; }

# ── Un simulateur neuf, créé ici ───────────────────────────────────────────
# Le modèle et la version d'iOS sont CHOISIS parmi ce que la machine propose,
# jamais supposés : les images d'intégration changent de contenu sans
# préavis, et un nom de simulateur écrit en dur casse la chaîne un matin.
RUNTIME="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
dispo = [r for r in json.load(sys.stdin)["runtimes"]
         if r["isAvailable"] and "SimRuntime.iOS" in r["identifier"]]
if not dispo:
    sys.exit("aucun runtime iOS disponible sur cette machine")
print(sorted(dispo, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]["identifier"])
')"
TYPE="$(xcrun simctl list devicetypes -j | python3 -c '
import json, re, sys
iphones = [d for d in json.load(sys.stdin)["devicetypes"]
           if "SimDeviceType.iPhone" in d["identifier"]]
if not iphones:
    sys.exit("aucun modele iPhone disponible sur cette machine")
numero = lambda d: (int(re.findall(r"\d+", d["name"])[0]) if re.findall(r"\d+", d["name"]) else 0, d["name"])
print(sorted(iphones, key=numero)[-1]["identifier"])
')"

UDID="$(xcrun simctl create widjila-ci "$TYPE" "$RUNTIME")"
JOURNAL=""

# Quoi qu'il arrive : le suivi du journal est arrêté et le simulateur effacé
# — il garde une copie de l'app et de ses données.
#
# Deux précautions, et chacune a sa raison :
#
#  - le code de sortie est relevé À L'ENTRÉE et rendu À LA SORTIE. Sans
#    cela, le résultat du script devient celui du nettoyage : un test réussi
#    pouvait échouer parce que le journal était déjà arrêté, et un test
#    raté aurait pu passer pour réussi ;
#  - chaque commande se termine par « || true ». Sous `set -e`, la première
#    qui échoue interrompt le nettoyage : le simulateur restait allumé, et
#    la suite n'était jamais exécutée.
menage() {
  code=$?
  if [ -n "$JOURNAL" ]; then kill "$JOURNAL" 2>/dev/null || true; fi
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  exit "$code"
}
trap menage EXIT
echo "▶ Simulateur $(xcrun simctl list devices -j | python3 -c "import json,sys; print([d['name'] for g in json.load(sys.stdin)['devices'].values() for d in g if d['udid']=='$UDID'][0])") ($RUNTIME)"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

echo "▶ Installation de $APP"
xcrun simctl install booted "$APP"

# Journal capturé en direct : `log show` après coup rate ce qui est écrit
# avant que le simulateur ne vide ses tampons.
xcrun simctl spawn booted log stream --level debug --style compact > "$SORTIE/journal.txt" 2>/dev/null &
JOURNAL=$!
sleep 2

echo "▶ Démarrage de $BUNDLE"
# `simctl launch` rend « bundle: <pid> » — le PID est celui d'un vrai
# processus de la machine hôte, donc observable avec `ps`.
LANCEMENT="$(xcrun simctl launch booted "$BUNDLE")"
PID="$(echo "$LANCEMENT" | sed 's/.*: *//' | tr -d '[:space:]')"
echo "   $LANCEMENT"
sleep "$ATTENTE"

VIVANT=0
if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then VIVANT=1; fi

xcrun simctl io booted screenshot "$SORTIE/ecran-demarrage.png" > /dev/null 2>&1 || true
kill "$JOURNAL" 2>/dev/null || true
sleep 1

PLANTAGE="$(grep -E "Fatal error|signal SIGABRT|Terminating app due to|crashed" "$SORTIE/journal.txt" 2>/dev/null || true)"
ERREURS_DART="$(grep -E "flutter.*(Unhandled Exception|\[ERROR)" "$SORTIE/journal.txt" 2>/dev/null || true)"

# Rapports de plantage du simulateur : la preuve la plus nette qu'il y en a eu.
RAPPORTS="$HOME/Library/Logs/DiagnosticReports"
if [ -d "$RAPPORTS" ]; then
  find "$RAPPORTS" -name 'Runner*' -newermt "-5 minutes" -exec cp {} "$SORTIE/" \; 2>/dev/null || true
fi
NB_RAPPORTS="$(find "$SORTIE" -name 'Runner*.ips' -o -name 'Runner*.crash' 2>/dev/null | wc -l | tr -d ' ')"

resume "### 📱 Test de démarrage sur simulateur"
resume ""
resume "| Contrôle | Résultat | |"
resume "|---|---|:---:|"
resume "| Installation | app installée sur une installation neuve | ✅ |"

ECHEC=0
if [ "$VIVANT" -eq 1 ] && [ -z "$PLANTAGE" ] && [ "$NB_RAPPORTS" -eq 0 ]; then
  resume "| Démarrage | l'app tourne après ${ATTENTE} s (PID $PID) | ✅ |"
else
  resume "| Démarrage | l'app s'est arrêtée ou a planté | ❌ |"
  ECHEC=1
fi

if [ -n "$ERREURS_DART" ]; then
  resume "| Erreurs Dart | $(echo "$ERREURS_DART" | wc -l | tr -d ' ') erreur(s) non gérée(s) au démarrage — voir le journal | ⚠️ |"
else
  resume "| Erreurs Dart | aucune au démarrage | ✅ |"
fi
resume ""
resume "Capture d'écran et journal complets : artefact **test-demarrage-ios** (en bas de la page)."
resume ""

if [ "$ECHEC" -ne 0 ]; then
  echo "::error::L'app ne démarre pas sur simulateur — extrait du journal :"
  echo "$PLANTAGE" | head -40
  tail -60 "$SORTIE/journal.txt" || true
  exit 1
fi
