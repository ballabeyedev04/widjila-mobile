#!/usr/bin/env python3
"""Contrôle de l'AAB avant tout envoi à Google Play.

Lit le manifeste extrait par bundletool et les mesures faites par le workflow,
les compare à tool/ci/android_reference.json, puis écrit un rapport Markdown
dans $GITHUB_STEP_SUMMARY.

BLOQUANT (code de sortie 1) :
  - signature : l'empreinte du certificat n'est pas celle de la clé d'import ;
  - identité : package, numéro de build ou version différents de l'attendu ;
  - targetSdk sous le minimum exigé par Google Play.

AVERTISSEMENT (le déploiement continue, affiché en tête du rapport) :
  - permission absente de la liste de référence ;
  - targetSdk sous la valeur recommandée ;
  - taille en hausse anormale ;
  - adresse de l'API ou configuration Firebase non retrouvées.
"""

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = "{http://schemas.android.com/apk/res/android}"


def empreinte(valeur: str) -> str:
    return valeur.replace(":", "").replace(" ", "").strip().upper()


def taille_lisible(octets: int) -> str:
    return f"{octets / 1024 / 1024:.1f} Mo"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", required=True)
    p.add_argument("--reference", required=True)
    p.add_argument("--version-code", required=True, type=int)
    p.add_argument("--version-name", required=True)
    p.add_argument("--empreinte", required=True, help="SHA-256 du certificat de l'AAB")
    p.add_argument("--empreinte-attendue", default="", help="SHA-256 de la clé d'importation (Play Console)")
    p.add_argument("--taille", required=True, type=int)
    p.add_argument("--taille-precedente", default="")
    p.add_argument("--api-trouvee", required=True, choices=["oui", "non"])
    p.add_argument("--firebase", required=True, choices=["oui", "non"])
    p.add_argument("--permissions-sortie", required=True)
    a = p.parse_args()

    ref = json.loads(Path(a.reference).read_text(encoding="utf-8"))
    racine = ET.parse(a.manifest).getroot()

    package = racine.get("package", "")
    code = racine.get(f"{ANDROID}versionCode", "")
    nom = racine.get(f"{ANDROID}versionName", "")
    sdk = racine.find("uses-sdk")
    target = int(sdk.get(f"{ANDROID}targetSdkVersion", "0")) if sdk is not None else 0
    minimum = sdk.get(f"{ANDROID}minSdkVersion", "?") if sdk is not None else "?"
    permissions = sorted(
        {e.get(f"{ANDROID}name", "") for e in racine.iter() if e.tag in ("uses-permission", "uses-permission-sdk-23")} - {""}
    )
    Path(a.permissions_sortie).write_text("\n".join(permissions) + "\n", encoding="utf-8")

    controles = []  # (libellé, valeur, statut) — statut : ok / alerte / bloque
    alertes = []

    def ajouter(libelle, valeur, statut, alerte=None):
        controles.append((libelle, valeur, statut))
        if alerte:
            alertes.append(alerte)

    # ── Signature ───────────────────────────────────────────────────────────
    reelle = empreinte(a.empreinte)
    attendue = empreinte(a.empreinte_attendue)
    if not reelle:
        ajouter("Signature", "certificat illisible", "bloque")
    elif not attendue:
        ajouter("Signature", f"`{reelle[:16]}…` — empreinte de référence non configurée", "bloque")
    elif reelle == attendue:
        ajouter("Signature", "clé d'importation Widjila ✔ (empreinte SHA-256 identique)", "ok")
    else:
        ajouter("Signature", f"empreinte `{reelle[:16]}…` ≠ attendue `{attendue[:16]}…`", "bloque")

    # ── Identité ────────────────────────────────────────────────────────────
    ajouter("Package", f"`{package}`", "ok" if package == ref["package"] else "bloque")
    ajouter("Numéro de build", code, "ok" if code == str(a.version_code) else "bloque")
    ajouter("Version", nom, "ok" if nom == a.version_name else "bloque")

    # ── Exigences Google Play ───────────────────────────────────────────────
    if target < ref["target_sdk_minimum"]:
        ajouter("Android ciblé (targetSdk)", f"API {target} — minimum Google Play : {ref['target_sdk_minimum']}", "bloque")
    elif target < ref["target_sdk_recommande"]:
        ajouter("Android ciblé (targetSdk)", f"API {target}", "alerte",
                f"Android ciblé : API {target}, Google Play recommande désormais {ref['target_sdk_recommande']}.")
    else:
        ajouter("Android ciblé (targetSdk)", f"API {target} (minimum supporté : API {minimum})", "ok")

    # ── Permissions ─────────────────────────────────────────────────────────
    acceptees = set(ref.get("permissions", []))
    if not acceptees:
        ajouter("Permissions", f"{len(permissions)} — référence à établir", "alerte",
                "Liste de référence des permissions vide : à compléter avec la liste de ce build (voir plus bas).")
    else:
        nouvelles = [x for x in permissions if x not in acceptees]
        retirees = sorted(acceptees - set(permissions))
        if nouvelles:
            ajouter("Permissions", f"{len(permissions)} dont {len(nouvelles)} NOUVELLE(S)", "alerte",
                    "Nouvelle(s) permission(s) : " + ", ".join(f"`{x}`" for x in nouvelles)
                    + " — vérifiez qu'elles sont voulues avant d'approuver.")
        else:
            ajouter("Permissions", f"{len(permissions)}, toutes connues", "ok")
        if retirees:
            alertes.append("Permission(s) retirée(s) depuis la référence : " + ", ".join(f"`{x}`" for x in retirees) + ".")

    # ── Taille ──────────────────────────────────────────────────────────────
    if a.taille_precedente.isdigit() and int(a.taille_precedente) > 0:
        avant = int(a.taille_precedente)
        ecart = (a.taille - avant) * 100 / avant
        texte = f"{taille_lisible(a.taille)} ({ecart:+.1f} % vs {taille_lisible(avant)})"
        if ecart > ref["croissance_taille_alerte_pct"]:
            ajouter("Taille de l'AAB", texte, "alerte", f"L'app grossit de {ecart:.0f} % par rapport au déploiement précédent.")
        else:
            ajouter("Taille de l'AAB", texte, "ok")
    else:
        ajouter("Taille de l'AAB", f"{taille_lisible(a.taille)} (premier déploiement suivi)", "ok")

    # ── Configuration embarquée ─────────────────────────────────────────────
    if a.api_trouvee == "oui":
        ajouter("Adresse de l'API", f"`{ref['api_attendue']}`", "ok")
    else:
        ajouter("Adresse de l'API", "non retrouvée dans le binaire", "alerte",
                f"L'adresse `{ref['api_attendue']}` n'a pas été retrouvée dans le code compilé.")
    if a.firebase == "oui":
        ajouter("Firebase", "configuration présente", "ok")
    else:
        ajouter("Firebase", "configuration absente", "alerte",
                "Configuration Firebase absente : notifications push et Crashlytics inactifs dans ce build.")

    # ── Rapport ─────────────────────────────────────────────────────────────
    icone = {"ok": "✅", "alerte": "⚠️", "bloque": "❌"}
    bloque = any(s == "bloque" for _, _, s in controles)
    lignes = ["### 🔍 Contrôle de l'AAB", ""]
    if bloque:
        lignes += ["> [!CAUTION]", "> **Envoi refusé** : au moins un contrôle bloquant a échoué.", ""]
    if alertes:
        lignes += ["> [!WARNING]", "> **À vérifier avant d'approuver :**"] + [f"> - {x}" for x in alertes] + [""]
    lignes += ["| Contrôle | Résultat | |", "|---|---|:---:|"]
    lignes += [f"| {l} | {v} | {icone[s]} |" for l, v, s in controles]
    lignes += ["", "<details><summary>Permissions de ce build</summary>", "", "```", *permissions, "```", "</details>", ""]

    resume = "\n".join(lignes) + "\n"
    print(resume)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as f:
            f.write(resume)
    return 1 if bloque else 0


if __name__ == "__main__":
    sys.exit(main())
