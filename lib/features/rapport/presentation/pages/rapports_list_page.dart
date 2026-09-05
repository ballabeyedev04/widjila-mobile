import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/rapport.dart';
import '../../domain/usecases/rapport_usecases.dart';
import '../cubit/rapports_cubit.dart';
import '../../../../core/network/forcer_reseau.dart';

/// Rapports PDF d'un chantier.
///
/// Le mobile n'a pas vocation à remplacer le web pour la mise en forme : ce
/// qu'on veut ici, c'est CONSULTER un PDF depuis le chantier et le transmettre.
/// La génération est proposée parce que le besoin naît souvent sur place — à
/// la fin d'une visite, quand on veut le PV tout de suite.
class RapportsListPage extends StatelessWidget {
  final String chantierId;
  final String? chantierNom;

  const RapportsListPage({super.key, required this.chantierId, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => RapportsCubit(
        getRapports: sl<GetRapports>(),
        genererRapport: sl<GenererRapport>(),
        supprimerRapport: sl<SupprimerRapport>(),
        chantierId: chantierId,
      )..charger(),
      child: _Vue(chantierNom: chantierNom),
    );
  }
}

class _Vue extends StatelessWidget {
  final String? chantierNom;
  const _Vue({this.chantierNom});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<RapportsCubit, RapportsState>(
          listenWhen: (a, b) => a.generationStatus != b.generationStatus,
          listener: (context, state) {
            final cubit = context.read<RapportsCubit>();
            if (state.generationStatus == GenerationStatus.erreur) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.generationErreur ?? l10n.commonError)),
              );
              cubit.accuserReceptionGeneration();
            } else if (state.generationStatus == GenerationStatus.succes) {
              final rapport = state.dernierGenere;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.rapportGenere),
                  action: rapport == null
                      ? null
                      : SnackBarAction(
                          label: l10n.rapportOuvrir,
                          onPressed: () => _ouvrir(context, rapport),
                        ),
                ),
              );
              cubit.accuserReceptionGeneration();
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(
                    titre: chantierNom ?? l10n.rapportsTitre,
                    avecRetour: true,
                    avecCloche: false,
                  ),
                ),
                Expanded(child: _Corps(state: state)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: Builder(
        builder: (context) => BlocBuilder<RapportsCubit, RapportsState>(
          buildWhen: (a, b) => a.generationStatus != b.generationStatus,
          builder: (context, state) {
            final enCours = state.generationStatus == GenerationStatus.enCours;
            return FloatingActionButton.extended(
              backgroundColor: enCours ? AppColors.textMuted : AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: enCours ? null : () => _choisirType(context),
              icon: enCours
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: Text(enCours ? l10n.rapportGeneration : l10n.rapportGenerer),
            );
          },
        ),
      ),
    );
  }

  static Future<void> _ouvrir(BuildContext context, Rapport rapport) async {
    await sl<OuvertureFichier>().ouvrir(
      url: rapport.fichierUrl,
      nomFichier: 'rapport-${rapport.type.raw}.pdf',
    );
  }

  Future<void> _choisirType(BuildContext context) async {
    final cubit = context.read<RapportsCubit>();
    final l10n = context.l10n;

    final type = await showModalBottomSheet<RapportType>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.rapportTypeChamp,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            for (final t in RapportType.values)
              ListTile(
                leading: const Icon(Icons.description_outlined, color: AppColors.primary),
                title: Text(t.label(l10n), style: const TextStyle(fontSize: 14.5)),
                onTap: () => Navigator.of(sheetContext).pop(t),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                l10n.rapportFige,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );

    if (type != null) cubit.generer(type: type);
  }
}

class _Corps extends StatelessWidget {
  final RapportsState state;
  const _Corps({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RapportsCubit>();

    if (state.status == RapportsStatus.chargement && state.items.isEmpty) {
      return const LoadingList();
    }

    if (state.status == RapportsStatus.erreur && state.items.isEmpty) {
      return ErrorView(message: state.erreur ?? l10n.commonError, onRetry: cubit.charger);
    }

    if (state.items.isEmpty) {
      return EtatVideIllustre(
        motif: MotifVide.document,
        titre: l10n.rapportsAucun,
        description: l10n.rapportsAucunMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: forcerReseau(cubit.charger),
      child: ContenuCentre(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) => _CarteRapport(rapport: state.items[index]),
        ),
      ),
    );
  }
}

class _CarteRapport extends StatelessWidget {
  final Rapport rapport;
  const _CarteRapport({required this.rapport});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => sl<OuvertureFichier>().ouvrir(
          url: rapport.fichierUrl,
          nomFichier: 'rapport-${rapport.type.raw}.pdf',
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded, size: 21, color: AppColors.danger),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Un type inconnu de cette version est affiché tel quel
                      // plutôt que travesti en « Réserves ».
                      rapport.typeInconnu ? rapport.typeBrut : rapport.type.label(l10n),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    if (rapport.createdAt != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _formaterDate(rapport.createdAt!),
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  static String _formaterDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
