import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/fiche_chrome.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve.dart';
import '../cubit/reserve_detail_cubit.dart';
import '../cubit/reserve_detail_state.dart';

// ── Bornes MIROIR de `modifierReserveSchema` ─────────────────────────────────
// `backend/src/modules/reserve/validation/reserve.validation.js`
const int _minTitre = 2;
const int _maxTitre = 200;
const int _maxDescription = 5000;

/// Modification d'une réserve.
///
/// Jusqu'ici on pouvait créer une réserve mais jamais la corriger : une faute
/// de frappe dans le titre ou une échéance erronée restaient définitives, alors
/// que `PUT /reserves/:id` existe depuis toujours côté serveur.
Future<void> ouvrirModificationReserve(BuildContext context, Reserve reserve) {
  final cubit = context.read<ReserveDetailCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _ModifierReserveSheet(reserve: reserve),
    ),
  );
}

class _ModifierReserveSheet extends StatefulWidget {
  final Reserve reserve;
  const _ModifierReserveSheet({required this.reserve});

  @override
  State<_ModifierReserveSheet> createState() => _ModifierReserveSheetState();
}

class _ModifierReserveSheetState extends State<_ModifierReserveSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _titreCtrl = TextEditingController(text: widget.reserve.titre);
  late final _descriptionCtrl = TextEditingController(text: widget.reserve.description ?? '');

  late ReserveSeverite _severite = widget.reserve.severite;
  late ReserveCategorie _categorie = widget.reserve.categorie;
  late DateTime? _dateLimite = widget.reserve.dateLimite;

  @override
  void dispose() {
    _titreCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirEcheance() async {
    final maintenant = DateTime.now();
    final choix = await showDatePicker(
      context: context,
      initialDate: _dateLimite ?? maintenant,
      // Une échéance dans le passé reste possible : on corrige parfois une
      // réserve ancienne dont la date était mal saisie.
      firstDate: DateTime(maintenant.year - 2),
      lastDate: DateTime(maintenant.year + 5),
    );
    if (choix != null && mounted) setState(() => _dateLimite = choix);
  }

  /// `null` si la valeur n'a pas bougé — le champ est alors omis de la
  /// requête, ce qui évite d'écraser une valeur modifiée entre-temps depuis
  /// l'admin web.
  String? _siModifie(String saisie, String? origine) {
    final valeur = saisie.trim();
    return valeur == (origine ?? '').trim() ? null : valeur;
  }

  Future<void> _soumettre() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final cubit = context.read<ReserveDetailCubit>();
    final l10n = context.l10n;
    final r = widget.reserve;

    final titre = _siModifie(_titreCtrl.text, r.titre);
    final description = _siModifie(_descriptionCtrl.text, r.description);
    final severite = _severite == r.severite ? null : _severite;
    final categorie = _categorie == r.categorie ? null : _categorie;
    final echeance = _dateLimite == r.dateLimite ? null : _dateLimite;

    if (titre == null && description == null && severite == null && categorie == null && echeance == null) {
      Navigator.of(context).pop();
      return;
    }

    final ok = await cubit.modifier(
      titre: titre,
      description: description,
      severite: severite,
      categorie: categorie,
      dateLimite: echeance,
    );
    if (!mounted || !context.mounted) return;

    if (ok) {
      Navigator.of(context).pop();
      AppAlert.success(context, message: l10n.reserveModifieeMessage);
    } else {
      AppAlert.error(context, message: cubit.state.erreur ?? l10n.commonUneErreurSurvenue);
    }
  }

  String? _validerTitre(AppLocalizations l10n, String? valeur) {
    final v = (valeur ?? '').trim();
    if (v.isEmpty) return l10n.commonRequiredField;
    if (v.length < _minTitre) return l10n.membreFormChampTropCourt(_minTitre);
    if (v.length > _maxTitre) return l10n.membreFormChampTropLong(_maxTitre);
    return null;
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
                            l10n.reserveModifierTitre,
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
                          TitreSectionFiche(l10n.wizardEtapeInformations, icone: Icons.notes_rounded),
                          TextFormField(
                            controller: _titreCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            maxLength: _maxTitre,
                            decoration: InputDecoration(
                              labelText: l10n.wizardChampTitre,
                              counterText: '',
                            ),
                            validator: (v) => _validerTitre(l10n, v),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _descriptionCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            maxLines: 4,
                            maxLength: _maxDescription,
                            decoration: InputDecoration(
                              labelText: l10n.commonDescription,
                              alignLabelWithHint: true,
                              counterText: '',
                            ),
                          ),

                          const SizedBox(height: 22),
                          TitreSectionFiche(l10n.wizardChampPriorite, icone: Icons.flag_outlined),
                          _PucesSeverite(
                            valeur: _severite,
                            onChange: (v) => setState(() => _severite = v),
                          ),

                          const SizedBox(height: 22),
                          TitreSectionFiche(l10n.wizardChampCategorie, icone: Icons.category_outlined),
                          DropdownButtonFormField<ReserveCategorie>(
                            initialValue: _categorie,
                            isExpanded: true,
                            decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined)),
                            items: [
                              for (final c in ReserveCategorie.values)
                                DropdownMenuItem(value: c, child: Text(c.label(l10n))),
                            ],
                            onChanged: (v) => setState(() => _categorie = v ?? _categorie),
                          ),

                          const SizedBox(height: 22),
                          TitreSectionFiche(l10n.reserveChampEcheance, icone: Icons.event_outlined),
                          _ChampEcheance(
                            date: _dateLimite,
                            onChoisir: _choisirEcheance,
                            // Effacer l'échéance n'est PAS possible : le
                            // serveur ignore un `date_limite` vide, on ne
                            // propose donc pas une action sans effet.
                          ),

                          const SizedBox(height: 24),
                          BlocBuilder<ReserveDetailCubit, ReserveDetailState>(
                            buildWhen: (a, b) => a.actionEnCours != b.actionEnCours,
                            builder: (context, state) {
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
                                  onPressed: state.actionEnCours ? null : _soumettre,
                                  icon: state.actionEnCours
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.check_rounded, size: 20),
                                  label: Text(
                                    l10n.commonSave,
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
    );
  }
}

/// Sévérité en pastilles colorées plutôt qu'en liste déroulante : les quatre
/// valeurs tiennent à l'écran, et la couleur porte l'information aussi vite
/// que le mot.
class _PucesSeverite extends StatelessWidget {
  final ReserveSeverite valeur;
  final ValueChanged<ReserveSeverite> onChange;

  const _PucesSeverite({required this.valeur, required this.onChange});

  Color _couleur(ReserveSeverite s) => switch (s) {
        ReserveSeverite.critique => AppColors.danger,
        ReserveSeverite.haute => AppColors.warning,
        ReserveSeverite.moyenne => AppColors.info,
        ReserveSeverite.faible => AppColors.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in ReserveSeverite.values)
          Builder(
            builder: (context) {
              final actif = s == valeur;
              final teinte = _couleur(s);
              return Material(
                color: actif ? teinte : AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onChange(s),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: actif ? teinte : AppColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text(
                      s.label(l10n),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: actif ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ChampEcheance extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onChoisir;

  const _ChampEcheance({required this.date, required this.onChoisir});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vide = date == null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onChoisir,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.event_outlined, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  vide ? l10n.reserveEcheanceAucune : DateFormat('dd/MM/yyyy').format(date!),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: vide ? AppColors.textMuted : AppColors.textPrimary,
                    fontStyle: vide ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              const Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
