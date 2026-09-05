import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';

/// Habillage visuel commun aux écrans d'authentification publics (connexion,
/// inscription, mot de passe oublié…) : photo de fond, voile dégradé, carte
/// « verre dépoli », logo, champs et bouton sur fond sombre.
///
/// Centralisé ici pour qu'un changement de charte (photo, logo, couleurs) se
/// fasse à un seul endroit — avant ce fichier, `login_page.dart` portait tout
/// ce code en privé et `register_page.dart` avait un style totalement
/// différent (thème clair par défaut, pas de photo), la charte ne se lisait
/// donc que sur la moitié du parcours d'authentification.

/// Chantier au coucher de soleil. Tons chauds (or, ocre) volontairement dans
/// la même famille que l'orange de marque (`AppColors.primary`).
const String authBackgroundImage = 'assets/images/login-hero.jpg';

/// Logo complet de la marque (pictogramme + « WIDJILA »).
const String authLogoImage = 'assets/images/logo-widjila.png';

/// Rouge clair lisible sur fond sombre — `AppColors.danger` (#DC2626) est
/// calibré pour du texte sur fond blanc et devient illisible ici.
const Color authDangerColor = Color(0xFFFFB4AB);

const TextStyle authFieldTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 15,
  fontWeight: FontWeight.w500,
);

/// Validation email commune à tous les écrans d'authentification.
///
/// Remplace l'ancienne règle `^[^\s@]+@[^\s@]+\.[^\s@]+$` — n'importe quelle
/// suite de caractères non-espace de part et d'autre d'un `@` et d'un point
/// (« a@b.c » comme « x@@y..z » d'ailleurs rejeté seulement par coïncidence)
/// passait ce filtre sans broncher. Celle-ci exige une structure réellement
/// valide : partie locale composée des caractères autorisés par la norme
/// email, domaine découpé en étiquettes de 1 à 63 caractères ne commençant ni
/// ne finissant par un tiret — le même motif que celui utilisé par les
/// navigateurs pour `<input type="email">`.
///
/// Elle ne peut PAS (aucune regex ne le peut) détecter qu'un domaine
/// syntaxiquement valide est en réalité une faute de frappe (« gmil.com » au
/// lieu de « gmail.com ») — seule une vérification DNS/MX le pourrait, hors
/// de portée d'une validation côté client.
final RegExp authRegexEmail = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
);

/// Longueur maximale pratique d'une adresse email (RFC 5321).
const int authEmailLongueurMax = 254;

/// Validateur de champ email prêt à l'emploi pour un `TextFormField`.
/// [requis] à `false` pour les champs email optionnels (ex : email de
/// l'organisation à l'inscription).
///
/// Prend `l10n` en premier paramètre (et non `BuildContext`) : les appelants
/// l'ont déjà résolu via `context.l10n` pour construire une fermeture
/// (`(v) => authValidateurEmail(context.l10n, v)`), `TextFormField.validator`
/// n'ayant pas accès au `BuildContext` lui-même.
String? authValidateurEmail(AppLocalizations l10n, String? valeur, {bool requis = true}) {
  final val = (valeur ?? '').trim();
  if (val.isEmpty) return requis ? l10n.authEmailRequis : null;
  if (val.length > authEmailLongueurMax) return l10n.authEmailTropLong;
  return authRegexEmail.hasMatch(val) ? null : l10n.authEmailInvalide;
}

/// Décoration de champ adaptée au fond sombre : le thème global
/// (`AppTheme.inputDecorationTheme`) est calibré pour des écrans clairs —
/// fond blanc et texte ardoise y seraient illisibles sur la photo.
InputDecoration authFieldDecoration({
  required String label,
  required IconData icone,
  Widget? suffixe,
  String? texteAide,
}) {
  OutlineInputBorder bordure(Color couleur, [double epaisseur = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: couleur, width: epaisseur),
      );

  return InputDecoration(
    labelText: label,
    helperText: texteAide,
    helperMaxLines: 2,
    prefixIcon: Icon(icone, size: 20, color: Colors.white.withValues(alpha: 0.70)),
    suffixIcon: suffixe,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.10),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 14.5),
    helperStyle: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 12),
    floatingLabelStyle: const TextStyle(
      color: AppColors.accentLight,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    errorStyle: const TextStyle(color: authDangerColor, fontWeight: FontWeight.w500),
    border: bordure(Colors.white.withValues(alpha: 0.22)),
    enabledBorder: bordure(Colors.white.withValues(alpha: 0.22)),
    focusedBorder: bordure(AppColors.primaryLight, 1.6),
    errorBorder: bordure(authDangerColor),
    focusedErrorBorder: bordure(authDangerColor, 1.6),
  );
}

/// Mesures d'un écran d'authentification, dérivées de la place réellement
/// disponible.
///
/// Tout est calculé à partir des CONTRAINTES du LayoutBuilder (la zone utile
/// sous les encoches et au-dessus du clavier), et non de la taille physique
/// de l'appareil : c'est ce qui fait que la page réagit aussi bien au passage
/// portrait/paysage et à l'ouverture du clavier qu'au changement d'appareil.
///
/// Seule exception, `côtéCourt` (plus petite dimension de l'écran) : il ne
/// change pas avec la rotation, c'est le critère Material pour distinguer une
/// tablette d'un téléphone — une tablette reste une tablette une fois tournée.
///
/// Les largeurs par défaut conviennent à un formulaire court (connexion,
/// mot de passe oublié). Un formulaire plus long (inscription) passe des
/// largeurs plus généreuses via les paramètres `largeurXxx`.
class AuthMesures {
  final bool deuxColonnes;
  final bool hauteurSerree;
  final bool estTablette;
  final double largeurMaxContenu;
  final double largeurCarteEnRangee;
  final double hauteurLogo;
  final double paddingEcran;
  final double paddingCarte;
  final double tailleTitre;
  final double espaceMarqueCarte;

  const AuthMesures({
    required this.deuxColonnes,
    required this.hauteurSerree,
    required this.estTablette,
    required this.largeurMaxContenu,
    required this.largeurCarteEnRangee,
    required this.hauteurLogo,
    required this.paddingEcran,
    required this.paddingCarte,
    required this.tailleTitre,
    required this.espaceMarqueCarte,
  });

  factory AuthMesures.depuis(
    BoxConstraints contraintes,
    double coteCourt, {
    double largeurCompacte = 440,
    double largeurTablette = 500,
    double largeurDeuxColonnes = 980,
    double largeurCarteEnRangeeCompacte = 396,
    double largeurCarteEnRangeeTablette = 460,
  }) {
    final largeur = contraintes.maxWidth;
    final hauteur = contraintes.maxHeight;

    final estTablette = coteCourt >= 600;

    // Deux colonnes uniquement en paysage suffisamment large : en portrait,
    // même sur une grande tablette, l'œil suit mieux un axe vertical unique.
    final deuxColonnes = largeur > hauteur && largeur >= 720 && hauteur >= 360;

    // Hauteur contrainte : petit téléphone, paysage, ou clavier ouvert. On
    // resserre alors tout ce qui est décoratif (logo, marges, titre) pour
    // préserver ce qui compte — les champs et le bouton.
    final hauteurSerree = hauteur < 640;

    double logo;
    if (hauteurSerree) {
      logo = 74;
    } else if (estTablette) {
      logo = deuxColonnes ? 150 : 132;
    } else {
      logo = deuxColonnes ? 118 : 104;
    }

    return AuthMesures(
      deuxColonnes: deuxColonnes,
      hauteurSerree: hauteurSerree,
      estTablette: estTablette,
      largeurMaxContenu: deuxColonnes ? largeurDeuxColonnes : (estTablette ? largeurTablette : largeurCompacte),
      largeurCarteEnRangee: estTablette ? largeurCarteEnRangeeTablette : largeurCarteEnRangeeCompacte,
      hauteurLogo: logo,
      paddingEcran: estTablette ? 40 : 22,
      paddingCarte: hauteurSerree ? 20 : (estTablette ? 32 : 24),
      tailleTitre: hauteurSerree ? 25 : (estTablette ? 34 : 30),
      espaceMarqueCarte: hauteurSerree ? 16 : (estTablette ? 32 : 26),
    );
  }
}

/// Charpente commune à tous les écrans publics : photo plein écran + voile,
/// puis contenu centré et limité en largeur, avec animation d'entrée.
///
/// `contenu` reçoit les [AuthMesures] déjà calculées pour construire une
/// disposition en colonne (portrait) ou en rangée (paysage large) — voir
/// [LoginPage] et [RegisterPage] pour deux implémentations différentes de
/// cette disposition, au-dessus du même socle visuel.
class AuthBackdrop extends StatelessWidget {
  final Widget Function(BuildContext context, AuthMesures mesures) contenu;
  final double largeurCompacte;
  final double largeurTablette;
  final double largeurDeuxColonnes;
  final double largeurCarteEnRangeeCompacte;
  final double largeurCarteEnRangeeTablette;

  /// Écran atteint par une navigation « poussée » (mot de passe oublié,
  /// saisie du code…) plutôt que par une redirection du routeur : fournir un
  /// callback ici affiche un bouton retour flottant. `null` (connexion,
  /// inscription — écrans racines) n'affiche rien.
  final VoidCallback? onRetour;

  const AuthBackdrop({
    super.key,
    required this.contenu,
    this.largeurCompacte = 440,
    this.largeurTablette = 500,
    this.largeurDeuxColonnes = 980,
    this.largeurCarteEnRangeeCompacte = 396,
    this.largeurCarteEnRangeeTablette = 460,
    this.onRetour,
  });

  @override
  Widget build(BuildContext context) {
    // Le fond garde la hauteur PLEIN ÉCRAN même quand le corps du Scaffold
    // se réduit sous le clavier : sans cela, `BoxFit.cover` recadrerait la
    // photo à chaque ouverture/fermeture du clavier — l'image « saute » et
    // le dégradé se comprime. Le Stack se contente de rogner le bas, le
    // cadrage ne bouge jamais.
    final hauteurEcran = MediaQuery.sizeOf(context).height;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: hauteurEcran,
          child: Image.asset(authBackgroundImage, fit: BoxFit.cover, alignment: Alignment.center),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: hauteurEcran,
          child: const AuthGradientOverlay(),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, contraintes) {
              final m = AuthMesures.depuis(
                contraintes,
                MediaQuery.sizeOf(context).shortestSide,
                largeurCompacte: largeurCompacte,
                largeurTablette: largeurTablette,
                largeurDeuxColonnes: largeurDeuxColonnes,
                largeurCarteEnRangeeCompacte: largeurCarteEnRangeeCompacte,
                largeurCarteEnRangeeTablette: largeurCarteEnRangeeTablette,
              );

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: m.paddingEcran, vertical: 24),
                child: ConstrainedBox(
                  // `Center` ne centre que s'il reste de la place : le
                  // formulaire est au milieu sur un grand écran, et défile
                  // normalement sur un petit ou clavier ouvert.
                  //
                  // Le plancher à zéro n'est pas décoratif : `maxHeight` tombe
                  // sous 48 dès que la zone visible se réduit à une bande —
                  // clavier logiciel déployé sur un petit écran, fenêtre de
                  // navigateur redimensionnée. Une contrainte de hauteur
                  // minimale NÉGATIVE fait échouer la mise en page, et l'écran
                  // de connexion devient blanc.
                  constraints: BoxConstraints(
                    minHeight: (contraintes.maxHeight - 48).clamp(0.0, double.infinity),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      // Un formulaire pleine largeur devient illisible sur
                      // tablette (lignes trop longues) : la largeur est
                      // plafonnée, pas étirée.
                      constraints: BoxConstraints(maxWidth: m.largeurMaxContenu),
                      child: AuthEntranceAnimation(child: contenu(context, m)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (onRetour != null)
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(bottom: false, child: AuthBackButton(onPressed: onRetour!)),
          ),
      ],
    );
  }
}

/// Bouton retour flottant sur fond photo — cercle translucide, cohérent avec
/// le langage visuel des écrans d'authentification. Utilisé par les écrans
/// atteints via une navigation poussée (voir `AuthBackdrop.onRetour`).
class AuthBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AuthBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.32),
      shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.22))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// Voile dégradé posé sur la photo. Deux rôles : garantir le contraste du
/// texte blanc (la photo est claire en haut à droite), et faire ressortir le
/// centre de l'écran où vit le formulaire.
class AuthGradientOverlay extends StatelessWidget {
  const AuthGradientOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0B1220).withValues(alpha: 0.62),
            const Color(0xFF0B1220).withValues(alpha: 0.74),
            const Color(0xFF0B1220).withValues(alpha: 0.90),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

/// Bloc de marque affiché au-dessus du formulaire.
///
/// Le logo officiel porte déjà le pictogramme ET le nom : le style codé ici
/// se limite donc au support qui le rend lisible — pas de nom retapé en
/// typographie, qui ferait doublon avec l'image.
///
/// Le support blanc n'est pas décoratif : le logo est fourni en JPEG à fond
/// blanc et son texte « WID » est bleu nuit, invisible sur un fond sombre.
class AuthMarque extends StatelessWidget {
  /// Hauteur du logo — pilotée par [AuthMesures] : marges et rayon en
  /// découlent, pour que le support garde les mêmes proportions à toutes les
  /// tailles.
  final double hauteurLogo;

  const AuthMarque({super.key, required this.hauteurLogo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: hauteurLogo * 0.21,
        vertical: hauteurLogo * 0.155,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(hauteurLogo * 0.23),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Image.asset(
        authLogoImage,
        height: hauteurLogo,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// Carte « verre dépoli » : le flou laisse deviner la photo sans jamais
/// nuire à la lisibilité du texte posé dessus. Conteneur commun à tout
/// formulaire d'authentification (connexion, inscription…).
class AuthGlassCard extends StatelessWidget {
  final AuthMesures mesures;
  final Widget child;

  const AuthGlassCard({super.key, required this.mesures, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            mesures.paddingCarte,
            mesures.paddingCarte + 6,
            mesures.paddingCarte,
            mesures.paddingCarte + 4,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Titre + sous-titre centrés en tête de carte (« Se connecter », « Créer un
/// compte »…).
class AuthCardHeader extends StatelessWidget {
  final String titre;
  final String sousTitre;
  final AuthMesures mesures;

  const AuthCardHeader({
    super.key,
    required this.titre,
    required this.sousTitre,
    required this.mesures,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          titre,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: mesures.tailleTitre,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.1,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sousTitre,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.45,
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
      ],
    );
  }
}

/// En-tête de section à l'intérieur de la carte (« Vos informations »,
/// « Votre organisation »…) — regroupe visuellement un long formulaire sans
/// changer de conteneur (contrairement à des `fieldset` séparés côté web).
class AuthSectionLabel extends StatelessWidget {
  final String texte;
  final IconData icone;

  const AuthSectionLabel({super.key, required this.texte, required this.icone});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 16, color: AppColors.accentLight),
        const SizedBox(width: 8),
        Text(
          texte.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

/// Range 1 à N champs sur une même ligne quand la largeur disponible le
/// permet (tablette, paysage), sinon les empile verticalement (téléphone en
/// portrait).
///
/// Sans ce repli, un couple de champs (prénom/nom, ville/pays…) écrasé sur un
/// téléphone étroit produirait des champs trop comprimés pour rester
/// lisibles — c'est l'équivalent responsive du `grid-2` CSS utilisé côté web
/// (`admin/src/pages/auth/Register.jsx`).
class AuthFieldRow extends StatelessWidget {
  final List<Widget> children;
  final double seuilRangee;
  final double espacement;

  const AuthFieldRow({
    super.key,
    required this.children,
    this.seuilRangee = 380,
    this.espacement = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (children.length == 1) return children.first;

    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth < seuilRangee) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: espacement),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: espacement),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Bouton d'action principal d'un écran d'authentification.
///
/// N'utilise pas `PrimaryButton` (widget partagé du reste de l'app) : celui-ci
/// hérite du thème clair — rayon 12, sans halo — alors que ces écrans ont
/// leur propre langage visuel (rayon 16 aligné sur les champs, halo orange
/// sur fond sombre).
class AuthActionButton extends StatelessWidget {
  final String label;
  final IconData icone;
  final bool enCours;
  final VoidCallback onPressed;

  const AuthActionButton({
    super.key,
    required this.label,
    this.icone = Icons.arrow_forward_rounded,
    required this.enCours,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: enCours ? 0.20 : 0.45),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: enCours ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.70),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          // Le padding horizontal par défaut de Material (24 de chaque côté)
          // ne laissait plus assez de place au libellé + icône quand ce
          // bouton partage la ligne avec [AuthSecondaryButton] (largeur
          // divisée en deux) — débordement (bandes jaunes/noires) sur les
          // écrans étroits.
          padding: const EdgeInsets.symmetric(horizontal: 10),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: enCours
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            // `FittedBox` : filet de sécurité si, malgré le padding réduit,
            // le libellé + l'icône ne tiennent toujours pas (bouton très
            // étroit, libellé long) — le contenu rétrécit plutôt que de
            // déborder.
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(icone, size: 19),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Bouton d'action secondaire (« Précédent ») — contour translucide, sans le
/// halo orange de [AuthActionButton], pour rester visuellement subordonné au
/// bouton principal quand les deux sont côte à côte.
class AuthSecondaryButton extends StatelessWidget {
  final String label;
  final IconData icone;
  final VoidCallback onPressed;

  const AuthSecondaryButton({
    super.key,
    required this.label,
    this.icone = Icons.arrow_back_rounded,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        // Voir le commentaire équivalent dans [AuthActionButton] : le
        // padding par défaut de Material laissait déborder libellé + icône
        // quand ce bouton partage la ligne avec lui.
        padding: const EdgeInsets.symmetric(horizontal: 10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Repère d'avancement d'un formulaire en plusieurs étapes (« Étape 1/2 » +
/// puces). Purement indicatif — la navigation reste assurée par les boutons
/// Suivant/Précédent, jamais par un tap sur une puce (une étape non validée
/// ne doit pas être atteignable en sautant les autres).
class AuthStepIndicator extends StatelessWidget {
  final int etapeCourante;
  final List<String> libelles;

  const AuthStepIndicator({super.key, required this.etapeCourante, required this.libelles});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < libelles.length; i++) ...[
              if (i > 0)
                Container(
                  width: 28,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i <= etapeCourante ? AppColors.accentLight : Colors.white.withValues(alpha: 0.25),
                ),
              _Puce(actif: i == etapeCourante, franchi: i < etapeCourante),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          context.l10n.authEtapeIndicateur(etapeCourante + 1, libelles.length, libelles[etapeCourante]),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Puce extends StatelessWidget {
  final bool actif;
  final bool franchi;

  const _Puce({required this.actif, required this.franchi});

  @override
  Widget build(BuildContext context) {
    final rempli = actif || franchi;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: actif ? 22 : 9,
      height: 9,
      decoration: BoxDecoration(
        color: rempli ? AppColors.accentLight : Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

/// Ligne de pied de page (« Pas encore de compte ? Créer un compte »,
/// « Déjà un compte ? Se connecter »…).
class AuthFooterLink extends StatelessWidget {
  final String question;
  final String action;
  final VoidCallback onPressed;

  const AuthFooterLink({
    super.key,
    required this.question,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // `Wrap` plutôt que `Row` : sur un écran étroit avec une question un peu
    // longue, un `Row` (même avec le `Text` dans un `Flexible`) force la
    // question à passer sur 2 lignes ET garde le bouton sur cette même
    // ligne — le tout dépasse alors la largeur ou s'écrase contre le bord.
    // `Wrap` laisse le bouton retomber proprement sous la question quand ça
    // ne tient pas sur une ligne, sans jamais déborder.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(
          question,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 14),
        ),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accentLight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(action, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Apparition du formulaire — fondu + légère remontée. Joué une seule fois,
/// à l'ouverture de l'écran.
class AuthEntranceAnimation extends StatelessWidget {
  final Widget child;

  const AuthEntranceAnimation({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, valeur, enfant) => Opacity(
        opacity: valeur,
        child: Transform.translate(offset: Offset(0, 26 * (1 - valeur)), child: enfant),
      ),
      child: child,
    );
  }
}

/// Affiche le popup de confirmation d'un écran d'authentification — une
/// feuille qui monte depuis le bas de l'écran, avec le message tel que reçu
/// du backend et un unique bouton « OK ».
///
/// Volontairement NON fermable par balayage ou tap en dehors
/// (`isDismissible`/`enableDrag` à `false`) : le seul geste qui referme la
/// feuille est le bouton, de sorte que [onFerme] — qui déclenche la suite du
/// parcours (ex. navigation vers la saisie du code) — corresponde exactement
/// au moment où l'utilisateur a acquitté le message.
Future<void> showAuthNoticeSheet(
  BuildContext context, {
  required String message,
  String? bouton,
  IconData icone = Icons.mark_email_read_outlined,
  VoidCallback? onFerme,
}) async {
  final libelleBouton = bouton ?? context.l10n.commonOk;
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xFF0B1220).withValues(alpha: 0.72),
    builder: (context) => _AuthNoticeSheet(message: message, bouton: libelleBouton, icone: icone),
  );
  onFerme?.call();
}

class _AuthNoticeSheet extends StatelessWidget {
  final String message;
  final String bouton;
  final IconData icone;

  const _AuthNoticeSheet({required this.message, required this.bouton, required this.icone});

  @override
  Widget build(BuildContext context) {
    return AuthEntranceAnimation(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.paddingOf(context).bottom),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220).withValues(alpha: 0.82),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Poignée décorative — la feuille n'est pas balayable (voir
                // `showAuthNoticeSheet`), elle reste ici comme simple repère
                // visuel de « feuille du bas », pas comme affordance de geste.
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.45), width: 1.4),
                  ),
                  child: Icon(icone, color: AppColors.accentLight, size: 30),
                ),
                const SizedBox(height: 18),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                AuthActionButton(
                  label: bouton,
                  icone: Icons.check_rounded,
                  enCours: false,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
