import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/inspection.dart';
import '../cubit/inspections_list_cubit.dart';
import '../cubit/inspections_list_state.dart';

/// Feuille de planification d'une visite : type, date, points à contrôler.
///
/// La checklist est saisie ICI plutôt qu'après création : sur le terrain, on
/// sait ce qu'on vient vérifier avant d'arriver, et le back accepte les
/// libellés dès la création (`creerInspectionSchema.checklist`). Créer d'abord
/// puis ajouter les points un par un demanderait autant d'allers-retours
/// réseau que de points.
class PlanifierInspectionSheet extends StatefulWidget {
  const PlanifierInspectionSheet({super.key});

  @override
  State<PlanifierInspectionSheet> createState() => _PlanifierInspectionSheetState();
}

class _PlanifierInspectionSheetState extends State<PlanifierInspectionSheet> {
  InspectionType _type = InspectionType.inspection;
  DateTime? _date;

  /// Un contrôleur par ligne — le texte doit survivre au réordonnancement
  /// provoqué par la suppression d'une ligne du milieu.
  final List<TextEditingController> _points = [TextEditingController()];

  @override
  void dispose() {
    for (final c in _points) {
      c.dispose();
    }
    super.dispose();
  }

  void _ajouterPoint() => setState(() => _points.add(TextEditingController()));

  void _retirerPoint(int index) {
    setState(() {
      _points.removeAt(index).dispose();
      // Toujours au moins un champ : une liste vide donnerait un écran sans
      // aucun point d'entrée pour recommencer.
      if (_points.isEmpty) _points.add(TextEditingController());
    });
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final choix = await showDatePicker(
      context: context,
      initialDate: _date ?? maintenant,
      // Une visite peut être consignée après coup (on saisit au bureau une
      // visite d'hier) : la borne basse remonte donc dans le passé.
      firstDate: DateTime(maintenant.year - 1),
      lastDate: DateTime(maintenant.year + 3),
    );
    if (choix != null) setState(() => _date = choix);
  }

  void _valider() {
    final libelles = _points
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    context.read<InspectionsListCubit>().planifier(
          type: _type,
          dateVisite: _date,
          libellesChecklist: libelles,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      // Remonte la feuille au-dessus du clavier : sans cela, les derniers
      // points de contrôle saisis sont cachés par celui-ci.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.inspectionPlanifier,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: l10n.commonClose,
                  ),
                ],
              ),
            ),

            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                shrinkWrap: true,
                children: [
                  Text(l10n.inspectionTypeChamp, style: _styleLabel),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in InspectionType.values)
                        ChoiceChip(
                          label: Text(type.label(l10n)),
                          selected: _type == type,
                          onSelected: (_) => setState(() => _type = type),
                          selectedColor: AppColors.primary.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _type == type ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  Text(l10n.inspectionDateChamp, style: _styleLabel),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _choisirDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_rounded, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Text(
                            _date != null
                                ? '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}'
                                : l10n.inspectionSansDate,
                            style: TextStyle(
                              fontSize: 14,
                              color: _date != null ? AppColors.textPrimary : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Text(l10n.inspectionPointsChamp, style: _styleLabel),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _points.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _points[i],
                              decoration: InputDecoration(
                                hintText: l10n.inspectionPointPlaceholder,
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              style: const TextStyle(fontSize: 14),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          if (_points.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded,
                                  size: 20, color: AppColors.textMuted),
                              onPressed: () => _retirerPoint(i),
                            ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _ajouterPoint,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(l10n.inspectionAjouterPoint),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: BlocBuilder<InspectionsListCubit, InspectionsListState>(
                buildWhen: (a, b) => a.creationStatus != b.creationStatus,
                builder: (context, state) {
                  final enCours = state.creationStatus == CreationInspectionStatus.enCours;
                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: enCours ? null : _valider,
                      child: enCours
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              l10n.inspectionPlanifier,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _styleLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
}
