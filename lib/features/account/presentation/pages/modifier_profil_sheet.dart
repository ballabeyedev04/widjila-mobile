import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/fiche_chrome.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../domain/repositories/account_repository.dart';

final _regexTelephone = RegExp(r'^\+?[0-9\s\-\.]{7,20}$');

// ── Bornes MIROIR du schéma serveur ──────────────────────────────────────────
// `backend/src/modules/account/validation/account.validation.js`
// (`updateProfilSchema`) et `backend/src/validations/common.js`.
const int _minNom = 2; // common.js : nom / prenom → min(2)
const int _maxNom = 50; // common.js : nom / prenom → max(50)
const int _maxFonction = 100; // updateProfilSchema : fonction → max(100)
const int _maxTelephone = 20; // common.js : motif téléphone → {7,20}

/// Taille maximale d'une photo de profil — `upload.middleware.js` rejette
/// au-delà avec « Fichier trop volumineux. Taille maximale : 5 MB. ».
/// Refuser ici évite un aller-retour réseau pour rien.
const int _maxOctetsPhoto = 5 * 1024 * 1024;

/// Ouvre le formulaire de modification des informations personnelles.
///
/// La feuille pilote elle-même son envoi plutôt que de passer par un cubit :
/// l'écran Profil n'en a aucun — il lit l'utilisateur directement dans
/// l'[AuthBloc], qui reste le seul détenteur de la session. En créer un pour
/// une action unique aurait ajouté trois fichiers sans rien clarifier.
Future<void> ouvrirModificationProfil(BuildContext context, User utilisateur) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Le bloc est relu depuis le contexte de la page : la feuille est montée
    // par le Navigator racine, hors de l'arbre de l'écran appelant.
    builder: (_) => BlocProvider.value(
      value: context.read<AuthBloc>(),
      child: _ModifierProfilSheet(utilisateur: utilisateur),
    ),
  );
}

class _ModifierProfilSheet extends StatefulWidget {
  final User utilisateur;
  const _ModifierProfilSheet({required this.utilisateur});

  @override
  State<_ModifierProfilSheet> createState() => _ModifierProfilSheetState();
}

class _ModifierProfilSheetState extends State<_ModifierProfilSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _prenomCtrl = TextEditingController(text: widget.utilisateur.prenom);
  late final _nomCtrl = TextEditingController(text: widget.utilisateur.nom);
  late final _telephoneCtrl = TextEditingController(text: widget.utilisateur.telephone ?? '');
  late final _fonctionCtrl = TextEditingController(text: widget.utilisateur.fonction ?? '');

  String? _cheminPhoto;
  bool _envoiEnCours = false;

  @override
  void dispose() {
    for (final c in [_prenomCtrl, _nomCtrl, _telephoneCtrl, _fonctionCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validerNom(AppLocalizations l10n, String? valeur) {
    final v = (valeur ?? '').trim();
    if (v.isEmpty) return l10n.commonRequiredField;
    if (v.length < _minNom) return l10n.membreFormChampTropCourt(_minNom);
    if (v.length > _maxNom) return l10n.membreFormChampTropLong(_maxNom);
    return null;
  }

  Future<void> _choisirPhoto() async {
    final l10n = context.l10n;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
              title: Text(l10n.documentPrendrePhoto),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: Text(l10n.documentChoisirGalerie),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    // `imageQuality` : une photo d'appareil moderne dépasse largement les 5 Mo
    // acceptés par le serveur. La recompresser ici évite de faire échouer un
    // envoi pour une raison que l'utilisateur ne maîtrise pas.
    final fichier = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1024);
    if (fichier == null || !mounted) return;

    final taille = await File(fichier.path).length();
    if (!mounted) return;
    if (taille > _maxOctetsPhoto) {
      AppAlert.error(context, message: context.l10n.profilPhotoTropLourde);
      return;
    }
    setState(() => _cheminPhoto = fichier.path);
  }

  /// `null` si la valeur n'a pas bougé — le champ est alors omis de la
  /// requête. Une chaîne vide, elle, est transmise : c'est ce qui EFFACE un
  /// téléphone ou une fonction côté serveur.
  String? _siModifie(String saisie, String? origine) {
    final valeur = saisie.trim();
    return valeur == (origine ?? '').trim() ? null : valeur;
  }

  Future<void> _soumettre() async {
    if (_envoiEnCours) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final l10n = context.l10n;
    final authBloc = context.read<AuthBloc>();
    final u = widget.utilisateur;

    final nom = _siModifie(_nomCtrl.text, u.nom);
    final prenom = _siModifie(_prenomCtrl.text, u.prenom);
    final telephone = _siModifie(_telephoneCtrl.text, u.telephone);
    final fonction = _siModifie(_fonctionCtrl.text, u.fonction);

    // Rien n'a bougé : on referme sans appeler le serveur. `updateProfilSchema`
    // accepterait un corps vide, mais l'appel n'aurait aucun effet — autant ne
    // pas le faire.
    if (nom == null && prenom == null && telephone == null && fonction == null && _cheminPhoto == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _envoiEnCours = true);
    final result = await sl<AccountRepository>().modifierProfil(
      nom: nom,
      prenom: prenom,
      telephone: telephone,
      fonction: fonction,
      cheminPhoto: _cheminPhoto,
    );
    if (!mounted) return;
    setState(() => _envoiEnCours = false);
    if (!context.mounted) return;

    result.fold(
      (failure) => AppAlert.error(context, message: failure.errorMessage),
      (utilisateur) {
        // L'AuthBloc détient l'utilisateur courant affiché partout (profil,
        // en-têtes, permissions) : sans cet événement, l'écran garderait les
        // anciennes valeurs jusqu'au prochain redémarrage.
        authBloc.add(AuthUserUpdated(utilisateur));
        Navigator.of(context).pop();
        AppAlert.success(context, message: l10n.profilModifieMessage);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
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
                          child: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.profilModifierTitre,
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
                          Center(
                            child: _SelecteurPhoto(
                              initiales: widget.utilisateur.initiales,
                              cheminLocal: _cheminPhoto,
                              onTap: _choisirPhoto,
                            ),
                          ),
                          const SizedBox(height: 22),
                          TitreSectionFiche(l10n.membreSectionIdentite, icone: Icons.person_outline_rounded),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _prenomCtrl,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
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
                            maxLength: _maxFonction,
                            decoration: InputDecoration(
                              labelText: l10n.membreFormFonction,
                              prefixIcon: const Icon(Icons.work_outline_rounded),
                              counterText: '',
                            ),
                          ),

                          const SizedBox(height: 22),
                          TitreSectionFiche(l10n.membreSectionContact, icone: Icons.alternate_email_rounded),
                          TextFormField(
                            controller: _telephoneCtrl,
                            keyboardType: TextInputType.phone,
                            maxLength: _maxTelephone,
                            decoration: InputDecoration(
                              labelText: l10n.membreFormTelephone,
                              prefixIcon: const Icon(Icons.phone_outlined),
                              counterText: '',
                            ),
                            validator: (v) {
                              final val = (v ?? '').trim();
                              if (val.isEmpty) return null; // vider est permis
                              return _regexTelephone.hasMatch(val) ? null : l10n.commonNumeroInvalide;
                            },
                          ),
                          const SizedBox(height: 10),
                          // L'email ne figure PAS dans ce formulaire :
                          // `updateProfilSchema` ne l'accepte pas, et il sert
                          // d'identifiant de connexion — le changer demande une
                          // re-vérification que le back n'expose pas encore.
                          _NoteEmail(email: widget.utilisateur.email, texte: l10n.profilEmailNonModifiable),

                          const SizedBox(height: 18),
                          Text(
                            l10n.membreFormObligatoiresNote,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 54,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: _envoiEnCours ? null : _soumettre,
                              icon: _envoiEnCours
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                    )
                                  : const Icon(Icons.check_rounded, size: 20),
                              label: Text(
                                l10n.commonSave,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                            ),
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
    );
  }
}

/// Avatar cliquable — initiales, ou aperçu LOCAL du fichier choisi.
///
/// L'aperçu vient du disque et non du réseau : la photo n'est pas encore
/// envoyée, et afficher l'ancienne pendant qu'on en a choisi une nouvelle
/// ferait douter que le choix ait été pris en compte.
class _SelecteurPhoto extends StatelessWidget {
  final String initiales;
  final String? cheminLocal;
  final VoidCallback onTap;

  const _SelecteurPhoto({required this.initiales, required this.cheminLocal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.profilChangerPhoto,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.12),
                  image: cheminLocal == null
                      ? null
                      : DecorationImage(image: FileImage(File(cheminLocal!)), fit: BoxFit.cover),
                ),
                alignment: Alignment.center,
                child: cheminLocal != null
                    ? null
                    : Text(
                        initiales,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    border: Border.all(color: AppColors.background, width: 3),
                  ),
                  child: const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEmail extends StatelessWidget {
  final String email;
  final String texte;

  const _NoteEmail({required this.email, required this.texte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.neutralBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mail_outline_rounded, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  texte,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
