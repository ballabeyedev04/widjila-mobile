import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../injection_container.dart';
import '../../domain/entities/plan.dart';

/// Aperçu d'un plan — la PREMIÈRE PAGE du document, et non une icône générique.
///
/// Une carte qui n'affiche qu'un pictogramme oblige à ouvrir chaque plan pour
/// savoir lequel on regarde. Sur un chantier qui compte trente plans
/// d'appartements presque homonymes (« A201 », « A202 »…), c'est la différence
/// entre reconnaître un plan d'un coup d'œil et les ouvrir un par un.
///
/// ── Trois précautions, dans cet ordre d'importance ──────────────────────────
///
/// 1. CACHE DE SESSION. Le rendu est conservé en mémoire, indexé par fichier.
///    Faire défiler une liste puis revenir dessus ne retélécharge rien — c'est
///    ce qui rend l'aperçu tenable sur une connexion de chantier.
///
/// 2. UN SEUL RENDU EN VOL par fichier. Deux cartes du même plan (liste + vue
///    mise en avant) partagent la même requête au lieu d'en lancer deux.
///
/// 3. REPLI SILENCIEUX. Fichier illisible, format DWG/IFC sans visionneuse,
///    réseau coupé : l'icône reste affichée. Un aperçu est un confort, son
///    absence ne doit jamais masquer la carte.
///
/// Contrairement au web, il n'y a PAS de rendu différé au défilement : une
/// liste mobile n'affiche que quelques cartes à la fois, et `ListView` ne
/// construit de toute façon que les éléments visibles.
class PlanVignette extends StatefulWidget {
  final Plan plan;

  /// Icône affichée tant que l'aperçu n'est pas disponible.
  final IconData icone;

  /// Couleur de l'icône et du fond de repli.
  final Color couleur;

  final double taille;

  /// Largeur, quand l'apercu n'est pas carre. `null` = aussi large que haut.
  ///
  /// Une bande horizontale (carrousel du tableau de bord) a besoin d'un
  /// bandeau plus large que haut ; les listes verticales gardent le carre.
  final double? largeur;

  final double rayon;

  const PlanVignette({
    super.key,
    required this.plan,
    required this.icone,
    required this.couleur,
    this.taille = 52,
    this.largeur,
    this.rayon = 16,
  });

  @override
  State<PlanVignette> createState() => _PlanVignetteState();
}

/// Aperçus déjà produits, indexés par chemin de fichier.
///
/// On retient l'image encodée (quelques dizaines de kilo-octets) et non le PDF
/// (plusieurs mégaoctets), et surtout on évite de refaire le rendu natif. Le
/// plafond empêche qu'une longue session finisse par retenir tous les plans de
/// l'organisation.
final Map<String, Uint8List> _cache = <String, Uint8List>{};

/// Rendus en cours, pour qu'une même carte affichée deux fois ne déclenche
/// qu'un seul téléchargement.
final Map<String, Future<Uint8List?>> _enVol = <String, Future<Uint8List?>>{};

const int _cacheMax = 40;

void _memoriser(String cle, Uint8List octets) {
  if (_cache.length >= _cacheMax) {
    // Éviction de la plus ancienne entrée : une vignette perdue se reconstruit
    // toute seule au prochain affichage, une politique LRU complète
    // n'apporterait rien ici.
    _cache.remove(_cache.keys.first);
  }
  _cache[cle] = octets;
}

/// Télécharge le plan et rend sa première page en image.
///
/// Ce fichier est-il un PDF ?
///
/// Les cinq premiers octets d'un PDF sont `%PDF-`. On ne se fie pas à
/// l'extension ni au champ `format` : le premier peut mentir, le second vaut
/// 'pdf' par défaut pour tout ce qui est déposé sans précision.
bool _estPdf(Uint8List octets) {
  const entete = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
  if (octets.length < entete.length) return false;
  for (var i = 0; i < entete.length; i++) {
    if (octets[i] != entete[i]) return false;
  }
  return true;
}

/// Renvoie `null` — jamais une exception — quand le rendu est impossible :
/// l'appelant retombe alors sur son icône.
Future<Uint8List?> _rendrePremierePage(Plan plan) async {
  final cle = plan.fichierUrl;
  if (cle.isEmpty) return null;

  final dejaLa = _cache[cle];
  if (dejaLa != null) return dejaLa;

  final enCours = _enVol[cle];
  if (enCours != null) return enCours;

  final future = () async {
    PdfDocument? document;
    try {
      // Les octets transitent par le Dio de l'application, qui porte le jeton
      // exigé par `/uploads/*` — un lien direct répondrait 401.
      final reponse = await sl<Dio>().get<List<int>>(
        cle,
        options: Options(responseType: ResponseType.bytes),
      );
      final donnees = reponse.data;
      if (donnees == null || donnees.isEmpty) return null;
      final octets = Uint8List.fromList(donnees);

      // Une IMAGE est déjà son propre aperçu : rien à rasteriser, on rend les
      // octets tels quels.
      //
      // La décision se prend sur les OCTETS, pas sur `plan.format`. Ce champ
      // vaut 'pdf' pour tout plan déposé sans format explicite — c'est le
      // défaut du serveur — alors que le dépôt accepte png, jpg, jpeg et webp.
      // Un plan photographié depuis le chantier arrivait donc étiqueté « PDF »,
      // `PdfDocument.openData` échouait sur ses octets, et l'application
      // affichait une icône générique à la place du plan. Le client l'a
      // signalé ainsi : « on ne voit pas réellement l'image du plan ».
      //
      // Lire l'en-tête corrige aussi les plans DÉJÀ EN BASE, que rien ne
      // viendra ré-étiqueter.
      if (!_estPdf(octets)) {
        _memoriser(cle, octets);
        return octets;
      }

      document = await PdfDocument.openData(octets);
      final page = await document.getPage(1);
      try {
        // Largeur cible fixe plutôt qu'une échelle fixe : un plan A0 et un plan
        // A4 donneraient sinon des vignettes de poids très différents, la
        // première pesant plusieurs mégaoctets pour être réduite à 52 points.
        const largeurCible = 320.0;
        final echelle = largeurCible / page.width;
        final rendu = await page.render(
          width: largeurCible,
          height: page.height * echelle,
          format: PdfPageImageFormat.jpeg,
          // Fond blanc explicite : un PDF sans calque de fond serait rendu en
          // traits noirs sur du transparent, illisible sur une carte claire.
          backgroundColor: '#FFFFFF',
        );
        final image = rendu?.bytes;
        if (image == null || image.isEmpty) return null;
        _memoriser(cle, image);
        return image;
      } finally {
        await page.close();
      }
    } catch (_) {
      // Aperçu indisponible — l'appelant garde son icône.
      return null;
    } finally {
      await document?.close();
      _enVol.remove(cle);
    }
  }();

  _enVol[cle] = future;
  return future;
}

class _PlanVignetteState extends State<PlanVignette> {
  Uint8List? _apercu;

  /// Vrai tant que le rendu est EN COURS.
  ///
  /// Sans cet état, chargement et échec se ressemblaient trait pour trait :
  /// la même icône générique, sans rien qui dise s'il faut attendre ou si le
  /// plan n'aura jamais d'aperçu. Devant une bande de huit cartes, on ne
  /// pouvait que patienter au cas où.
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    // Le cache est consulté DÈS le premier rendu : une vignette déjà connue
    // s'affiche sans le moindre clignotement d'icône.
    _apercu = _cache[widget.plan.fichierUrl];
    if (_apercu == null) _charger();
  }

  @override
  void didUpdateWidget(PlanVignette ancien) {
    super.didUpdateWidget(ancien);
    // Le recyclage d'une tuile de liste doit repartir du cache pour CE
    // fichier, sans conserver l'aperçu du plan précédent.
    if (ancien.plan.fichierUrl != widget.plan.fichierUrl) {
      _apercu = _cache[widget.plan.fichierUrl];
      if (_apercu == null) _charger();
    }
  }

  Future<void> _charger() async {
    // Affectation DIRECTE, sans `setState` : `_charger` est appelée depuis
    // `initState` et depuis `didUpdateWidget`, deux moments où une
    // reconstruction suit de toute façon — et où `setState` lèverait.
    _enCours = true;
    final image = await _rendrePremierePage(widget.plan);
    if (!mounted) return;
    // `_enCours` retombe DANS TOUS LES CAS, y compris à l'échec : c'est ce qui
    // fait passer la carte de « ça arrive » à « il n'y a pas d'aperçu ».
    setState(() {
      _enCours = false;
      if (image != null) _apercu = image;
    });
  }

  @override
  Widget build(BuildContext context) {
    final apercu = _apercu;

    return Container(
      width: widget.largeur ?? widget.taille,
      height: widget.taille,
      decoration: BoxDecoration(
        color: widget.couleur.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(widget.rayon),
      ),
      clipBehavior: Clip.antiAlias,
      child: apercu == null
          ? (_enCours
              // CHARGEMENT : un fin indicateur, à l'échelle de la vignette —
              // un anneau de taille normale déborderait d'une pastille de 40.
              ? Center(
                  child: SizedBox(
                    width: widget.taille * 0.3,
                    height: widget.taille * 0.3,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.couleur.withValues(alpha: 0.6),
                    ),
                  ),
                )
              // APERÇU INDISPONIBLE : format sans visionneuse, fichier
              // illisible, réseau coupé. L'icône reste — une carte sans
              // aperçu vaut mieux qu'une carte manquante.
              : Icon(widget.icone, color: widget.couleur, size: widget.taille * 0.48))
          : Image.memory(
              apercu,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // Un décodage raté ne doit pas faire tomber la liste : on
              // retombe sur l'icône, comme pour un fichier illisible.
              errorBuilder: (_, _, _) =>
                  Icon(widget.icone, color: widget.couleur, size: widget.taille * 0.48),
            ),
    );
  }
}
