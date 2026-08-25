import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/notification/presentation/cubit/notifications_cubit.dart';
import '../../l10n/l10n_extension.dart';
import '../routes/app_router.dart';
import '../theme/app_colors.dart';

/// Chrome commun aux écrans de liste de premier niveau (Réserves, Plans).
///
/// Les deux pages partagent exactement la même armature — en-tête, recherche,
/// filtres, état vide illustré, bouton d'action — et ne diffèrent que par leur
/// contenu (icône, titre, texte, action). Regrouper ces pièces ici est ce qui
/// garantit qu'elles restent jumelles : une retouche de style se fait à un
/// seul endroit, au lieu d'être recopiée dans chaque page avec le risque
/// qu'elles divergent au fil des retouches.

/// Largeur au-delà de laquelle le contenu cesse de s'étirer et se centre.
/// Sur une tablette, une barre de recherche de 1000 px de large et un état
/// vide perdu au milieu d'un grand vide ne servent personne.
const double largeurContenuMax = 560;

/// Même plafond, version TABLETTE.
///
/// 560 dp est calibré pour un téléphone : sur une tablette, il laisserait la
/// liste en colonne étroite au milieu de deux grandes bandes vides, alors que
/// les cartes de réserve, de plan et de membre portent justement de quoi
/// remplir la largeur (référence, statut, responsable, échéance, action). Le
/// plafond reste néanmoins posé : au-delà, les lignes deviennent trop longues
/// pour l'œil.
const double largeurContenuMaxTablette = 1040;

/// Seuil de bascule, aligné sur celui de la coquille (`app_shell.dart`) : les
/// deux décisions — rail latéral et largeur de contenu — décrivent le même
/// basculement d'appareil et doivent donc se déclencher ensemble.
const double _seuilTablette = 700;

/// Plafond applicable à l'appareil courant.
double largeurContenuPour(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= _seuilTablette
        ? largeurContenuMaxTablette
        : largeurContenuMax;

/// Contraint le contenu à [largeurContenuMax] et le centre au-delà.
class ContenuCentre extends StatelessWidget {
  final Widget child;
  const ContenuCentre({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: largeurContenuPour(context)),
        child: child,
      ),
    );
  }
}

/// Largeur au-delà de laquelle un FORMULAIRE cesse de s'étirer.
///
/// Plus étroite que [largeurContenuMax] : une liste de cartes profite de la
/// largeur supplémentaire d'une tablette, un formulaire non — des champs de
/// saisie de 900 px de large sont pénibles à lire et à remplir. La valeur
/// s'aligne sur `largeurCompacte` d'[AuthMesures] (auth_chrome.dart), pour que
/// tous les formulaires de l'app partagent la même largeur de référence.
const double largeurFormulaireMax = 440;

/// Contraint un formulaire (page entière ou feuille modale) à
/// [largeurFormulaireMax] et le centre au-delà.
///
/// À utiliser pour tout écran ou toute feuille dont le contenu principal est
/// une saisie : mots de passe, code MFA, assistant de création, formulaires
/// d'ajout. Les listes et fiches de consultation utilisent [ContenuCentre].
class ContenuFormulaire extends StatelessWidget {
  final Widget child;
  const ContenuFormulaire({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: largeurFormulaireMax),
        child: child,
      ),
    );
  }
}

/// Nombre de colonnes d'une grille, d'après la largeur disponible.
///
/// À utiliser dans un [LayoutBuilder] pour remplacer un
/// `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: N)` figé : sur
/// téléphone étroit, [min] colonnes ; sur tablette, la grille en ajoute
/// jusqu'à [max] plutôt que d'afficher [min] vignettes démesurément grandes.
///
/// [largeurCible] est la largeur qu'une vignette devrait viser — le nombre de
/// colonnes est celui qui s'en rapproche le plus sans jamais descendre
/// au-dessous de [min] ni dépasser [max].
int colonnesAdaptatives(
  double largeurDisponible, {
  int min = 2,
  int max = 5,
  double largeurCible = 160,
}) {
  final colonnes = (largeurDisponible / largeurCible).floor();
  return colonnes.clamp(min, max);
}

// ─────────────────────────────────────────────────────────────────────────────
//  EN-TÊTE
// ─────────────────────────────────────────────────────────────────────────────

/// En-tête d'écran de liste — titre en gros et accès aux notifications.
///
/// Volontairement PAS une `AppBar` : la maquette demande un titre de 27 px
/// aligné à gauche, bien plus haut que la hauteur d'une barre Material, et
/// aucune des mécaniques d'`AppBar` (élévation au défilement, centrage
/// automatique du titre) n'est souhaitée ici.
class EnTeteListe extends StatelessWidget {
  final String titre;

  /// Affiche une flèche de retour — pour les sous-écrans ouverts depuis un
  /// chantier, qui ne sont pas des onglets de la barre du bas.
  final bool avecRetour;

  /// Affiche la cloche.
  ///
  /// À mettre à `false` dans DEUX cas :
  ///  - sur l'écran Notifications lui-même — un raccourci vers la page où
  ///    l'on se trouve déjà n'a pas de sens ;
  ///  - sur tout écran ouvert HORS de la coquille applicative (réserves et
  ///    plans d'un chantier, détail…). Le [NotificationsCubit] est fourni par
  ///    `AppShell` et par lui seul : la cloche y chercherait un fournisseur
  ///    absent et ferait planter l'écran à l'ouverture.
  final bool avecCloche;

  /// Contrôle posé à droite du titre, À LA PLACE de la cloche.
  ///
  /// Sert aux écrans qui ont leur propre action de tête — la croix de
  /// fermeture d'un assistant, par exemple. Fournir [action] rend [avecCloche]
  /// sans effet : les deux occuperaient la même position.
  final Widget? action;

  const EnTeteListe({
    super.key,
    required this.titre,
    this.avecRetour = false,
    this.avecCloche = true,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Row(
        children: [
          if (avecRetour)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: context.l10n.commonBack,
              ),
            ),
          Expanded(
            child: Text(
              titre,
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null) action! else if (avecCloche) const BoutonCloche(),
        ],
      ),
    );
  }
}

/// Cloche de notifications, avec le nombre de messages non lus.
///
/// Le compteur vient du serveur (`GET /notifications/non-lues/count`) via le
/// [NotificationsCubit] fourni une fois pour toutes par la coquille
/// applicative. Aucune pastille tant qu'il n'y a rien à lire : un point rouge
/// permanent perdrait tout pouvoir d'alerte.
class BoutonCloche extends StatelessWidget {
  const BoutonCloche({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (a, b) => a.nonLues != b.nonLues,
      builder: (context, state) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () => context.go(AppRoutes.notifications),
              icon: const Icon(Icons.notifications_none_rounded, size: 26, color: AppColors.textPrimary),
              tooltip: context.l10n.navNotifications,
            ),
            if (state.nonLues > 0)
              Positioned(
                top: 6,
                right: 4,
                child: IgnorePointer(child: PastilleCompteur(nombre: state.nonLues)),
              ),
          ],
        );
      },
    );
  }
}

/// Pastille de comptage — partagée par la cloche de l'en-tête de liste et
/// celle du tableau de bord, pour qu'elles restent identiques.
class PastilleCompteur extends StatelessWidget {
  final int nombre;

  /// Couleur du liseré, à accorder au fond sur lequel la pastille est posée.
  final Color couleurBordure;

  const PastilleCompteur({super.key, required this.nombre, this.couleurBordure = Colors.white});

  /// Diamètre d'une pastille à un chiffre.
  static const double _diametre = 18;

  @override
  Widget build(BuildContext context) {
    // Au-delà de 99, le nombre exact n'apporte plus rien et ferait éclater la
    // pastille.
    final texte = nombre > 99 ? '99+' : '$nombre';

    // Taille EXPLICITE, et non des contraintes minimales : la pastille est
    // posée dans un `Positioned` qui ne borne pas ses enfants, et un
    // `Container` aligné s'étire alors jusqu'à remplir tout le `Stack`. En
    // fixant la largeur au nombre de caractères, elle reste un disque quel que
    // soit son parent.
    final largeur = _diametre + (texte.length - 1) * 7.0;

    return Container(
      width: largeur,
      height: _diametre,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(_diametre / 2),
        border: Border.all(color: couleurBordure, width: 1.6),
      ),
      child: Text(
        texte,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RECHERCHE ET FILTRES
// ─────────────────────────────────────────────────────────────────────────────

class ChampRecherche extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const ChampRecherche({super.key, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 15, color: AppColors.textMuted, fontWeight: FontWeight.w400),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 6, right: 2),
            child: Icon(Icons.search_rounded, size: 22, color: AppColors.textMuted),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          filled: true,
          fillColor: AppColors.background,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Puce de filtre — pilule à icône. Actif : aplat orange. Inactif : blanc
/// cerclé, pour se détacher du fond blanc de la page.
class ChipFiltre extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool actif;
  final VoidCallback onTap;

  const ChipFiltre({
    super.key,
    required this.icon,
    required this.label,
    required this.actif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(13, 9, 15, 9),
        decoration: BoxDecoration(
          color: actif ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: actif ? AppColors.primary : AppColors.border, width: 1.2),
          boxShadow: actif
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: actif ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: actif ? FontWeight.w700 : FontWeight.w600,
                color: actif ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ÉTAT VIDE ILLUSTRÉ
// ─────────────────────────────────────────────────────────────────────────────

/// Sujet dessiné au centre de l'état vide.
enum MotifVide { reserve, plan, notification, recherche, chantier, document, equipe, intervenant, synchronisation }

/// État vide de la maquette : illustration, titre, explication, action.
///
/// Défilable (`ListView`) et non centré en dur : sur un petit téléphone en
/// paysage, ou clavier ouvert, un `Center` rigide tronquerait l'illustration
/// et rendrait le bouton inatteignable.
class EtatVideIllustre extends StatelessWidget {
  final MotifVide motif;
  final String titre;
  final String description;

  /// Bouton d'action principal. Absent quand aucune action n'a de sens —
  /// typiquement une recherche sans résultat.
  final Widget? cta;

  const EtatVideIllustre({
    super.key,
    required this.motif,
    required this.titre,
    required this.description,
    this.cta,
  });

  @override
  Widget build(BuildContext context) {
    return ContenuCentre(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
        children: [
          const SizedBox(height: 12),
          Center(child: IllustrationVide(motif: motif)),
          const SizedBox(height: 26),
          Text(
            titre,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (cta != null) ...[
            const SizedBox(height: 30),
            cta!,
          ],
        ],
      ),
    );
  }
}

/// Bouton d'action principal de l'état vide — pleine largeur, orange.
class BoutonAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Remplace l'icône par un indicateur d'activité et neutralise le bouton.
  final bool enCours;

  const BoutonAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enCours = false,
  });

  @override
  Widget build(BuildContext context) {
    final actif = onTap != null && !enCours;

    return Opacity(
      opacity: actif ? 1 : 0.6,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: actif ? onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryLight, AppColors.primary],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.38),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (enCours)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  else
                    Icon(icon, color: Colors.white, size: 21),
                  const SizedBox(width: 11),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ILLUSTRATION
// ─────────────────────────────────────────────────────────────────────────────

/// Illustration de l'état vide — dessinée au [CustomPainter] plutôt
/// qu'importée en image : elle suit ainsi la couleur de marque définie dans
/// [AppColors], reste nette à toute densité d'écran et n'ajoute aucun octet
/// au paquet de l'application.
class IllustrationVide extends StatelessWidget {
  final MotifVide motif;
  const IllustrationVide({super.key, required this.motif});

  static const Size _taille = Size(230, 200);

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: _taille,
      child: CustomPaint(
        painter: _PeintreIllustration(motif: motif),
        // Décor purement visuel : les lecteurs d'écran doivent l'ignorer et
        // s'en tenir au titre et à la description qui la suivent.
        isComplex: true,
      ),
    );
  }
}

class _PeintreIllustration extends CustomPainter {
  final MotifVide motif;
  _PeintreIllustration({required this.motif});

  @override
  void paint(Canvas canvas, Size size) {
    _halo(canvas, size);
    _nuages(canvas);
    _arcPointille(canvas);
    _etincelles(canvas);

    switch (motif) {
      case MotifVide.reserve:
        _pressePapier(canvas);
      case MotifVide.plan:
        _carte(canvas);
      case MotifVide.notification:
        _cloche(canvas);
      case MotifVide.recherche:
        _loupe(canvas);
      case MotifVide.chantier:
        _grue(canvas);
      case MotifVide.document:
        _dossier(canvas);
      case MotifVide.equipe:
        _equipe(canvas);
      case MotifVide.intervenant:
        _poigneeDeMain(canvas);
      case MotifVide.synchronisation:
        _nuageSynchro(canvas);
    }
  }

  /// Disque pêche qui pose le sujet — deux passes pour que le bord s'éteigne
  /// en douceur au lieu de trancher.
  void _halo(Canvas canvas, Size size) {
    const centre = Offset(115, 96);
    canvas.drawCircle(centre, 84, Paint()..color = AppColors.primary100.withValues(alpha: 0.45));
    canvas.drawCircle(centre, 70, Paint()..color = AppColors.primary100);
  }

  /// Deux nuages très pâles qui ancrent le sujet au lieu de le laisser
  /// flotter dans le vide.
  void _nuages(Canvas canvas) {
    final peinture = Paint()..color = AppColors.primary100.withValues(alpha: 0.75);
    for (final (cx, cy, r) in [(48.0, 138.0, 15.0), (62.0, 142.0, 11.0), (176.0, 130.0, 13.0), (163.0, 135.0, 9.0)]) {
      canvas.drawCircle(Offset(cx, cy), r, peinture);
    }
  }

  /// Étincelles à quatre branches, façon éclat.
  void _etincelles(Canvas canvas) {
    final peinture = Paint()..color = AppColors.primary200;
    for (final (cx, cy, r) in [(40.0, 62.0, 8.0), (196.0, 52.0, 10.0), (32.0, 104.0, 5.5), (204.0, 100.0, 6.0)]) {
      canvas.drawPath(_etoile(Offset(cx, cy), r), peinture);
    }
  }

  Path _etoile(Offset c, double r) {
    final creux = r * 0.2;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + creux, c.dy - creux, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + creux, c.dy + creux, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - creux, c.dy + creux, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - creux, c.dy - creux, c.dx, c.dy - r)
      ..close();
  }

  /// Trajectoire pointillée sous le sujet, terminée par une pointe de flèche.
  void _arcPointille(Canvas canvas) {
    final trace = Path()
      ..moveTo(46, 172)
      ..quadraticBezierTo(115, 200, 186, 162);

    final peinture = Paint()
      ..color = AppColors.primary200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    for (final segment in trace.computeMetrics()) {
      var distance = 0.0;
      while (distance < segment.length) {
        final fin = math.min(distance + 6, segment.length);
        canvas.drawPath(segment.extractPath(distance, fin), peinture);
        distance = fin + 6;
      }
    }

    // Pointe de flèche à l'extrémité droite, orientée dans le sens du tracé.
    final pointe = Path()
      ..moveTo(186, 162)
      ..lineTo(176, 160)
      ..lineTo(183, 153)
      ..close();
    canvas.drawPath(pointe, Paint()..color = AppColors.primary200);
  }

  Paint get _contour => Paint()
    ..color = AppColors.primary
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6
    ..strokeJoin = StrokeJoin.round;

  Paint get _remplissageBlanc => Paint()..color = Colors.white;

  /// Presse-papiers — le sujet des réserves.
  void _pressePapier(Canvas canvas) {
    final planche = RRect.fromLTRBR(80, 48, 150, 146, const Radius.circular(13));
    canvas.drawRRect(planche, _remplissageBlanc);
    canvas.drawRRect(planche, _contour);

    // Pince
    final pince = RRect.fromLTRBR(101, 38, 129, 58, const Radius.circular(7));
    canvas.drawRRect(pince, Paint()..color = AppColors.primary);
    canvas.drawCircle(const Offset(115, 36), 6, Paint()..color = AppColors.primary);

    // Vignette + deux lignes courtes
    canvas.drawRRect(
      RRect.fromLTRBR(91, 72, 106, 87, const Radius.circular(4)),
      Paint()..color = AppColors.primary,
    );
    final ligne = Paint()..color = AppColors.primary200;
    for (final (x2, y) in [(140.0, 74.0), (132.0, 83.0)]) {
      canvas.drawRRect(
        RRect.fromLTRBR(112, y, x2, y + 5, const Radius.circular(2.5)),
        ligne,
      );
    }
    // Lignes de texte
    for (final (x2, y) in [(139.0, 100.0), (139.0, 112.0), (126.0, 124.0)]) {
      canvas.drawRRect(
        RRect.fromLTRBR(91, y, x2, y + 5, const Radius.circular(2.5)),
        ligne,
      );
    }
  }

  /// Carte pliée surmontée d'une épingle — le sujet des plans.
  void _carte(Canvas canvas) {
    // Trois volets en accordéon : le pli alterne le haut et le bas.
    const xs = [58.0, 96.0, 134.0, 172.0];
    const hauts = [104.0, 88.0, 104.0, 88.0];
    const bas = [152.0, 136.0, 152.0, 136.0];

    final teintes = [AppColors.primary100, Colors.white, AppColors.primary200];
    for (var i = 0; i < 3; i++) {
      final volet = Path()
        ..moveTo(xs[i], hauts[i])
        ..lineTo(xs[i + 1], hauts[i + 1])
        ..lineTo(xs[i + 1], bas[i + 1])
        ..lineTo(xs[i], bas[i])
        ..close();
      canvas.drawPath(volet, Paint()..color = teintes[i]);
      canvas.drawPath(volet, _contour);
    }

    // Épingle : disque + pointe, puis l'œil blanc.
    const centrePin = Offset(150, 68);
    canvas.drawCircle(centrePin, 19, Paint()..color = AppColors.primary);
    final pointe = Path()
      ..moveTo(135, 79)
      ..lineTo(165, 79)
      ..lineTo(150, 102)
      ..close();
    canvas.drawPath(pointe, Paint()..color = AppColors.primary);
    canvas.drawCircle(centrePin, 7, _remplissageBlanc);
  }

  /// Trois silhouettes — le sujet de l'équipe.
  ///
  /// Celle du centre est plus grande et blanche, les deux autres en retrait et
  /// teintées : le groupe se lit d'un coup, avec une profondeur que trois
  /// bonshommes alignés à la même taille n'auraient pas.
  void _equipe(Canvas canvas) {
    void personne(double cx, double baseY, double echelle, Color remplissage, {bool contour = false}) {
      final rayonTete = 15 * echelle;
      final centreTete = Offset(cx, baseY - 54 * echelle);
      final peinture = Paint()..color = remplissage;

      // Buste : demi-disque adouci, posé sous la tête.
      final buste = Path()
        ..moveTo(cx - 26 * echelle, baseY)
        ..quadraticBezierTo(cx - 26 * echelle, baseY - 34 * echelle, cx, baseY - 34 * echelle)
        ..quadraticBezierTo(cx + 26 * echelle, baseY - 34 * echelle, cx + 26 * echelle, baseY)
        ..close();

      canvas.drawPath(buste, peinture);
      canvas.drawCircle(centreTete, rayonTete, peinture);
      if (contour) {
        canvas.drawPath(buste, _contour);
        canvas.drawCircle(centreTete, rayonTete, _contour);
      }
    }

    // Les deux du fond d'abord : le personnage central doit les recouvrir.
    personne(74, 146, 0.80, AppColors.primary200);
    personne(156, 146, 0.80, AppColors.primary200);
    personne(115, 152, 1.0, Colors.white, contour: true);

    // Casque du personnage central — c'est lui qui dit « chantier » plutôt
    // que « contacts ».
    final casque = Path()
      ..moveTo(94, 100)
      ..quadraticBezierTo(94, 76, 115, 76)
      ..quadraticBezierTo(136, 76, 136, 100)
      ..close();
    canvas.drawPath(casque, Paint()..color = AppColors.primary);
    canvas.drawRRect(
      RRect.fromLTRBR(88, 98, 142, 106, const Radius.circular(4)),
      Paint()..color = AppColors.primary,
    );
  }

  /// Poignée de main — le sujet des intervenants.
  ///
  /// Deux manches qui se rejoignent : le geste dit « partenaire extérieur »,
  /// là où les silhouettes de [_equipe] disent « les nôtres ».
  void _poigneeDeMain(Canvas canvas) {
    // Manches, l'une claire l'autre teintée, pour qu'on distingue les deux
    // parties de la poignée.
    for (final (depart, arrivee, teinte) in [
      (const Offset(52, 132), const Offset(104, 106), AppColors.primary200),
      (const Offset(178, 132), const Offset(126, 106), AppColors.primary100),
    ]) {
      final manche = Path()
        ..moveTo(depart.dx, depart.dy)
        ..lineTo(depart.dx + (arrivee.dx - depart.dx), arrivee.dy)
        ..lineTo(depart.dx + (arrivee.dx - depart.dx), arrivee.dy + 22)
        ..lineTo(depart.dx, depart.dy + 22)
        ..close();
      canvas.drawPath(manche, Paint()..color = teinte);
      canvas.drawPath(manche, _contour);
    }

    // Mains jointes au centre : un bloc blanc cerclé, plus lisible que deux
    // mains détaillées à cette taille.
    final jointure = RRect.fromLTRBR(92, 98, 138, 136, const Radius.circular(12));
    canvas.drawRRect(jointure, _remplissageBlanc);
    canvas.drawRRect(jointure, _contour);

    // Trois plis qui suggèrent les doigts.
    final pli = Paint()
      ..color = AppColors.primary200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (final y in [110.0, 118.0, 126.0]) {
      canvas.drawLine(Offset(102, y), Offset(128, y), pli);
    }
  }

  /// Nuage coché — le sujet de la synchronisation terminée.
  void _nuageSynchro(Canvas canvas) {
    // Nuage : trois bosses posées sur une base droite.
    final nuage = Path()
      ..moveTo(70, 132)
      ..quadraticBezierTo(52, 132, 52, 114)
      ..quadraticBezierTo(52, 98, 70, 96)
      ..quadraticBezierTo(74, 72, 100, 72)
      ..quadraticBezierTo(122, 72, 128, 90)
      ..quadraticBezierTo(154, 88, 158, 108)
      ..quadraticBezierTo(172, 112, 172, 122)
      ..quadraticBezierTo(172, 132, 158, 132)
      ..close();
    canvas.drawPath(nuage, _remplissageBlanc);
    canvas.drawPath(nuage, _contour);

    // Pastille de validation en bas à droite — le « c'est fait » de l'écran.
    const centreCoche = Offset(150, 138);
    canvas.drawCircle(centreCoche, 22, Paint()..color = AppColors.primary);
    canvas.drawCircle(centreCoche, 22, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);

    final coche = Path()
      ..moveTo(140, 138)
      ..lineTo(147, 146)
      ..lineTo(161, 130);
    canvas.drawPath(coche, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  /// Grue et bâtiment en construction — le sujet des chantiers.
  void _grue(Canvas canvas) {
    // Bâtiment : deux volumes de hauteurs différentes, pour que la silhouette
    // se lise comme un chantier et non comme une simple boîte.
    final basse = RRect.fromLTRBR(74, 104, 112, 150, const Radius.circular(6));
    canvas.drawRRect(basse, Paint()..color = AppColors.primary100);
    canvas.drawRRect(basse, _contour);

    final haute = RRect.fromLTRBR(112, 78, 150, 150, const Radius.circular(6));
    canvas.drawRRect(haute, _remplissageBlanc);
    canvas.drawRRect(haute, _contour);

    // Fenêtres — deux colonnes régulières, la trame qui dit « immeuble ».
    final fenetre = Paint()..color = AppColors.primary200;
    for (final y in [92.0, 110.0, 128.0]) {
      for (final x in [120.0, 134.0]) {
        canvas.drawRRect(
          RRect.fromLTRBR(x, y, x + 9, y + 10, const Radius.circular(2)),
          fenetre,
        );
      }
    }
    for (final y in [116.0, 132.0]) {
      canvas.drawRRect(
        RRect.fromLTRBR(84, y, 93, y + 10, const Radius.circular(2)),
        fenetre,
      );
    }

    // Grue : mât, flèche et câble. Tracée par-dessus le bâtiment, elle donne
    // la hauteur et signe le chantier « en cours ».
    final mat = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(158, 46), const Offset(158, 150), mat);
    canvas.drawLine(const Offset(120, 46), const Offset(178, 46), mat);
    canvas.drawLine(const Offset(132, 60), const Offset(132, 46), mat);

    // Crochet suspendu au bout de la flèche.
    canvas.drawRRect(
      RRect.fromLTRBR(126, 60, 138, 70, const Radius.circular(3)),
      Paint()..color = AppColors.primary,
    );
  }

  /// Chemise contenant deux feuilles — le sujet des documents.
  void _dossier(Canvas canvas) {
    // Feuilles décalées derrière la chemise : le décalage suffit à dire
    // « plusieurs fichiers » sans les dessiner tous.
    for (final (dx, teinte) in [(10.0, AppColors.primary200), (0.0, Colors.white)]) {
      final feuille = RRect.fromLTRBR(88 + dx, 54, 148 + dx, 122, const Radius.circular(6));
      canvas.drawRRect(feuille, Paint()..color = teinte);
      canvas.drawRRect(feuille, _contour);
    }

    // Lignes de texte sur la feuille du dessus.
    final ligne = Paint()..color = AppColors.primary200;
    for (final (x2, y) in [(138.0, 68.0), (138.0, 80.0), (126.0, 92.0)]) {
      canvas.drawRRect(RRect.fromLTRBR(98, y, x2, y + 5, const Radius.circular(2.5)), ligne);
    }

    // Chemise au premier plan : languette puis corps, comme un dossier ouvert
    // dont les feuilles dépassent.
    final chemise = Path()
      ..moveTo(66, 108)
      ..lineTo(66, 100)
      ..quadraticBezierTo(66, 96, 70, 96)
      ..lineTo(92, 96)
      ..lineTo(100, 104)
      ..lineTo(160, 104)
      ..quadraticBezierTo(164, 104, 164, 108)
      ..lineTo(164, 148)
      ..quadraticBezierTo(164, 152, 160, 152)
      ..lineTo(70, 152)
      ..quadraticBezierTo(66, 152, 66, 148)
      ..close();
    canvas.drawPath(chemise, Paint()..color = AppColors.primary100);
    canvas.drawPath(chemise, _contour);
  }

  /// Cloche — le sujet des notifications.
  void _cloche(Canvas canvas) {
    // Corps de la cloche : deux courbes qui s'évasent depuis la calotte.
    final corps = Path()
      ..moveTo(84, 128)
      ..lineTo(146, 128)
      ..quadraticBezierTo(138, 118, 137, 100)
      ..lineTo(137, 88)
      ..cubicTo(137, 70, 126, 58, 115, 58)
      ..cubicTo(104, 58, 93, 70, 93, 88)
      ..lineTo(93, 100)
      ..quadraticBezierTo(92, 118, 84, 128)
      ..close();
    canvas.drawPath(corps, _remplissageBlanc);
    canvas.drawPath(corps, _contour);

    // Anse et battant.
    canvas.drawCircle(const Offset(115, 51), 7, Paint()..color = AppColors.primary);
    final battant = Path()
      ..moveTo(104, 134)
      ..quadraticBezierTo(115, 146, 126, 134)
      ..close();
    canvas.drawPath(battant, Paint()..color = AppColors.primary);

    // Ondes de part et d'autre : c'est ce qui fait « sonner » la cloche
    // plutôt que de la laisser inerte.
    final onde = Paint()
      ..color = AppColors.primary200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final rayon in [16.0, 27.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(70, 92), radius: rayon),
        2.5, 1.3, false, onde,
      );
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(160, 92), radius: rayon),
        -0.65, 1.3, false, onde,
      );
    }

    // Pastille « non lu », clin d'œil au badge de la cloche de l'en-tête.
    canvas.drawCircle(const Offset(141, 66), 10, Paint()..color = AppColors.danger);
    canvas.drawCircle(const Offset(141, 66), 10, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
  }

  /// Loupe — utilisée quand une recherche ou un filtre ne donne rien.
  void _loupe(Canvas canvas) {
    const centre = Offset(106, 88);
    canvas.drawCircle(centre, 34, _remplissageBlanc);
    canvas.drawCircle(centre, 34, _contour);

    final manche = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(131, 113), const Offset(152, 134), manche);

    final ligne = Paint()..color = AppColors.primary200;
    for (final (x1, x2, y) in [(90.0, 122.0, 80.0), (90.0, 114.0, 91.0)]) {
      canvas.drawRRect(
        RRect.fromLTRBR(x1, y, x2, y + 5, const Radius.circular(2.5)),
        ligne,
      );
    }
  }

  @override
  bool shouldRepaint(_PeintreIllustration ancien) => ancien.motif != motif;
}
