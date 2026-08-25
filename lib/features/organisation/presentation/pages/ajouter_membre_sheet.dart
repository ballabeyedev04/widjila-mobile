import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../cubit/membres_cubit.dart';
import '../cubit/membres_state.dart';

final _regexEmail = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
);
final _regexTelephone = RegExp(r'^\+?[0-9\s\-\.]{7,20}$');

// ── Bornes MIROIR du schéma serveur ──────────────────────────────────────────
// `backend/src/modules/organisation/validation/organisation.validation.js`
// (`ajouterMembreSchema`) et `backend/src/validations/common.js`.
//
// Les reproduire ici n'est pas de la duplication décorative : sans elles, un
// nom de 60 caractères passe la validation locale, part sur le réseau, et
// revient en 422 avec un message générique — l'utilisateur ne sait alors pas
// QUEL champ est en cause. Bloquer la saisie au bon plafond rend l'erreur
// impossible plutôt que d'avoir à l'expliquer.
const int _minNom = 2; // common.js : nom / prenom → min(2)
const int _maxNom = 50; // common.js : nom / prenom → max(50)
const int _maxFonction = 100; // ajouterMembreSchema : fonction → max(100)
const int _maxTelephone = 20; // common.js : motif téléphone → {7,20}
const int _maxMotDePasse = 128; // ajouterMembreSchema : mot_de_passe → max(128)

/// Validation commune à « Prénom » et « Nom » — mêmes bornes côté serveur,
/// donc même règle ici.
String? _validerNom(AppLocalizations l10n, String? valeur) {
  final v = (valeur ?? '').trim();
  if (v.isEmpty) return l10n.commonRequiredField;
  if (v.length < _minNom) return l10n.membreFormChampTropCourt(_minNom);
  if (v.length > _maxNom) return l10n.membreFormChampTropLong(_maxNom);
  return null;
}

/// Rôles proposés à la création — MIROIR de `ROLE_UTILISATEUR` côté backend
/// (`backend/src/validations/common.js`) MOINS `Admin`, réservé au
/// super-admin plateforme et déjà explicitement exclu de [UserRole]
/// (`core/config/user_role.dart`) ainsi que rejeté par
/// `OrganisationService.ajouterMembre` si on tentait de le forcer.
const _rolesProposes = [
  UserRole.chefProjet,
  UserRole.conducteurTravaux,
  UserRole.bureauControle,
  UserRole.maitreOuvrage,
  UserRole.maitreOeuvre,
  UserRole.entreprise,
  UserRole.client,
  UserRole.pilote,
  UserRole.sousTraitant,
];

/// Formulaire d'ajout d'un membre — feuille modale ouverte depuis
/// [MembresListPage]. Réutilise le [MembresCubit] de la page appelante
/// (passé via `BlocProvider.value`), pas d'instance dédiée.
class AjouterMembreSheet extends StatefulWidget {
  const AjouterMembreSheet({super.key});

  @override
  State<AjouterMembreSheet> createState() => _AjouterMembreSheetState();
}

class _AjouterMembreSheetState extends State<AjouterMembreSheet> {
  final _formKey = GlobalKey<FormState>();
  final _prenomCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _fonctionCtrl = TextEditingController();
  final _motDePasseCtrl = TextEditingController();

  UserRole _role = UserRole.conducteurTravaux;
  bool _motDePasseAuto = true;
  bool _motDePasseVisible = false;
  bool _envoiEnCours = false;

  @override
  void dispose() {
    for (final c in [_prenomCtrl, _nomCtrl, _emailCtrl, _telephoneCtrl, _fonctionCtrl, _motDePasseCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_envoiEnCours) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    _envoiEnCours = true;
    context.read<MembresCubit>().ajouter(
          nom: _nomCtrl.text.trim(),
          prenom: _prenomCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          role: _role,
          telephone: _telephoneCtrl.text.trim().isEmpty ? null : _telephoneCtrl.text.trim(),
          fonction: _fonctionCtrl.text.trim().isEmpty ? null : _fonctionCtrl.text.trim(),
          motDePasse: _motDePasseAuto || _motDePasseCtrl.text.isEmpty ? null : _motDePasseCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocListener<MembresCubit, MembresState>(
      listenWhen: (a, b) => a.soumissionStatus != b.soumissionStatus,
      listener: (context, state) {
        if (state.soumissionStatus == SoumissionStatus.erreur) {
          _envoiEnCours = false;
          AppAlert.error(context, message: state.soumissionErreur ?? l10n.commonUneErreurSurvenue);
        } else if (state.soumissionStatus == SoumissionStatus.succes) {
          // La confirmation (mot de passe temporaire éventuel) est affichée
          // par la page liste, qui écoute `dernierAjout` — ici, la feuille
          // se contente de se refermer.
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.membreFormTitre,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
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
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        children: [
                          _TitreSection(l10n.membreSectionIdentite, icone: Icons.person_outline_rounded),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _prenomCtrl,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  // Plafond ALIGNÉ sur `prenom` du back
                                  // (`validations/common.js` : min 2, max 50).
                                  // Bloquer la saisie ici évite un refus
                                  // serveur sur une limite invisible à l'écran.
                                  maxLength: _maxNom,
                                  decoration: InputDecoration(
                                    labelText: '${l10n.membreFormPrenom} *',
                                    counterText: '',
                                  ),
                                  validator: (v) => _validerNom(l10n, v),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _nomCtrl,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  maxLength: _maxNom,
                                  decoration: InputDecoration(
                                    labelText: '${l10n.membreFormNom} *',
                                    counterText: '',
                                  ),
                                  validator: (v) => _validerNom(l10n, v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _fonctionCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.next,
                            // `fonction` : max 100 côté back.
                            maxLength: _maxFonction,
                            decoration: InputDecoration(
                              labelText: l10n.membreFormFonction,
                              prefixIcon: const Icon(Icons.work_outline_rounded),
                              counterText: '',
                            ),
                          ),

                          const SizedBox(height: 22),
                          _TitreSection(l10n.membreSectionContact, icone: Icons.alternate_email_rounded),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: '${l10n.membreFormEmail} *',
                              prefixIcon: const Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (v) {
                              final val = (v ?? '').trim();
                              if (val.isEmpty) return l10n.membreFormEmailRequis;
                              return _regexEmail.hasMatch(val) ? null : l10n.membreFormEmailInvalide;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _telephoneCtrl,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            // 20 = plafond du motif `telephone` côté back
                            // (`^\+?[0-9\s\-\.]{7,20}$`).
                            maxLength: _maxTelephone,
                            decoration: InputDecoration(
                              labelText: l10n.membreFormTelephone,
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
                          _TitreSection(l10n.membreSectionAcces, icone: Icons.badge_outlined),
                          DropdownButtonFormField<UserRole>(
                            initialValue: _role,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: '${l10n.membreFormRole} *',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              helperText: l10n.membreFormRoleDescription,
                              helperMaxLines: 3,
                            ),
                            items: [
                              for (final r in _rolesProposes)
                                DropdownMenuItem(
                                  value: r,
                                  child: Row(
                                    children: [
                                      Icon(r.icon, size: 18, color: AppColors.primary),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          r.label(l10n),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 14.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => _role = v ?? _role),
                          ),
                          const SizedBox(height: 14),
                          // Bloc mot de passe encadré : l'interrupteur pilote
                          // l'apparition du champ, les deux se lisent donc
                          // comme UNE décision, pas deux réglages voisins.
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _motDePasseAuto,
                                  onChanged: (v) => setState(() => _motDePasseAuto = v),
                                  activeTrackColor: AppColors.primary,
                                  title: Text(
                                    l10n.membreFormMdpAuto,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    l10n.membreFormMdpAutoDescription,
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                  ),
                                ),
                                // `AnimatedSize` : le champ se déplie au lieu
                                // d'apparaître d'un coup et de faire sauter
                                // tout le formulaire sous lui.
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: _motDePasseAuto
                                      ? const SizedBox(width: double.infinity)
                                      : Padding(
                                          padding: const EdgeInsets.fromLTRB(0, 4, 6, 14),
                                          child: TextFormField(
                                            controller: _motDePasseCtrl,
                                            obscureText: !_motDePasseVisible,
                                            maxLength: _maxMotDePasse,
                                            decoration: InputDecoration(
                                              labelText: l10n.membreFormMdp,
                                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                                              helperText: l10n.membreFormMdpHelper,
                                              helperMaxLines: 2,
                                              counterText: '',
                                              suffixIcon: IconButton(
                                                icon: Icon(_motDePasseVisible
                                                    ? Icons.visibility_off_outlined
                                                    : Icons.visibility_outlined),
                                                onPressed: () =>
                                                    setState(() => _motDePasseVisible = !_motDePasseVisible),
                                              ),
                                            ),
                                            validator: (v) {
                                              if (_motDePasseAuto) return null;
                                              final val = v ?? '';
                                              if (val.isEmpty) return l10n.membreFormMdpRequis;
                                              if (val.length < 8) return l10n.membreFormMdpCourt;
                                              final ok =
                                                  RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(val);
                                              return ok ? null : l10n.membreFormMdpFaible;
                                            },
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.membreFormObligatoiresNote,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 16),
                          BlocBuilder<MembresCubit, MembresState>(
                            builder: (context, state) {
                              final enCours = state.soumissionStatus == SoumissionStatus.enCours;
                              return SizedBox(
                                height: 52,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: enCours ? null : _submit,
                                  child: enCours
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                        )
                                      : Text(l10n.membreFormBouton, style: const TextStyle(fontWeight: FontWeight.w700)),
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

/// Intertitre de section du formulaire.
///
/// Un formulaire de neuf champs présenté d'un bloc se lit comme une corvée
/// indifférenciée. Les regrouper en trois temps — qui est la personne, comment
/// la joindre, ce qu'elle a le droit de faire — donne un rythme à la saisie et
/// permet de retrouver un champ d'un coup d'œil en cas de correction.
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
              // Interlettrage élargi : à cette taille, c'est ce qui distingue
              // un intertitre d'un libellé de champ en gras.
              letterSpacing: 0.9,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          // Filet qui court jusqu'au bord : sépare visuellement les sections
          // sans ajouter de trait plein, plus lourd sur un fond clair.
          Expanded(
            child: Container(height: 1, color: AppColors.border.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}
