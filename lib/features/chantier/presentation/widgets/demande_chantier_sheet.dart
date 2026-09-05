import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/service_position.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liste_chrome.dart' show ContenuFormulaire;
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../organisation/domain/entities/membre.dart';
import '../../domain/entities/chantier.dart';
import '../cubit/creer_chantier_cubit.dart';

/// Formulaire de DEMANDE de création de chantier.
///
/// Mêmes champs que l'espace d'administration — nom, code, description,
/// adresse, coordonnées, dates, budget, responsable — comme demandé par le
/// client. Un valideur qui doit rappeler le demandeur pour connaître l'adresse
/// ou les dates ne tranche pas : autant tout recueillir au dépôt.
///
/// Seul le NOM est obligatoire, comme côté serveur. Une entreprise qui dépose
/// ses plans un vendredi soir n'a pas forcément le budget sous la main, et
/// exiger neuf champs ferait abandonner la demande.
///
/// Retourne le [Chantier] créé — en statut « en attente de validation » — ou
/// `null` si l'utilisateur referme.
Future<Chantier?> demanderChantier(BuildContext context) {
  return showModalBottomSheet<Chantier>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider(
      create: (_) => sl<CreerChantierCubit>()..chargerMembres(),
      child: const _Feuille(),
    ),
  );
}

class _Feuille extends StatefulWidget {
  const _Feuille();

  @override
  State<_Feuille> createState() => _FeuilleState();
}

class _FeuilleState extends State<_Feuille> {
  final _cle = GlobalKey<FormState>();

  final _nom = TextEditingController();
  final _code = TextEditingController();
  final _description = TextEditingController();
  final _adresse = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _budget = TextEditingController();

  DateTime? _dateDebut;
  DateTime? _dateFin;
  String? _responsableId;

  /// `true` pendant la recherche de position — le bouton montre l'attente
  /// plutôt que de rester inerte pendant les douze secondes du délai.
  bool _positionEnCours = false;

  @override
  void dispose() {
    for (final c in [_nom, _code, _description, _adresse, _latitude, _longitude, _budget]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choisirDate({required bool debut}) async {
    final maintenant = DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: (debut ? _dateDebut : _dateFin) ?? maintenant,
      // Bornes larges : un chantier peut avoir démarré l'an dernier, ou
      // s'achever dans cinq ans. Les resserrer aurait bloqué des saisies
      // légitimes sans rien protéger.
      firstDate: DateTime(maintenant.year - 5),
      lastDate: DateTime(maintenant.year + 10),
    );
    if (choisie == null) return;
    setState(() {
      if (debut) {
        _dateDebut = choisie;
      } else {
        _dateFin = choisie;
      }
    });
  }

  /// Renseigne latitude et longitude depuis la position de l'appareil.
  ///
  /// Chaque cause d'échec a SON message : « activez la localisation » et
  /// « autorisez l'application » demandent deux gestes opposés, dans deux
  /// écrans de réglages différents. Un message générique enverrait chercher au
  /// mauvais endroit.
  Future<void> _utiliserMaPosition() async {
    if (_positionEnCours) return;
    setState(() => _positionEnCours = true);

    final resultat = await const ServicePosition().obtenir();
    if (!mounted) return;
    setState(() => _positionEnCours = false);

    final l10n = context.l10n;
    if (resultat.reussi) {
      setState(() {
        // Cinq décimales : environ un mètre. Au-delà, on afficherait du bruit
        // de mesure — aucun GPS de téléphone n'est précis au centimètre.
        _latitude.text = resultat.latitude!.toStringAsFixed(5);
        _longitude.text = resultat.longitude!.toStringAsFixed(5);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.positionRelevee), backgroundColor: AppColors.success),
      );
      return;
    }

    final message = switch (resultat.echec!) {
      EchecPosition.serviceDesactive => l10n.positionServiceDesactive,
      EchecPosition.refusee => l10n.positionRefusee,
      EchecPosition.refuseeDefinitivement => l10n.positionRefuseeDefinitivement,
      EchecPosition.indisponible => l10n.positionIndisponible,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.warning),
    );
  }

  void _envoyer() {
    if (!(_cle.currentState?.validate() ?? false)) return;

    context.read<CreerChantierCubit>().envoyer(
          nom: _nom.text.trim(),
          code: _code.text.trim(),
          adresse: _adresse.text.trim(),
          description: _description.text.trim(),
          latitude: double.tryParse(_latitude.text.trim().replaceAll(',', '.')),
          longitude: double.tryParse(_longitude.text.trim().replaceAll(',', '.')),
          dateDebut: _dateDebut,
          dateFin: _dateFin,
          budget: num.tryParse(_budget.text.trim().replaceAll(',', '.')),
          responsableId: _responsableId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocConsumer<CreerChantierCubit, CreerChantierState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, etat) {
        if (etat.status == CreerChantierStatus.succes && etat.cree != null) {
          Navigator.of(context).pop(etat.cree);
        }
        if (etat.status == CreerChantierStatus.erreur && etat.erreur != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(etat.erreur!), backgroundColor: AppColors.danger),
          );
        }
      },
      builder: (context, etat) {
        final envoiEnCours = etat.status == CreerChantierStatus.envoi;

        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, defilement) {
            // Sur une tablette, la feuille occupe toute la largeur — et les
            // champs avec elle : pres de 1000 px pour saisir un nom de
            // chantier. `ContenuFormulaire` ramene le contenu a 440 px
            // centres, la largeur de reference des formulaires de
            // l'application. Sans effet sur telephone, ou l'ecran est deja
            // plus etroit que cette borne.
            return ContenuFormulaire(
                child: Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _Entete(titre: l10n.demandeChantierTitre, sousTitre: l10n.demandeChantierSousTitre),
                  Expanded(
                    child: Form(
                      key: _cle,
                      child: ListView(
                        controller: defilement,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        children: [
                          _Champ(
                            controleur: _nom,
                            libelle: l10n.demandeChantierNom,
                            icone: Icons.apartment_outlined,
                            // Seul champ obligatoire, comme côté serveur.
                            validateur: (v) =>
                                (v ?? '').trim().isEmpty ? l10n.demandeChantierNomRequis : null,
                          ),
                          _Champ(
                            controleur: _code,
                            libelle: l10n.demandeChantierCode,
                            icone: Icons.tag_rounded,
                            aide: l10n.demandeChantierCodeAide,
                          ),
                          _Champ(
                            controleur: _adresse,
                            libelle: l10n.demandeChantierAdresse,
                            icone: Icons.place_outlined,
                          ),
                          _Champ(
                            controleur: _description,
                            libelle: l10n.demandeChantierDescription,
                            icone: Icons.notes_outlined,
                            lignes: 3,
                          ),
                          // Le bouton AVANT les champs : c'est le geste
                          // attendu, la saisie manuelle n'est que le repli.
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _positionEnCours ? null : _utiliserMaPosition,
                              icon: _positionEnCours
                                  ? const SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.my_location_rounded, size: 18),
                              label: Text(
                                _positionEnCours
                                    ? l10n.positionRecherche
                                    : l10n.positionUtiliserMaPosition,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _Champ(
                                  controleur: _latitude,
                                  libelle: l10n.demandeChantierLatitude,
                                  icone: Icons.my_location_rounded,
                                  clavier: const TextInputType.numberWithOptions(
                                    decimal: true, signed: true,
                                  ),
                                  validateur: (v) => _validerCoordonnee(v, min: -90, max: 90, l10n: l10n),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _Champ(
                                  controleur: _longitude,
                                  libelle: l10n.demandeChantierLongitude,
                                  icone: Icons.explore_outlined,
                                  clavier: const TextInputType.numberWithOptions(
                                    decimal: true, signed: true,
                                  ),
                                  validateur: (v) => _validerCoordonnee(v, min: -180, max: 180, l10n: l10n),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _ChampDate(
                                  libelle: l10n.demandeChantierDateDebut,
                                  date: _dateDebut,
                                  onTap: () => _choisirDate(debut: true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _ChampDate(
                                  libelle: l10n.demandeChantierDateFin,
                                  date: _dateFin,
                                  onTap: () => _choisirDate(debut: false),
                                ),
                              ),
                            ],
                          ),
                          // La cohérence des dates est vérifiée ICI et non
                          // dans un validateur de champ : elle porte sur la
                          // PAIRE, et l'attacher à l'un des deux ferait
                          // clignoter l'erreur au gré de l'ordre de saisie.
                          if (_dateDebut != null && _dateFin != null && _dateFin!.isBefore(_dateDebut!))
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                l10n.demandeChantierDatesIncoherentes,
                                style: const TextStyle(fontSize: 12, color: AppColors.danger),
                              ),
                            ),
                          _Champ(
                            controleur: _budget,
                            libelle: l10n.demandeChantierBudget,
                            icone: Icons.euro_rounded,
                            clavier: const TextInputType.numberWithOptions(decimal: true),
                            validateur: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return null;
                              final n = num.tryParse(t.replaceAll(',', '.'));
                              if (n == null) return l10n.demandeChantierBudgetInvalide;
                              // Le serveur exige un budget STRICTEMENT positif :
                              // le refuser ici évite un aller-retour pour une
                              // erreur que le formulaire voit seul.
                              if (n <= 0) return l10n.demandeChantierBudgetInvalide;
                              return null;
                            },
                          ),
                          _ChampResponsable(
                            membres: etat.membres,
                            choisi: _responsableId,
                            onChange: (id) => setState(() => _responsableId = id),
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: envoiEnCours ? null : _envoyer,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              minimumSize: const Size.fromHeight(50),
                            ),
                            child: Text(
                              envoiEnCours
                                  ? l10n.demandeChantierEnvoiEnCours
                                  : l10n.demandeChantierEnvoyer,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.demandeChantierAvertissementValidation,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ));
          },
        );
      },
    );
  }
}

String? _validerCoordonnee(String? valeur, {required double min, required double max, required dynamic l10n}) {
  final t = (valeur ?? '').trim();
  if (t.isEmpty) return null;
  final n = double.tryParse(t.replaceAll(',', '.'));
  // Bornes du serveur : les vérifier ici évite un refus après envoi, sur un
  // formulaire de neuf champs qu'il faudrait rouvrir.
  if (n == null || n < min || n > max) return l10n.demandeChantierCoordonneeInvalide;
  return null;
}

class _Entete extends StatelessWidget {
  final String titre;
  final String sousTitre;

  const _Entete({required this.titre, required this.sousTitre});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.add_business_rounded, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        titre,
                        style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sousTitre,
                        style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: context.l10n.commonClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Champ extends StatelessWidget {
  final TextEditingController controleur;
  final String libelle;
  final IconData icone;
  final String? aide;
  final int lignes;
  final TextInputType? clavier;
  final String? Function(String?)? validateur;

  const _Champ({
    required this.controleur,
    required this.libelle,
    required this.icone,
    this.aide,
    this.lignes = 1,
    this.clavier,
    this.validateur,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controleur,
        maxLines: lignes,
        keyboardType: clavier,
        textInputAction: lignes > 1 ? TextInputAction.newline : TextInputAction.next,
        inputFormatters: clavier == null
            ? null
            // Le clavier décimal d'Android laisse taper des lettres sur
            // certains constructeurs : le filtre les écarte à la source.
            : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
        decoration: InputDecoration(
          labelText: libelle,
          helperText: aide,
          helperMaxLines: 2,
          prefixIcon: Icon(icone),
          alignLabelWithHint: lignes > 1,
        ),
        validator: validateur,
      ),
    );
  }
}

class _ChampDate extends StatelessWidget {
  final String libelle;
  final DateTime? date;
  final VoidCallback onTap;

  const _ChampDate({required this.libelle, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final texte = date == null
        ? ''
        : '${date!.day.toString().padLeft(2, '0')}/${date!.month.toString().padLeft(2, '0')}/${date!.year}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: libelle,
            prefixIcon: const Icon(Icons.event_outlined),
          ),
          child: Text(
            texte,
            style: TextStyle(
              fontSize: 15,
              color: texte.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChampResponsable extends StatelessWidget {
  final List<Membre> membres;
  final String? choisi;
  final ValueChanged<String?> onChange;

  const _ChampResponsable({required this.membres, required this.choisi, required this.onChange});

  @override
  Widget build(BuildContext context) {
    // Seuls les comptes ACTIFS. La liste vient de `/organisation/membres` —
    // filtrée par organisation côté serveur, donc jamais toute la base — mais
    // elle contient tous les statuts. Un compte inactif, en attente de
    // validation ou rejeté ne peut pas se connecter : le proposer comme
    // responsable serait proposer l'impossible.
    final actifs = membres.where((m) => m.statut == 'actif').toList();

    // Rien tant que la liste n'est pas revenue : un sélecteur vide donnerait
    // l'impression que l'organisation n'a aucun membre, alors que l'appel est
    // simplement en cours — ou a échoué sans conséquence, le champ étant
    // facultatif.
    if (actifs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String?>(
        initialValue: choisi,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.l10n.demandeChantierResponsable,
          prefixIcon: const Icon(Icons.person_outline_rounded),
        ),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(context.l10n.demandeChantierAucunResponsable),
          ),
          for (final m in actifs)
            DropdownMenuItem<String?>(
              value: m.id,
              child: Text('${m.prenom} ${m.nom}'.trim(), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChange,
      ),
    );
  }
}
