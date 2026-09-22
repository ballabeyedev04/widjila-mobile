#!/usr/bin/env python3
"""Contrôle des traductions — chaque texte existe dans toutes les langues.

Référence : lib/l10n/app_fr.arb (le `template-arb-file` de l'app). Pour chaque
autre langue, on vérifie :
  - aucune clé manquante (le texte s'afficherait en français, ou pas du tout) ;
  - aucune clé orpheline (texte supprimé du français mais resté ailleurs) ;
  - les mêmes variables {nom} dans chaque texte (une variable manquante fait
    échouer la génération ou afficher « {nom} » à l'écran).

Écrit un résumé Markdown dans $GITHUB_STEP_SUMMARY. Code de sortie 1 si une
langue est incomplète.
"""

import json
import os
import re
import sys
from pathlib import Path

DOSSIER = Path(__file__).resolve().parents[2] / "lib" / "l10n"
REFERENCE = "app_fr.arb"
# `{nom}` ou `{nom, plural, …}` — pas le contenu d'une branche plurielle,
# collée à son mot-clé (« one{Mot… », « other{jours} » ne sont pas des variables).
VARIABLE = re.compile(r"(?<!\w)\{(\w+)\s*[,}]")


def textes(fichier: Path) -> dict:
    donnees = json.loads(fichier.read_text(encoding="utf-8"))
    return {k: v for k, v in donnees.items() if not k.startswith("@") and isinstance(v, str)}


def variables(texte: str) -> set:
    # Les formes plurielles/select imbriquent des accolades : seules les
    # variables de premier niveau comptent, les mots-clés ICU sont exclus.
    return {v for v in VARIABLE.findall(texte) if v not in {"plural", "select", "other", "one", "zero", "few", "many", "two"}}


def main() -> int:
    reference = textes(DOSSIER / REFERENCE)
    lignes = ["### 🌍 Traductions", "", "| Langue | Textes | Manquants | En trop | Variables incohérentes | Résultat |", "|---|---:|---:|---:|---:|:---:|"]
    lignes.append(f"| `fr` (référence) | {len(reference)} | — | — | — | ✅ |")
    erreurs = []

    for fichier in sorted(DOSSIER.glob("app_*.arb")):
        if fichier.name == REFERENCE:
            continue
        langue = fichier.stem.removeprefix("app_")
        traduits = textes(fichier)
        manquants = sorted(set(reference) - set(traduits))
        en_trop = sorted(set(traduits) - set(reference))
        incoherents = sorted(
            k for k in set(reference) & set(traduits) if variables(reference[k]) != variables(traduits[k])
        )
        ok = not manquants and not incoherents
        lignes.append(
            f"| `{langue}` | {len(traduits)} | {len(manquants)} | {len(en_trop)} | {len(incoherents)} | {'✅' if ok else '❌'} |"
        )
        if manquants:
            erreurs.append(f"**{langue}** — textes manquants : " + ", ".join(f"`{k}`" for k in manquants[:30]))
        if incoherents:
            erreurs.append(f"**{langue}** — variables différentes du français : " + ", ".join(f"`{k}`" for k in incoherents[:30]))
        if en_trop:
            erreurs.append(f"**{langue}** — ⚠️ textes absents du français (sans effet, à nettoyer) : " + ", ".join(f"`{k}`" for k in en_trop[:30]))

    if erreurs:
        lignes += ["", *[f"- {e}" for e in erreurs]]

    resume = "\n".join(lignes) + "\n"
    print(resume)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as f:
            f.write(resume)

    bloquant = any("manquants" in e or "variables différentes" in e for e in erreurs)
    return 1 if bloquant else 0


if __name__ == "__main__":
    sys.exit(main())
