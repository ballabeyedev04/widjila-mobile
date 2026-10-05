#!/usr/bin/env bash
# Sélectionne le Xcode le plus récent installé, et refuse si son SDK iOS est
# plus ancien que ce qu'Apple accepte.
#
# Pourquoi ne pas se contenter de /Applications/Xcode.app : ce lien désigne
# le Xcode « par défaut » de la machine, qui n'est pas le plus récent
# installé. Une image d'intégration porte plusieurs Xcode à la fois, et le
# défaut reste longtemps en arrière. On s'en est aperçu de la pire façon :
# après quinze minutes de compilation, Apple a refusé l'IPA — « built with
# the iOS 18.5 SDK, must be built with the iOS 26 SDK or later » — alors
# qu'un Xcode 26 dormait sur la même machine.
#
# Apple fixe un SDK minimum et le relève chaque année, quelques mois après
# la sortie d'une version d'iOS. Le refus tombe à l'ENVOI, pas à la
# compilation : sans ce contrôle, on paie la compilation pour rien.
#
#   tool/ci/choisir_xcode.sh <majeur-minimum-du-sdk-ios>

set -euo pipefail

SDK_MINIMUM="${1:?majeur minimum du SDK iOS attendu}"

meilleur=""
version_max="0"
disponibles=""

for app in /Applications/Xcode*.app; do
  [ -d "$app" ] || continue

  # Deux précautions pour une seule ligne, et chacune a coûté une exécution :
  #
  #  - pas de `| head -1` : sous `pipefail`, `head` ferme le tuyau après la
  #    première ligne et tue `xcodebuild`, qui meurt sur SIGABRT ; le
  #    pipeline échoue, et `set -e` emporte le script entier (code 134).
  #    `awk` lit tout, il ne ferme rien tôt ;
  #  - `|| true` : un Xcode incomplet, en version d'essai ou dont la licence
  #    n'est pas acceptée répond en erreur. Ce n'est pas une raison
  #    d'abandonner les autres. `|| true` garde malgré tout ce qui a été
  #    affiché — `|| sortie=""` jetterait une version pourtant lisible.
  sortie="$("$app/Contents/Developer/usr/bin/xcodebuild" -version 2>/dev/null)" || true
  version="$(printf '%s\n' "$sortie" | awk 'NR==1 {print $2}')"

  if [ -z "$version" ]; then
    echo "  (ignoré : $app ne répond pas)"
    continue
  fi
  disponibles="$disponibles  - Xcode $version ($app)"$'\n'
  if [ "$(printf '%s\n%s\n' "$version_max" "$version" | sort -V | tail -1)" = "$version" ]; then
    meilleur="$app"
    version_max="$version"
  fi
done

if [ -z "$meilleur" ]; then
  echo "::error::Aucun Xcode utilisable dans /Applications."
  exit 1
fi

echo "Xcode installés sur cette machine :"
printf '%s' "$disponibles"
echo "→ retenu : Xcode $version_max ($meilleur)"

sudo xcode-select -switch "$meilleur"
SDK="$(xcrun --sdk iphoneos --show-sdk-version)"

if [ "${SDK%%.*}" -lt "$SDK_MINIMUM" ]; then
  echo "::error::Le Xcode le plus récent de cette machine (Xcode $version_max) fournit le SDK iOS $SDK, alors qu'Apple exige le SDK iOS $SDK_MINIMUM ou plus récent pour tout envoi. Changez l'image de la machine (runs-on) pour une plus récente — voir docs/DEPLOIEMENT_IOS.md."
  printf 'Xcode disponibles :\n%s' "$disponibles"
  exit 1
fi

{
  echo "XCODE_VERSION=$version_max"
  echo "IOS_SDK_VERSION=$SDK"
} >> "${GITHUB_ENV:-/dev/null}"

echo "SDK iOS $SDK — conforme (minimum exigé par Apple : $SDK_MINIMUM)"
