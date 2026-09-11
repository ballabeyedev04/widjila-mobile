import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../data/historique_observations.dart';
import '../../domain/suggestions_observation.dart';
import 'dictee_vocale.dart';

/// Champ « Observation » de la création d'une réserve : saisie libre, DICTÉE
/// et SUGGESTIONS tirées des observations déjà employées.
///
/// ## Dictée
///
/// L'icône micro démarre la reconnaissance vocale du téléphone ; un second
/// appui l'arrête. Les mots reconnus s'ajoutent À LA SUITE du texte déjà
/// présent — « client VIP » + « livraison demain » donne « client VIP
/// livraison demain » — et apparaissent pendant qu'on parle. Rien de ce qui
/// était écrit n'est jamais remplacé : si l'utilisateur reprend le clavier
/// pendant l'écoute, la dictée s'arrête et son texte à lui reste tel quel.
///
/// ## Suggestions
///
/// Dès deux caractères, les observations déjà employées qui correspondent à
/// la phrase en cours sont proposées sous le champ (« coi » → « coins
/// casse »). En choisir une remplace la phrase en cours ; ne pas en choisir
/// laisse la saisie parfaitement libre.
class ChampObservation extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;

  /// Historique des observations ; `null` : pas de suggestions.
  final SourceObservations? historique;

  final MoteurDictee moteur;

  const ChampObservation({
    super.key,
    required this.controller,
    required this.labelText,
    required this.hintText,
    required this.moteur,
    this.historique,
  });

  @override
  State<ChampObservation> createState() => _ChampObservationState();
}

enum _Dictee { inactive, demarrage, ecoute }

class _ChampObservationState extends State<ChampObservation> with SingleTickerProviderStateMixin {
  /// Miroir de `creerReserveSchema` côté serveur (`description` : max 5000).
  static const int _longueurMax = 5000;

  final FocusNode _focus = FocusNode();
  late final AnimationController _pulsation =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  List<String> _historique = const [];
  _Dictee _dictee = _Dictee.inactive;
  ErreurDictee? _erreur;

  /// Texte du champ au début de l'écoute en cours — la dictée s'ajoute à lui.
  String _base = '';

  /// Vrai pendant que le champ écrit lui-même dans le contrôleur : ces
  /// changements-là ne sont pas une reprise en main par l'utilisateur.
  bool _ecritureInterne = false;

  bool _motsRecus = false;
  bool _arretDemande = false;

  /// L'écoute en cours a été abandonnée (saisie au clavier, fermeture) : ses
  /// résultats tardifs sont ignorés.
  bool _abandonnee = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_surTexte);
    _focus.addListener(_surFocus);
    _chargerHistorique();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_surTexte);
    _focus.removeListener(_surFocus);
    if (_dictee != _Dictee.inactive) {
      _abandonnee = true;
      widget.moteur.annuler();
    }
    _focus.dispose();
    _pulsation.dispose();
    super.dispose();
  }

  Future<void> _chargerHistorique() async {
    final source = widget.historique;
    if (source == null) return;
    final liste = await source.charger();
    if (mounted) setState(() => _historique = liste);
  }

  void _surFocus() => setState(() {});

  void _surTexte() {
    if (_ecritureInterne) return;
    if (_dictee == _Dictee.ecoute) {
      // L'utilisateur reprend la main au clavier : on arrête d'écouter, et un
      // résultat tardif ne doit pas écraser ce qu'il vient de taper.
      _abandonnee = true;
      widget.moteur.annuler();
      _pulsation
        ..stop()
        ..value = 0;
      _dictee = _Dictee.inactive;
    }
    setState(() => _erreur = null);
  }

  Future<void> _basculerDictee() async {
    if (_dictee == _Dictee.ecoute) {
      _arretDemande = true;
      await widget.moteur.arreter();
      return;
    }
    if (_dictee == _Dictee.demarrage) return;

    setState(() {
      _dictee = _Dictee.demarrage;
      _erreur = null;
    });
    final langue = Localizations.localeOf(context).toLanguageTag();
    final erreur = await widget.moteur.preparer();
    if (!mounted) return;
    if (erreur != null) {
      setState(() {
        _dictee = _Dictee.inactive;
        _erreur = erreur;
      });
      return;
    }

    _base = widget.controller.text;
    _motsRecus = false;
    _arretDemande = false;
    _abandonnee = false;
    setState(() => _dictee = _Dictee.ecoute);
    _pulsation.repeat(reverse: true);
    await widget.moteur.ecouter(langue: langue, surResultat: _surResultat, surFin: _surFin);
  }

  void _surResultat(String texte, bool definitif) {
    if (_abandonnee || !mounted) return;
    if (texte.trim().isNotEmpty) _motsRecus = true;
    // Toujours la BASE + ce qui est reconnu depuis le début de l'écoute : un
    // résultat partiel remplace le partiel précédent, jamais le texte d'avant.
    _ecrire(joindreDictee(_base, texte));
    if (definitif) _base = widget.controller.text;
  }

  void _surFin(ErreurDictee? erreur) {
    if (!mounted) return;
    _pulsation
      ..stop()
      ..value = 0;
    final ErreurDictee? affichee;
    if (_abandonnee) {
      affichee = null;
    } else if (erreur == null || erreur == ErreurDictee.aucuneParole) {
      // Silence : ce n'est un problème que si RIEN n'a été reconnu et que
      // l'utilisateur n'a pas arrêté lui-même.
      affichee = (_motsRecus || _arretDemande) ? null : ErreurDictee.aucuneParole;
    } else {
      affichee = erreur;
    }
    setState(() {
      _dictee = _Dictee.inactive;
      _erreur = affichee;
    });
  }

  void _ecrire(String texte) {
    final borne = texte.length > _longueurMax ? texte.substring(0, _longueurMax) : texte;
    _ecritureInterne = true;
    widget.controller.value = TextEditingValue(
      text: borne,
      selection: TextSelection.collapsed(offset: borne.length),
    );
    _ecritureInterne = false;
    setState(() {});
  }

  void _choisirSuggestion(String suggestion) {
    _ecrire(remplacerFragment(widget.controller.text, suggestion));
    _focus.requestFocus();
  }

  List<String> get _suggestions {
    if (!_focus.hasFocus || _dictee != _Dictee.inactive) return const [];
    return suggestionsObservation(_historique, fragmentEnCours(widget.controller.text).fragment);
  }

  String _message(AppLocalizations l10n, ErreurDictee erreur) => switch (erreur) {
        ErreurDictee.microRefuse => l10n.reserveNouvDicteeMicroRefuse,
        ErreurDictee.indisponible => l10n.reserveNouvDicteeIndisponible,
        ErreurDictee.aucuneParole => l10n.reserveNouvDicteeAucuneParole,
        ErreurDictee.reseau => l10n.reserveNouvDicteeReseau,
        ErreurDictee.interrompue => l10n.reserveNouvDicteeInterrompue,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final suggestions = _suggestions;
    final erreur = _erreur;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focus,
          maxLines: 3,
          maxLength: _longueurMax,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            alignLabelWithHint: true,
            suffixIcon: _BoutonMicro(
              etat: _dictee,
              pulsation: _pulsation,
              tooltip: _dictee == _Dictee.ecoute ? l10n.reserveNouvDicteeArreter : l10n.reserveNouvDicter,
              onPressed: _basculerDictee,
            ),
          ),
        ),
        if (_dictee == _Dictee.ecoute)
          _LigneEcoute(texte: l10n.reserveNouvDicteeEcoute, pulsation: _pulsation)
        else if (erreur != null)
          _LigneErreur(texte: _message(l10n, erreur)),
        if (suggestions.isNotEmpty)
          // Région du champ : toucher une suggestion ne lui retire pas le
          // focus (et ne referme pas le clavier).
          TextFieldTapRegion(
            child: _Suggestions(
              titre: l10n.reserveNouvSuggestionsTitre,
              suggestions: suggestions,
              onChoisir: _choisirSuggestion,
            ),
          ),
      ],
    );
  }
}

/// Icône micro du champ : normale au repos, indicateur pendant la
/// préparation, rouge pulsé pendant l'écoute.
class _BoutonMicro extends StatelessWidget {
  final _Dictee etat;
  final Animation<double> pulsation;
  final String tooltip;
  final VoidCallback onPressed;

  const _BoutonMicro({
    required this.etat,
    required this.pulsation,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final Widget icone = switch (etat) {
      _Dictee.inactive => const Icon(Icons.mic_none_rounded, color: AppColors.textSecondary),
      _Dictee.demarrage => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      _Dictee.ecoute => AnimatedBuilder(
          animation: pulsation,
          builder: (context, _) => Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.danger.withValues(alpha: 0.12 + 0.16 * pulsation.value),
            ),
            child: const Icon(Icons.mic_rounded, color: AppColors.danger, size: 22),
          ),
        ),
    };

    return IconButton(
      key: const ValueKey('micro-observation'),
      tooltip: tooltip,
      onPressed: etat == _Dictee.demarrage ? null : onPressed,
      icon: icone,
    );
  }
}

/// « Écoute en cours… » sous le champ, avec un point rouge qui pulse.
class _LigneEcoute extends StatelessWidget {
  final String texte;
  final Animation<double> pulsation;

  const _LigneEcoute({required this.texte, required this.pulsation});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1).animate(pulsation),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texte,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Message d'une dictée impossible ou interrompue.
class _LigneErreur extends StatelessWidget {
  final String texte;

  const _LigneErreur({required this.texte});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(texte, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Observations déjà employées qui correspondent à la phrase en cours.
class _Suggestions extends StatelessWidget {
  final String titre;
  final List<String> suggestions;
  final ValueChanged<String> onChoisir;

  const _Suggestions({required this.titre, required this.suggestions, required this.onChoisir});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in suggestions)
                ActionChip(
                  key: ValueKey('suggestion-$s'),
                  avatar: const Icon(Icons.history_rounded, size: 16, color: AppColors.textSecondary),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  backgroundColor: AppColors.background,
                  side: const BorderSide(color: AppColors.border),
                  shape: const StadiumBorder(),
                  onPressed: () => onChoisir(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
