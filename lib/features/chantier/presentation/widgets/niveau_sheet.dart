import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../cubit/depot_plans_cubit.dart';

/// Extensions acceptées — les mêmes que le reste du parcours.
const _extensions = ['pdf', 'png', 'jpg', 'jpeg', 'dwg', 'dxf'];

/// Ce que l'utilisateur a saisi pour un nouveau niveau.
class SaisieNiveau {
  final String code;
  final String? description;
  final String? cheminFichier;
  final String? nomFichier;

  const SaisieNiveau({
    required this.code,
    this.description,
    this.cheminFichier,
    this.nomFichier,
  });
}

/// Formulaire d'ajout d'un niveau — le « + » d'une section.
///
/// Trois choses, comme demandé par le client : un CODE choisi dans une liste
/// (avec un « + » pour en créer un absent), une DESCRIPTION, et le PLAN à
/// téléverser.
///
/// Le cubit est passé explicitement plutôt que relu du contexte : la feuille
/// s'ouvre dans une autre branche de l'arbre (`showModalBottomSheet` monte sur
/// le `Navigator` racine), où le `BlocProvider` de l'écran n'est pas visible.
Future<SaisieNiveau?> ouvrirFeuilleNiveau(
  BuildContext context, {
  required TypeNiveau type,
  required DepotPlansCubit cubit,
}) {
  return showModalBottomSheet<SaisieNiveau>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _FeuilleNiveau(type: type),
    ),
  );
}

class _FeuilleNiveau extends StatefulWidget {
  final TypeNiveau type;

  const _FeuilleNiveau({required this.type});

  @override
  State<_FeuilleNiveau> createState() => _FeuilleNiveauState();
}

class _FeuilleNiveauState extends State<_FeuilleNiveau> {
  final _description = TextEditingController();
  final _nouveauCode = TextEditingController();

  String? _codeChoisi;
  String? _erreurCode;

  /// Le champ de création est replié par défaut : la liste suffit dans
  /// l'immense majorité des cas, et l'afficher d'emblée inviterait à créer un
  /// doublon de « RDC » plutôt qu'à le chercher.
  bool _creationOuverte = false;
  bool _creationEnCours = false;

  String? _cheminFichier;
  String? _nomFichier;

  @override
  void dispose() {
    _description.dispose();
    _nouveauCode.dispose();
    super.dispose();
  }

  Future<void> _choisirFichier() async {
    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _extensions,
      withData: false,
    );
    final fichier = choix?.files.singleOrNull;
    final chemin = fichier?.path;
    if (fichier == null || chemin == null) return;
    setState(() {
      _cheminFichier = chemin;
      _nomFichier = fichier.name;
    });
  }

  Future<void> _creerCode() async {
    final saisi = _nouveauCode.text.trim();
    if (saisi.isEmpty) return;

    setState(() => _creationEnCours = true);
    final cree = await context.read<DepotPlansCubit>().ajouterCode(
          typeNiveau: widget.type,
          code: saisi,
        );
    if (!mounted) return;

    setState(() {
      _creationEnCours = false;
      if (cree != null) {
        // Le code fraîchement créé est SÉLECTIONNÉ : l'utilisateur vient de le
        // taper pour l'utiliser, le lui faire rechercher dans la liste serait
        // une étape de trop.
        _codeChoisi = cree.code;
        _creationOuverte = false;
        _nouveauCode.clear();
        _erreurCode = null;
      }
    });
  }

  void _valider() {
    if (_codeChoisi == null) {
      setState(() => _erreurCode = context.l10n.depotNiveauCodeRequis);
      return;
    }
    Navigator.of(context).pop(SaisieNiveau(
      code: _codeChoisi!,
      description: _description.text.trim(),
      cheminFichier: _cheminFichier,
      nomFichier: _nomFichier,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<DepotPlansCubit, DepotPlansState>(
      builder: (context, etat) {
        final codes = etat.codesDe(widget.type);

        return Padding(
          // Remonte la feuille au-dessus du clavier : sans cela, le champ de
          // création se retrouve caché au moment précis où on y tape.
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    l10n.depotNiveauTitre,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),

                  // ── Le code ────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _codeChoisi,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.depotNiveauCode,
                            errorText: _erreurCode,
                            prefixIcon: const Icon(Icons.layers_outlined),
                          ),
                          items: [
                            for (final c in codes)
                              DropdownMenuItem(
                                value: c.code,
                                child: Text(c.libelle, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _codeChoisi = v;
                            _erreurCode = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Le « + » demandé par le client : créer un code absent
                      // de la liste, sans quitter la saisie en cours.
                      IconButton.filledTonal(
                        tooltip: l10n.depotNiveauNouveauCode,
                        icon: Icon(_creationOuverte ? Icons.close_rounded : Icons.add_rounded),
                        onPressed: () => setState(() => _creationOuverte = !_creationOuverte),
                      ),
                    ],
                  ),

                  if (_creationOuverte) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nouveauCode,
                            autofocus: true,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: l10n.depotNiveauNouveauCode,
                              helperText: l10n.depotNiveauNouveauCodeAide,
                              helperMaxLines: 2,
                              prefixIcon: const Icon(Icons.tag_rounded),
                            ),
                            onSubmitted: (_) => _creerCode(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _creationEnCours ? null : _creerCode,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: _creationEnCours
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(l10n.depotNiveauCreerCode),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 14),

                  // ── La description ─────────────────────────────────────
                  TextField(
                    controller: _description,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: l10n.depotNiveauDescription,
                      alignLabelWithHint: true,
                      prefixIcon: const Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Le plan ────────────────────────────────────────────
                  Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _choisirFichier,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _nomFichier == null
                                  ? Icons.upload_file_rounded
                                  : Icons.description_rounded,
                              color: _nomFichier == null ? AppColors.textMuted : AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.depotNiveauPlan,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _nomFichier ?? l10n.depotNiveauAucunFichier,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              l10n.depotNiveauChoisirFichier,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _valider,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(l10n.depotNiveauEnregistrer),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
