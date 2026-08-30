import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../injection_container.dart';
import '../../../referentiel/domain/entities/type_referentiel.dart';
import '../../../referentiel/presentation/cubit/types_referentiel_cubit.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/partenaire.dart';
import '../cubit/partenaires_cubit.dart';
import 'intervenants_list_page.dart' show iconeTypePartenaire, toneTypePartenaire;

final _regexEmail = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
);
final _regexTelephone = RegExp(r'^\+?[0-9\s\-\.]{7,20}$');

// ── Bornes MIROIR du schéma serveur ──────────────────────────────────────────
// `backend/src/modules/organisation/validation/partenaire.validation.js`
// (`creerPartenaireSchema`).
//
// Les reproduire ici n'est pas de la duplication décorative : sans elles, une
// raison sociale de 250 caractères passe la validation locale, part sur le
// réseau, et revient en 422 avec un message générique — l'utilisateur ne sait
// alors pas QUEL champ est en cause. Bloquer la saisie au bon plafond rend
// l'erreur impossible plutôt que d'avoir à l'expliquer.
const int _minNom = 2; // nom → min(2)
const int _maxNom = 200; // nom → max(200)
const int _maxContact = 150; // contact → max(150)
const int _maxTelephone = 50; // telephone → max(50)
const int _maxAdresse = 500; // adresse → max(500)
const int _maxNotes = 2000; // notes → max(2000)

/// Formulaire d'ajout d'un intervenant — réutilise le [PartenairesCubit] de
/// la page appelante (passé par `BlocProvider.value`).
///
/// Le formulaire envoie exactement les champs de `creerPartenaireSchema` :
/// `nom`, `type` (valeur ENUM brute, pas le libellé traduit), `contact`,
/// `email`, `telephone`, `adresse`, `notes`. Les champs laissés vides sont
/// OMIS du corps de la requête plutôt qu'envoyés à `''` (voir
/// `OrganisationRepositoryImpl.creerPartenaire`).
class AjouterPartenaireSheet extends StatefulWidget {
  const AjouterPartenaireSheet({super.key});

  @override
  State<AjouterPartenaireSheet> createState() => _AjouterPartenaireSheetState();
}

class _AjouterPartenaireSheetState extends State<AjouterPartenaireSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  /// CODE du type choisi, et non une énumération : le référentiel est
  /// administrable, un type ajouté côté web doit être sélectionnable ici.
  ///
  /// Nul tant que le référentiel n'a pas répondu — la première valeur reçue
  /// devient la sélection par défaut. Choisir « sous-traitant » en dur
  /// enverrait ce code même si l'administrateur l'a désactivé.
  String? _typeCode;

  /// Référentiel des types d'intervenant, chargé à l'ouverture de la feuille.
  late final TypesReferentielCubit _typesCubit =
      sl<TypesReferentielCubit>(param1: ReferentielType.intervenant)..charger();

  @override
  void dispose() {
    for (final c in [_nomCtrl, _emailCtrl, _telephoneCtrl, _contactCtrl, _adresseCtrl, _notesCtrl]) {
      c.dispose();
    }
    _typesCubit.close();
    super.dispose();
  }

  String? _valeurOuNull(TextEditingController controleur) {
    final v = controleur.text.trim();
    return v.isEmpty ? null : v;
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    // Sans code, le serveur refuserait la création. Le bouton est déjà
    // désactivé dans ce cas — cette garde couvre la course entre les deux.
    final code = _typeCode;
    if (code == null) return;
    context.read<PartenairesCubit>().ajouter(
          nom: _nomCtrl.text.trim(),
          typeCode: code,
          email: _valeurOuNull(_emailCtrl),
          telephone: _valeurOuNull(_telephoneCtrl),
          contact: _valeurOuNull(_contactCtrl),
          adresse: _valeurOuNull(_adresseCtrl),
          notes: _valeurOuNull(_notesCtrl),
        );
  }

  String? _validerNom(AppLocalizations l10n, String? valeur) {
    final v = (valeur ?? '').trim();
    if (v.isEmpty) return l10n.commonRequiredField;
    if (v.length < _minNom) return l10n.membreFormChampTropCourt(_minNom);
    if (v.length > _maxNom) return l10n.membreFormChampTropLong(_maxNom);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocProvider.value(
      value: _typesCubit,
      // La PREMIÈRE valeur reçue devient la sélection par défaut : choisir
      // « sous-traitant » en dur enverrait ce code même si l'administrateur
      // l'a désactivé ou renommé.
      child: BlocListener<TypesReferentielCubit, TypesReferentielState>(
        listener: (context, etat) {
          if (_typeCode == null && etat.items.isNotEmpty) {
            setState(() => _typeCode = etat.items.first.code);
          }
        },
        child: _corps(context, l10n),
      ),
    );
  }

  Widget _corps(BuildContext context, AppLocalizations l10n) {
    return BlocListener<PartenairesCubit, PartenairesState>(
      listenWhen: (a, b) => a.soumissionStatus != b.soumissionStatus,
      listener: (context, state) {
        if (state.soumissionStatus == SoumissionPartenaireStatus.erreur) {
          AppAlert.error(context, message: state.soumissionErreur ?? l10n.commonUneErreurSurvenue);
        } else if (state.soumissionStatus == SoumissionPartenaireStatus.succes) {
          // Le message de succès est affiché par la page liste.
          Navigator.of(context).pop();
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                  ContenuFormulaire(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primary100,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.add_business_rounded, color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.partenaireFormTitre,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: ContenuFormulaire(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                          children: [
                            _TitreSection(l10n.partenaireSectionIdentite, icone: Icons.business_rounded),
                            TextFormField(
                              controller: _nomCtrl,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              maxLength: _maxNom,
                              decoration: InputDecoration(
                                labelText: '${l10n.partenaireFormNom} *',
                                prefixIcon: const Icon(Icons.business_rounded),
                                helperText: l10n.partenaireFormNomAide,
                                helperMaxLines: 2,
                                counterText: '',
                              ),
                              validator: (v) => _validerNom(l10n, v),
                            ),
                            const SizedBox(height: 18),
                            BlocBuilder<TypesReferentielCubit, TypesReferentielState>(
                              builder: (context, typesState) => _SelecteurType(
                                types: typesState.items,
                                valeur: _typeCode,
                                indisponible: typesState.status == TypesStatus.vide ||
                                    typesState.status == TypesStatus.erreur,
                                onChange: (code) => setState(() => _typeCode = code),
                              ),
                            ),

                            const SizedBox(height: 22),
                            _TitreSection(l10n.partenaireSectionContact, icone: Icons.alternate_email_rounded),
                            TextFormField(
                              controller: _contactCtrl,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              maxLength: _maxContact,
                              decoration: InputDecoration(
                                labelText: l10n.partenaireFormResponsable,
                                prefixIcon: const Icon(Icons.person_outline_rounded),
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: l10n.partenaireFormEmail,
                                prefixIcon: const Icon(Icons.mail_outline_rounded),
                              ),
                              validator: (v) {
                                final val = (v ?? '').trim();
                                // Champ facultatif : vide est valide. Rempli,
                                // il doit passer `Joi.string().email()` côté
                                // serveur — autant le dire tout de suite.
                                if (val.isEmpty) return null;
                                return _regexEmail.hasMatch(val) ? null : l10n.membreFormEmailInvalide;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _telephoneCtrl,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              maxLength: _maxTelephone,
                              decoration: InputDecoration(
                                labelText: l10n.partenaireFormTelephone,
                                prefixIcon: const Icon(Icons.phone_outlined),
                                counterText: '',
                              ),
                              validator: (v) {
                                final val = (v ?? '').trim();
                                if (val.isEmpty) return null;
                                return _regexTelephone.hasMatch(val) ? null : l10n.commonNumeroInvalide;
                              },
                            ),

                            const SizedBox(height: 22),
                            _TitreSection(l10n.partenaireSectionComplement, icone: Icons.notes_rounded),
                            TextFormField(
                              controller: _adresseCtrl,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.next,
                              maxLength: _maxAdresse,
                              decoration: InputDecoration(
                                labelText: l10n.partenaireFormAdresse,
                                prefixIcon: const Icon(Icons.location_on_outlined),
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _notesCtrl,
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: 3,
                              maxLength: _maxNotes,
                              decoration: InputDecoration(
                                labelText: l10n.partenaireFormNotes,
                                helperText: l10n.partenaireFormNotesAide,
                                helperMaxLines: 2,
                                alignLabelWithHint: true,
                                counterText: '',
                              ),
                            ),

                            const SizedBox(height: 18),
                            Text(
                              l10n.membreFormObligatoiresNote,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 16),
                            BlocBuilder<PartenairesCubit, PartenairesState>(
                              builder: (context, state) {
                                final enCours = state.soumissionStatus == SoumissionPartenaireStatus.enCours;
                                return SizedBox(
                                  height: 54,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    // Désactivé tant qu'aucun type n'est
                                    // sélectionnable : sans code, le serveur
                                    // refuserait la création et l'utilisateur
                                    // ne saurait pas pourquoi.
                                    onPressed: (enCours || _typeCode == null) ? null : _submit,
                                    icon: enCours
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                          )
                                        : const Icon(Icons.check_rounded, size: 20),
                                    label: Text(
                                      l10n.partenaireFormBouton,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Choix du type d'intervenant, en pastilles plutôt qu'en liste déroulante.
///
/// Les types tiennent à l'écran : les montrer tous permet de choisir en un
/// geste et, surtout, de VOIR les options — un menu déroulant les cache
/// derrière un tap et laisse le réglage par défaut passer inaperçu, alors
/// qu'il détermine le rôle de l'entreprise sur le chantier.
///
/// La liste vient du RÉFÉRENTIEL administrable et non d'une énumération : un
/// type ajouté côté web doit être sélectionnable ici.
class _SelecteurType extends StatelessWidget {
  final List<TypeReferentiel> types;
  final String? valeur;
  final bool indisponible;
  final ValueChanged<String> onChange;

  const _SelecteurType({
    required this.types,
    required this.valeur,
    required this.indisponible,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text(
            '${l10n.partenaireFormType} *',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in types)
              _PuceType(
                code: t.code,
                // Le NOM vient du référentiel : c'est l'administrateur qui le
                // fixe, y compris pour les types standard qu'il a renommés.
                nom: t.nom,
                selectionne: t.code == valeur,
                onTap: () => onChange(t.code),
              ),
            if (indisponible)
              // Ni liste muette ni écran d'erreur : un message qui dit où
              // agir. Le référentiel se gère depuis l'espace d'administration.
              Text(
                l10n.typesReferentielIndisponible,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 9),
          child: Text(
            l10n.partenaireFormTypeAide,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _PuceType extends StatelessWidget {
  final String code;
  final String nom;
  final bool selectionne;
  final VoidCallback onTap;

  const _PuceType({
    required this.code,
    required this.nom,
    required this.selectionne,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // La pastille sélectionnée prend la teinte du TYPE, pas l'orange
    // générique : elle annonce déjà la couleur qu'aura le badge de la fiche
    // une fois l'intervenant créé.
    //
    // Un type AJOUTÉ par l'administrateur n'a ni teinte ni icône dédiées :
    // `fromString` retombe alors sur la valeur générique, et la pastille
    // reste lisible plutôt que de disparaître.
    final type = PartenaireTypeX.fromString(code);
    final teinte = toneTypePartenaire(type).fg;
    final couleurTexte = selectionne ? Colors.white : AppColors.textSecondary;

    return Material(
      color: selectionne ? teinte : AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selectionne ? teinte : AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconeTypePartenaire(type), size: 15, color: couleurTexte),
              const SizedBox(width: 7),
              Text(
                nom,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: couleurTexte),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Intertitre de section du formulaire.
///
/// Sept champs présentés d'un bloc se lisent comme une corvée indifférenciée.
/// Les regrouper en trois temps — quelle entreprise, comment la joindre, ce
/// qu'il faut savoir en plus — donne un rythme à la saisie et permet de
/// retrouver un champ d'un coup d'œil en cas de correction.
class _TitreSection extends StatelessWidget {
  final String texte;
  final IconData icone;

  const _TitreSection(this.texte, {required this.icone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icone, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            texte.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: AppColors.border.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}
