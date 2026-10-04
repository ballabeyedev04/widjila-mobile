#!/usr/bin/env python3
"""Contrôle de l'IPA avant tout envoi à Apple.

Ouvre l'IPA (une archive ZIP), lit l'Info.plist de l'app, son profil
d'approvisionnement embarqué et son code compilé, compare le tout à
tool/ci/ios_reference.json, puis écrit un rapport Markdown dans
$GITHUB_STEP_SUMMARY.

Fait exprès sans outil Apple : le même contrôle tourne sur n'importe quelle
machine, et un IPA archivé il y a six mois reste vérifiable.

BLOQUANT (code de sortie 1) :
  - identité : bundle, numéro de build ou version différents de l'attendu ;
  - profil de DÉVELOPPEMENT ou AD HOC au lieu d'App Store (appareils listés,
    débogage autorisé) — Apple le refuserait après la compilation ;
  - profil d'une autre équipe, d'un autre bundle, ou expiré ;
  - app non signée (pas de _CodeSignature) ;
  - version d'iOS minimale inférieure à la référence.

AVERTISSEMENT (le déploiement continue, affiché en tête du rapport) :
  - demande d'autorisation absente de la liste de référence ;
  - profil qui expire bientôt, droits attendus manquants ;
  - taille en hausse anormale ;
  - adresse de l'API ou configuration Firebase non retrouvées ;
  - ITSAppUsesNonExemptEncryption absent (Apple poserait la question du
    chiffrement à chaque envoi).
"""

import argparse
import json
import os
import plistlib
import posixpath
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path


def taille_lisible(octets: int) -> str:
    return f"{octets / 1024 / 1024:.1f} Mo"


def version_tuple(valeur: str) -> tuple:
    return tuple(int(x) for x in re.findall(r"\d+", str(valeur)) or [0])


def dossier_app(archive: zipfile.ZipFile) -> str:
    """`Payload/Runner.app` — trouvé plutôt que supposé : le nom du bundle
    suit le nom du schéma Xcode, qui peut changer."""
    dossiers = {
        posixpath.dirname(n)
        for n in archive.namelist()
        if posixpath.dirname(n).startswith("Payload/") and posixpath.dirname(n).endswith(".app")
    }
    if not dossiers:
        raise SystemExit("::error::Aucun bundle .app dans Payload/ : ce fichier n'est pas un IPA valide.")
    if len(dossiers) > 1:
        raise SystemExit(f"::error::Plusieurs bundles .app dans Payload/ : {', '.join(sorted(dossiers))}")
    return dossiers.pop()


def profil_embarque(octets: bytes) -> dict:
    """Le .mobileprovision est un plist enveloppé dans une signature CMS :
    on en extrait la partie plist, ce qui évite d'avoir besoin de `security`
    (donc d'un Mac) pour lire le profil."""
    debut = octets.find(b"<?xml")
    fin = octets.find(b"</plist>")
    if debut == -1 or fin == -1:
        raise ValueError("profil illisible")
    return plistlib.loads(octets[debut:fin + len(b"</plist>")])


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--ipa", required=True)
    p.add_argument("--reference", required=True)
    p.add_argument("--version-code", required=True)
    p.add_argument("--version-name", required=True)
    p.add_argument("--taille-precedente", default="")
    p.add_argument("--autorisations-sortie", required=True)
    a = p.parse_args()

    ref = json.loads(Path(a.reference).read_text(encoding="utf-8"))
    taille = os.path.getsize(a.ipa)

    controles = []  # (libellé, valeur, statut) — statut : ok / alerte / bloque
    alertes = []

    def ajouter(libelle, valeur, statut, alerte=None):
        controles.append((libelle, valeur, statut))
        if alerte:
            alertes.append(alerte)

    with zipfile.ZipFile(a.ipa) as archive:
        app = dossier_app(archive)
        noms = set(archive.namelist())
        info = plistlib.loads(archive.read(f"{app}/Info.plist"))

        profil = None
        erreur_profil = None
        if f"{app}/embedded.mobileprovision" in noms:
            try:
                profil = profil_embarque(archive.read(f"{app}/embedded.mobileprovision"))
            except ValueError as e:
                erreur_profil = str(e)

        signe = any(n.startswith(f"{app}/_CodeSignature/") for n in noms)
        firebase = f"{app}/GoogleService-Info.plist" in noms

        # L'adresse de l'API est dans le code Dart compilé, pas dans l'app
        # native : c'est ce fichier qu'il faut lire.
        api_trouvee = False
        binaire = f"{app}/Frameworks/App.framework/App"
        if binaire in noms:
            api_trouvee = ref["api_attendue"].encode() in archive.read(binaire)

    # ── Identité ────────────────────────────────────────────────────────────
    bundle = info.get("CFBundleIdentifier", "")
    ajouter("Bundle", f"`{bundle}`", "ok" if bundle == ref["bundle_id"] else "bloque")
    build = str(info.get("CFBundleVersion", ""))
    ajouter("Numéro de build", build, "ok" if build == str(a.version_code) else "bloque")
    nom = str(info.get("CFBundleShortVersionString", ""))
    ajouter("Version", nom, "ok" if nom == a.version_name else "bloque")

    # ── Signature et profil ─────────────────────────────────────────────────
    ajouter("Signature", "app signée" if signe else "aucune signature (_CodeSignature absent)",
            "ok" if signe else "bloque")

    if erreur_profil or profil is None:
        ajouter("Profil d'approvisionnement",
                erreur_profil or "embedded.mobileprovision absent de l'IPA", "bloque")
    else:
        nom_profil = profil.get("Name", "?")
        droits = profil.get("Entitlements", {}) or {}
        identifiant = re.sub(r"^[^.]+\.", "", str(droits.get("application-identifier", "")))
        equipes = profil.get("TeamIdentifier", []) or []

        if identifiant != ref["bundle_id"]:
            ajouter("Profil — bundle", f"`{identifiant}` au lieu de `{ref['bundle_id']}`", "bloque")
        elif ref["equipe"] not in equipes:
            ajouter("Profil — équipe", f"`{', '.join(equipes)}` au lieu de `{ref['equipe']}`", "bloque")
        elif profil.get("ProvisionedDevices") is not None:
            ajouter("Profil — type",
                    f"« {nom_profil} » liste {len(profil['ProvisionedDevices'])} appareil(s) : "
                    "profil Développement ou Ad Hoc, pas App Store", "bloque")
        elif droits.get("get-task-allow"):
            ajouter("Profil — type",
                    f"« {nom_profil} » autorise le débogage (get-task-allow) : pas un profil App Store",
                    "bloque")
        else:
            expiration = profil.get("ExpirationDate")
            jours = None
            if isinstance(expiration, datetime):
                reference_temps = datetime.now(timezone.utc) if expiration.tzinfo else datetime.now()
                jours = (expiration - reference_temps).days
            if jours is not None and jours < 0:
                ajouter("Profil d'approvisionnement",
                        f"« {nom_profil} » a expiré il y a {-jours} jour(s)", "bloque")
            elif jours is not None and jours < 30:
                ajouter("Profil d'approvisionnement",
                        f"« {nom_profil} » — App Store, expire dans {jours} jour(s)", "alerte",
                        f"Le profil « {nom_profil} » expire dans {jours} jour(s) : régénérez-le sur developer.apple.com.")
            else:
                suffixe = f", valable {jours} jour(s)" if jours is not None else ""
                ajouter("Profil d'approvisionnement",
                        f"« {nom_profil} » — App Store, équipe `{ref['equipe']}`{suffixe}", "ok")

        for cle, attendu in (ref.get("droits") or {}).items():
            reel = droits.get(cle)
            if str(reel) == str(attendu):
                ajouter(f"Droit `{cle}`", f"`{reel}`", "ok")
            else:
                ajouter(f"Droit `{cle}`", f"`{reel}` au lieu de `{attendu}`", "alerte",
                        f"Le droit `{cle}` vaut `{reel}` au lieu de `{attendu}` : "
                        "les notifications push risquent de ne pas fonctionner dans ce build.")

    # ── Exigences Apple ─────────────────────────────────────────────────────
    minimum = str(info.get("MinimumOSVersion", "0"))
    if version_tuple(minimum) < version_tuple(ref["ios_minimum"]):
        ajouter("iOS minimum", f"{minimum} — référence : {ref['ios_minimum']}", "bloque")
    else:
        ajouter("iOS minimum", f"iOS {minimum}", "ok")

    if "ITSAppUsesNonExemptEncryption" in info:
        ajouter("Déclaration de chiffrement",
                f"`ITSAppUsesNonExemptEncryption = {info['ITSAppUsesNonExemptEncryption']}`", "ok")
    else:
        ajouter("Déclaration de chiffrement", "absente", "alerte",
                "`ITSAppUsesNonExemptEncryption` absent d'Info.plist : App Store Connect posera "
                "la question du chiffrement à chaque envoi, et bloquera la distribution en attendant.")

    # ── Autorisations demandées ─────────────────────────────────────────────
    demandees = sorted(k for k in info if k.endswith("UsageDescription"))
    Path(a.autorisations_sortie).write_text(
        "\n".join(f"{k} = {info[k]}" for k in demandees) + "\n", encoding="utf-8")

    acceptees = set(ref.get("autorisations", []))
    if not acceptees:
        ajouter("Autorisations demandées", f"{len(demandees)} — référence à établir", "alerte",
                "Liste de référence des autorisations vide : à compléter avec celle de ce build (voir plus bas).")
    else:
        nouvelles = [x for x in demandees if x not in acceptees]
        retirees = sorted(acceptees - set(demandees))
        if nouvelles:
            ajouter("Autorisations demandées", f"{len(demandees)} dont {len(nouvelles)} NOUVELLE(S)", "alerte",
                    "Nouvelle(s) autorisation(s) demandée(s) : " + ", ".join(f"`{x}`" for x in nouvelles)
                    + " — Apple refuse une demande dont l'explication ne correspond pas à l'usage réel. "
                      "Vérifiez le texte avant d'approuver.")
        else:
            ajouter("Autorisations demandées", f"{len(demandees)}, toutes connues", "ok")
        if retirees:
            alertes.append("Autorisation(s) retirée(s) depuis la référence : "
                           + ", ".join(f"`{x}`" for x in retirees) + ".")
        # Une explication vide passe la compilation et fait refuser l'app.
        vides = [k for k in demandees if not str(info[k]).strip()]
        if vides:
            ajouter("Explications d'autorisation", f"{len(vides)} vide(s)", "bloque")

    # ── Taille ──────────────────────────────────────────────────────────────
    if a.taille_precedente.isdigit() and int(a.taille_precedente) > 0:
        avant = int(a.taille_precedente)
        ecart = (taille - avant) * 100 / avant
        texte = f"{taille_lisible(taille)} ({ecart:+.1f} % vs {taille_lisible(avant)})"
        if ecart > ref["croissance_taille_alerte_pct"]:
            ajouter("Taille de l'IPA", texte, "alerte",
                    f"L'app grossit de {ecart:.0f} % par rapport au déploiement précédent.")
        else:
            ajouter("Taille de l'IPA", texte, "ok")
    else:
        ajouter("Taille de l'IPA", f"{taille_lisible(taille)} (premier déploiement suivi)", "ok")

    # ── Configuration embarquée ─────────────────────────────────────────────
    if api_trouvee:
        ajouter("Adresse de l'API", f"`{ref['api_attendue']}`", "ok")
    else:
        ajouter("Adresse de l'API", "non retrouvée dans le binaire", "alerte",
                f"L'adresse `{ref['api_attendue']}` n'a pas été retrouvée dans le code compilé.")
    if firebase:
        ajouter("Firebase", "configuration présente", "ok")
    else:
        ajouter("Firebase", "configuration absente", "alerte",
                "GoogleService-Info.plist absent du bundle : notifications push et Crashlytics "
                "inactifs dans ce build.")

    # ── Rapport ─────────────────────────────────────────────────────────────
    icone = {"ok": "✅", "alerte": "⚠️", "bloque": "❌"}
    bloque = any(s == "bloque" for _, _, s in controles)
    lignes = ["### 🔍 Contrôle de l'IPA", ""]
    if bloque:
        lignes += ["> [!CAUTION]", "> **Envoi refusé** : au moins un contrôle bloquant a échoué.", ""]
    if alertes:
        lignes += ["> [!WARNING]", "> **À vérifier avant d'approuver :**"] + [f"> - {x}" for x in alertes] + [""]
    lignes += ["| Contrôle | Résultat | |", "|---|---|:---:|"]
    lignes += [f"| {l} | {v} | {icone[s]} |" for l, v, s in controles]
    lignes += ["", "<details><summary>Autorisations demandées par ce build</summary>", "", "```",
               *(f"{k} = {info[k]}" for k in demandees), "```", "</details>", ""]

    resume = "\n".join(lignes) + "\n"
    print(resume)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as f:
            f.write(resume)
    return 1 if bloque else 0


if __name__ == "__main__":
    sys.exit(main())
