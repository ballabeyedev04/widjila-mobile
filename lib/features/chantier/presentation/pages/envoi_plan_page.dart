import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../cubit/envoi_plan_cubit.dart';

/// Extensions acceptées — mêmes que l'import de plan existant, et mêmes que
/// celles vérifiées par le serveur (`upload.validateMagicBytes`).
const _extensionsAcceptees = ['pdf', 'png', 'jpg', 'jpeg', 'dwg', 'dxf'];

/// « Envoi Plan » — décrire un chantier, y joindre ses plans, envoyer.
///
/// Le résultat n'est pas un chantier mais une DEMANDE : le serveur met en
/// attente tout chantier créé par un compte autre que le super-admin
/// plateforme. L'écran le dit avant l'envoi plutôt qu'après, pour qu'aucun
/// utilisateur ne croie son chantier immédiatement ouvert.
class EnvoiPlanPage extends StatelessWidget {
  const EnvoiPlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<EnvoiPlanCubit>(),
      child: const _Formulaire(),
    );
  }
}

class _Formulaire extends StatefulWidget {
  const _Formulaire();

  @override
  State<_Formulaire> createState() => _FormulaireState();
}

class _FormulaireState extends State<_Formulaire> {
  final _cleFormulaire = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  @override
  void dispose() {
    _nomCtrl.dispose();
    _adresseCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirPlan() async {
    final cubit = context.read<EnvoiPlanCubit>();

    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _extensionsAcceptees,
      // Plusieurs plans en une fois : un chantier en compte rarement un seul,
      // et les rouvrir un par un serait pénible sur le terrain.
      allowMultiple: true,
      withData: false,
    );
    if (choix == null) return;

    for (final fichier in choix.files) {
      final chemin = fichier.path;
      if (chemin == null) continue;
      // Le nom du fichier fait office de nom de plan : c'est presque toujours
      // le bon, et il reste modifiable une fois la demande validée.
      cubit.ajouter(PlanAJoindre(chemin: chemin, nom: fichier.name));
    }
  }

  void _envoyer() {
    if (!(_cleFormulaire.currentState?.validate() ?? false)) return;
    context.read<EnvoiPlanCubit>().envoyer(
          nom: _nomCtrl.text.trim(),
          adresse: _adresseCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.envoiPlanTitre),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: BlocConsumer<EnvoiPlanCubit, EnvoiPlanState>(
        listenWhen: (a, b) => a.status != b.status,
        listener: (context, etat) {
          if (etat.status == EnvoiPlanStatus.erreur && etat.erreur != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(etat.erreur!), backgroundColor: AppColors.danger),
            );
          }
          if (etat.status == EnvoiPlanStatus.succes) {
            // Un envoi partiel n'est PAS un échec : la demande existe, et la
            // présenter comme perdue pousserait à la déposer deux fois.
            final message = etat.plansEnEchec.isEmpty
                ? l10n.envoiPlanSucces
                : l10n.envoiPlanEchecPlans;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor:
                    etat.plansEnEchec.isEmpty ? AppColors.success : AppColors.warning,
                duration: const Duration(seconds: 5),
              ),
            );
            // Vers le suivi : la demande y est visible avec son statut, plutôt
            // que de laisser l'utilisateur devant un formulaire déjà envoyé.
            context.pushReplacement(AppRoutes.demandesChantier);
          }
        },
        builder: (context, etat) {
          final envoiEnCours = etat.status == EnvoiPlanStatus.envoi;

          return AbsorbPointer(
            absorbing: envoiEnCours,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  l10n.envoiPlanIntro,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 18),
                Form(
                  key: _cleFormulaire,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nomCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l10n.envoiPlanNomLabel,
                          prefixIcon: const Icon(Icons.apartment_outlined),
                        ),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? l10n.envoiPlanNomRequis : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _adresseCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l10n.envoiPlanAdresseLabel,
                          prefixIcon: const Icon(Icons.place_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _descriptionCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l10n.envoiPlanDescriptionLabel,
                          alignLabelWithHint: true,
                          prefixIcon: const Icon(Icons.notes_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.envoiPlanFichiers,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _choisirPlan,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(l10n.envoiPlanAjouterFichier),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (etat.plans.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      l10n.envoiPlanAucunFichier,
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  )
                else
                  for (final plan in etat.plans)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.description_outlined,
                                size: 20, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                plan.nom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.envoiPlanRetirer,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              color: AppColors.textMuted,
                              onPressed: () => context.read<EnvoiPlanCubit>().retirer(plan),
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: envoiEnCours ? null : _envoyer,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: envoiEnCours
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Text(l10n.envoiPlanEnvoiEnCours),
                          ],
                        )
                      : Text(l10n.envoiPlanEnvoyer),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
