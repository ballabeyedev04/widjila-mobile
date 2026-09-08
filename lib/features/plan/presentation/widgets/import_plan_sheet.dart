import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/plan.dart';

/// Ce que l'utilisateur renseigne avant l'envoi du fichier.
typedef DetailPlan = ({String nom, PlanFormat format, String? typePlan, DateTime? datePlan});

/// Disciplines proposées à l'import — cahier technique § 4.
///
/// Le document en nomme trois puis écrit « etc. » : la liste est donc une AIDE
/// À LA SAISIE, pas une contrainte. Le champ reste libre côté serveur, et cette
/// liste ne fait qu'éviter d'écrire « Electricité », « électricité » et
/// « ELEC » sur trois plans du même chantier — trois disciplines différentes
/// pour tout filtre.
const disciplinesPlan = <String>[
  'Architecture',
  'Structure',
  'Électricité',
  'Plomberie',
  'CVC',
  'VRD',
  'Sécurité incendie',
];

/// Demande le nom et le format du plan avant l'import.
///
/// Le serveur exige `nom` (2 à 200 caractères) et accepte un `format`
/// facultatif parmi pdf / dwg / ifc — voir `uploadPlanSchema` côté back. Ce
/// format décrit la NATURE du document, indépendamment du fichier réellement
/// envoyé : on peut photographier un plan papier et le déclarer « pdf ».
///
/// Retourne `null` si l'utilisateur renonce.
Future<DetailPlan?> demanderDetailPlan(BuildContext context, {required String nomPropose}) {
  return showModalBottomSheet<DetailPlan>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ImportPlanSheet(nomPropose: nomPropose),
  );
}

class _ImportPlanSheet extends StatefulWidget {
  final String nomPropose;
  const _ImportPlanSheet({required this.nomPropose});

  @override
  State<_ImportPlanSheet> createState() => _ImportPlanSheetState();
}

class _ImportPlanSheetState extends State<_ImportPlanSheet> {
  late final TextEditingController _nom = TextEditingController(text: _sansExtension(widget.nomPropose));
  PlanFormat _format = PlanFormat.pdf;

  /// Discipline du plan (§ 4) — facultative : un chantier de maison
  /// individuelle n'a qu'un jeu de plans et n'a rien à distinguer.
  String? _typePlan;

  /// Date DU PLAN (§ 4), distincte de la date de dépôt.
  ///
  /// Pré-remplie au jour même : c'est le cas le plus fréquent — on verse le
  /// plan qu'on vient de recevoir — et cela évite de laisser le champ vide par
  /// simple lassitude.
  DateTime? _datePlan = DateTime.now();
  String? _erreur;

  /// Le nom proposé vient du fichier : « Niveau R+2.pdf » se lit mieux sans
  /// son extension, que le format ci-dessous porte déjà.
  static String _sansExtension(String nomFichier) {
    final point = nomFichier.lastIndexOf('.');
    if (point <= 0) return nomFichier;
    return nomFichier.substring(0, point);
  }

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  void _valider() {
    final nom = _nom.text.trim();
    // Mêmes bornes que le schéma Joi du serveur : les vérifier ici évite un
    // aller-retour réseau pour une erreur que le formulaire voit tout seul.
    if (nom.length < 2) {
      setState(() => _erreur = context.l10n.planImportSheetErreurCourt);
      return;
    }
    if (nom.length > 200) {
      setState(() => _erreur = context.l10n.planImportSheetErreurLong);
      return;
    }
    Navigator.of(context).pop((
      nom: nom,
      format: _format,
      typePlan: _typePlan,
      datePlan: _datePlan,
    ));
  }

  /// Choisit la date DU PLAN.
  ///
  /// Bornée à un an dans le futur, comme le serveur : un plan daté de 2040 est
  /// une faute de frappe. Vingt ans en arrière, en revanche, est légitime — on
  /// verse encore des plans d'origine sur des chantiers de rénovation.
  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: _datePlan ?? maintenant,
      firstDate: DateTime(maintenant.year - 20),
      lastDate: maintenant.add(const Duration(days: 365)),
    );
    if (choisie != null && mounted) setState(() => _datePlan = choisie);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      // Remonte la feuille au-dessus du clavier : sans ça, le champ de saisie
      // se retrouve caché dès qu'il prend le focus.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: ContenuFormulaire(
            child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.planImporterBouton,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.nomPropose,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.planImportSheetNomLabel,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _nom,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 200,
                  onChanged: (_) {
                    if (_erreur != null) setState(() => _erreur = null);
                  },
                  decoration: InputDecoration(
                    hintText: l10n.planImportSheetNomHint,
                    errorText: _erreur,
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.planImportSheetFormatLabel,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    for (final format in PlanFormat.values) ...[
                      _ChoixFormat(
                        format: format,
                        actif: _format == format,
                        onTap: () => setState(() => _format = format),
                      ),
                      const SizedBox(width: 9),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // TYPE — cahier technique § 4. Deux plans d'un même niveau,
                // l'un architectural et l'autre électrique, étaient sinon
                // indiscernables autrement que par leur nom.
                Text(
                  l10n.planImportSheetTypeLabel,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 7),
                DropdownButtonFormField<String?>(
                  initialValue: _typePlan,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.planImportSheetTypeAucun),
                    ),
                    for (final d in disciplinesPlan)
                      DropdownMenuItem<String?>(value: d, child: Text(d)),
                  ],
                  onChanged: (v) => setState(() => _typePlan = v),
                ),
                const SizedBox(height: 16),

                // DATE DU PLAN — cahier technique § 4. Distincte de la date de
                // dépôt : un plan daté du 3 mars peut être versé en septembre.
                Text(
                  l10n.planImportSheetDateLabel,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 7),
                InkWell(
                  onTap: _choisirDate,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _datePlan == null
                                ? l10n.planImportSheetDateAucune
                                : DateFormat.yMd(Localizations.localeOf(context).toString())
                                    .format(_datePlan!),
                            style: TextStyle(
                              fontSize: 14,
                              color: _datePlan == null ? AppColors.textMuted : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const Icon(Icons.event_outlined, size: 20, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                PrimaryButton(label: l10n.planImportSheetValiderBouton, onPressed: _valider),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel, style: const TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoixFormat extends StatelessWidget {
  final PlanFormat format;
  final bool actif;
  final VoidCallback onTap;

  const _ChoixFormat({required this.format, required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: actif ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: actif ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          format.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: actif ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
