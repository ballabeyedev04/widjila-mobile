import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/fiche_chrome.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../organisation/domain/entities/organisation.dart';
import '../../../organisation/presentation/cubit/mon_organisation_cubit.dart';

/// Formulaire d'édition de l'entreprise — `PUT /organisation`.
///
/// N'expose QUE les champs de `modifierOrganisationSchema` : nom, raison
/// sociale, identifiants légaux, coordonnées, adresse. L'abonnement, le type
/// (siège / filiale / agence) et le statut sont pilotés par la facturation et
/// la plateforme — les proposer ici donnerait des champs qui échouent à
/// l'enregistrement.
///
/// Réservé aux rôles GESTION : l'appelant masque déjà le bouton, cette
/// feuille n'a donc pas à re-vérifier le rôle — mais un 403 serveur reste
/// affiché tel quel si la règle changeait d'un côté sans l'autre.
Future<void> ouvrirModificationOrganisation(BuildContext context, Organisation organisation) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Le cubit vient du contexte de la page : la feuille est montée par le
    // Navigator racine, hors de l'arbre de l'écran appelant.
    builder: (_) => BlocProvider.value(
      value: context.read<MonOrganisationCubit>(),
      child: _ModifierOrganisationSheet(organisation: organisation),
    ),
  );
}

class _ModifierOrganisationSheet extends StatefulWidget {
  final Organisation organisation;
  const _ModifierOrganisationSheet({required this.organisation});

  @override
  State<_ModifierOrganisationSheet> createState() => _ModifierOrganisationSheetState();
}

class _ModifierOrganisationSheetState extends State<_ModifierOrganisationSheet> {
  final _formKey = GlobalKey<FormState>();
  bool _envoiEnCours = false;

  late final _nomCtrl = TextEditingController(text: widget.organisation.nom);
  late final _raisonCtrl = TextEditingController(text: widget.organisation.raisonSociale ?? '');
  late final _siretCtrl = TextEditingController(text: widget.organisation.siret ?? '');
  late final _tvaCtrl = TextEditingController(text: widget.organisation.numTva ?? '');
  late final _rccmCtrl = TextEditingController(text: widget.organisation.rccm ?? '');
  late final _nineaCtrl = TextEditingController(text: widget.organisation.ninea ?? '');
  late final _telephoneCtrl = TextEditingController(text: widget.organisation.telephone ?? '');
  late final _emailCtrl = TextEditingController(text: widget.organisation.email ?? '');
  late final _adresseCtrl = TextEditingController(text: widget.organisation.adresse ?? '');
  late final _villeCtrl = TextEditingController(text: widget.organisation.ville ?? '');
  late final _paysCtrl = TextEditingController(text: widget.organisation.pays ?? '');

  List<TextEditingController> get _tousLesChamps => [
        _nomCtrl, _raisonCtrl, _siretCtrl, _tvaCtrl, _rccmCtrl, _nineaCtrl,
        _telephoneCtrl, _emailCtrl, _adresseCtrl, _villeCtrl, _paysCtrl,
      ];

  @override
  void dispose() {
    for (final c in _tousLesChamps) {
      c.dispose();
    }
    super.dispose();
  }

  /// N'envoie que ce qui a CHANGÉ — même règle que le formulaire de profil.
  /// Renvoyer l'intégralité du formulaire écraserait sans le vouloir un champ
  /// modifié entre-temps depuis l'interface web.
  String? _siModifie(String saisie, String? origine) {
    final valeur = saisie.trim();
    return valeur == (origine ?? '').trim() ? null : valeur;
  }

  String? _validerNom(String? v) {
    final l10n = context.l10n;
    final valeur = (v ?? '').trim();
    // Miroir de `creerOrganisationSchema` : min 2, max 150.
    if (valeur.isEmpty) return l10n.registerNomOrgRequis;
    if (valeur.length < 2) return l10n.membreFormChampTropCourt(2);
    if (valeur.length > 150) return l10n.membreFormChampTropLong(150);
    return null;
  }

  Future<void> _soumettre() async {
    if (_envoiEnCours) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final o = widget.organisation;
    final nom = _siModifie(_nomCtrl.text, o.nom);
    final raison = _siModifie(_raisonCtrl.text, o.raisonSociale);
    final siret = _siModifie(_siretCtrl.text, o.siret);
    final tva = _siModifie(_tvaCtrl.text, o.numTva);
    final rccm = _siModifie(_rccmCtrl.text, o.rccm);
    final ninea = _siModifie(_nineaCtrl.text, o.ninea);
    final telephone = _siModifie(_telephoneCtrl.text, o.telephone);
    final email = _siModifie(_emailCtrl.text, o.email);
    final adresse = _siModifie(_adresseCtrl.text, o.adresse);
    final ville = _siModifie(_villeCtrl.text, o.ville);
    final pays = _siModifie(_paysCtrl.text, o.pays);

    final riens = [nom, raison, siret, tva, rccm, ninea, telephone, email, adresse, ville, pays]
        .every((e) => e == null);
    if (riens) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _envoiEnCours = true);
    final erreur = await context.read<MonOrganisationCubit>().enregistrer(
          nom: nom,
          raisonSociale: raison,
          siret: siret,
          numTva: tva,
          rccm: rccm,
          ninea: ninea,
          telephone: telephone,
          email: email,
          adresse: adresse,
          ville: ville,
          pays: pays,
        );
    if (!mounted) return;
    setState(() => _envoiEnCours = false);

    final l10n = context.l10n;
    if (erreur != null) {
      // La feuille RESTE ouverte : la saisie est conservée et l'utilisateur
      // voit ce que le serveur a refusé.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erreur), backgroundColor: AppColors.danger),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.profilEntrepriseMaj), backgroundColor: AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _EnTete(titre: l10n.profilEntrepriseModifier),
            Expanded(
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: ContenuFormulaire(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      TitreSectionFiche(l10n.profilSectionEntreprise, icone: Icons.business_outlined),
                      _Champ(
                        controleur: _nomCtrl,
                        libelle: l10n.profilEntrepriseNom,
                        icone: Icons.badge_outlined,
                        validateur: _validerNom,
                        capitalisation: TextCapitalization.words,
                      ),
                      _Champ(
                        controleur: _raisonCtrl,
                        libelle: l10n.profilEntrepriseRaison,
                        icone: Icons.account_balance_outlined,
                        capitalisation: TextCapitalization.words,
                      ),
                      const SizedBox(height: 6),
                      TitreSectionFiche(l10n.profilSectionCompte, icone: Icons.numbers_rounded),
                      _Champ(
                        controleur: _siretCtrl,
                        libelle: l10n.profilEntrepriseSiret,
                        icone: Icons.confirmation_number_outlined,
                      ),
                      _Champ(
                        controleur: _tvaCtrl,
                        libelle: l10n.profilEntrepriseTva,
                        icone: Icons.receipt_long_outlined,
                      ),
                      _Champ(
                        controleur: _rccmCtrl,
                        libelle: l10n.profilEntrepriseRccm,
                        icone: Icons.gavel_rounded,
                      ),
                      _Champ(
                        controleur: _nineaCtrl,
                        libelle: l10n.profilEntrepriseNinea,
                        icone: Icons.pin_outlined,
                        // `ninea` est validé `alphanum` côté serveur : on
                        // écarte espaces et tirets à la saisie plutôt que de
                        // laisser Joi refuser après coup.
                        formateurs: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]'))],
                      ),
                      const SizedBox(height: 6),
                      TitreSectionFiche(l10n.profilEntrepriseAdresse, icone: Icons.place_outlined),
                      _Champ(
                        controleur: _telephoneCtrl,
                        libelle: l10n.profilTelephone,
                        icone: Icons.phone_outlined,
                        clavier: TextInputType.phone,
                      ),
                      _Champ(
                        controleur: _emailCtrl,
                        libelle: l10n.authChampEmail,
                        icone: Icons.mail_outline_rounded,
                        clavier: TextInputType.emailAddress,
                      ),
                      _Champ(
                        controleur: _adresseCtrl,
                        libelle: l10n.profilEntrepriseAdresse,
                        icone: Icons.home_outlined,
                        capitalisation: TextCapitalization.sentences,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _Champ(
                              controleur: _villeCtrl,
                              libelle: l10n.profilEntrepriseVille,
                              icone: Icons.location_city_outlined,
                              capitalisation: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _Champ(
                              controleur: _paysCtrl,
                              libelle: l10n.profilEntreprisePays,
                              icone: Icons.public_rounded,
                              capitalisation: TextCapitalization.words,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _BarreValidation(enCours: _envoiEnCours, onValider: _soumettre),
          ],
        ),
      ),
    );
  }
}

class _EnTete extends StatelessWidget {
  final String titre;
  const _EnTete({required this.titre});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.business_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titre,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
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
  final String? Function(String?)? validateur;
  final TextInputType? clavier;
  final TextCapitalization capitalisation;
  final List<TextInputFormatter>? formateurs;

  const _Champ({
    required this.controleur,
    required this.libelle,
    required this.icone,
    this.validateur,
    this.clavier,
    this.capitalisation = TextCapitalization.none,
    this.formateurs,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controleur,
          validator: validateur,
          keyboardType: clavier,
          textCapitalization: capitalisation,
          inputFormatters: formateurs,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: libelle,
            prefixIcon: Icon(icone, size: 19),
          ),
        ),
      );
}

class _BarreValidation extends StatelessWidget {
  final bool enCours;
  final VoidCallback onValider;

  const _BarreValidation({required this.enCours, required this.onValider});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: enCours ? null : onValider,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: enCours
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.3, color: Colors.white),
                )
              : Text(
                  l10n.commonSave,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}
