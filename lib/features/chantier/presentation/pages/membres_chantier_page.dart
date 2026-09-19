import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/forcer_reseau.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/membre_chantier.dart';
import '../cubit/membres_chantier_cubit.dart';
import '../cubit/membres_chantier_state.dart';

/// Membres affectés à un chantier.
///
/// La section était annoncée « Prochainement » sur la fiche chantier. Tout le
/// monde consulte ; affecter et retirer suivent les rôles du serveur
/// (`requireRole('ChefProjet', 'MaitreOeuvre', TITULAIRE)`).
class MembresChantierPage extends StatelessWidget {
  final String chantierId;
  const MembresChantierPage({super.key, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<MembresChantierCubit>(param1: chantierId)..charger(),
      child: const _VueMembres(),
    );
  }
}

class _VueMembres extends StatelessWidget {
  const _VueMembres();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final peutAffecter =
        context.select((AuthBloc b) => b.state.utilisateur?.role.peutAffecterMembresChantier ?? false);

    return BlocBuilder<MembresChantierCubit, MembresChantierState>(
      builder: (context, state) {
        final avecMembres = state.status == MembresChantierStatus.succes && state.membres.isNotEmpty;
        return Scaffold(
          backgroundColor: AppColors.surface,
          floatingActionButton: peutAffecter && avecMembres
              ? FloatingActionButton.extended(
                  onPressed: state.actionEnCours ? null : () => _affecter(context),
                  backgroundColor: state.actionEnCours ? AppColors.textMuted : AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(l10n.membresChantierAffecter, style: const TextStyle(fontWeight: FontWeight.w700)),
                )
              : null,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(titre: l10n.membresChantierTitre, avecRetour: true, avecCloche: false),
                ),
                if (state.actionEnCours) const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
                Expanded(child: _corps(context, state, peutAffecter)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _corps(BuildContext context, MembresChantierState state, bool peutAffecter) {
    final l10n = context.l10n;
    final cubit = context.read<MembresChantierCubit>();

    switch (state.status) {
      case MembresChantierStatus.chargement:
        return const LoadingList();
      case MembresChantierStatus.erreur:
        return ErrorView(message: state.erreur ?? l10n.commonErrorUnknown, onRetry: cubit.charger);
      case MembresChantierStatus.succes:
        if (state.membres.isEmpty) {
          return EtatVideIllustre(
            motif: MotifVide.equipe,
            titre: l10n.membresChantierAucun,
            description: l10n.membresChantierAucunDescription,
            cta: peutAffecter
                ? BoutonAction(
                    icon: Icons.person_add_alt_1_outlined,
                    label: l10n.membresChantierAffecter,
                    enCours: state.actionEnCours,
                    onTap: () => _affecter(context),
                  )
                : null,
          );
        }
        return ColoredBox(
          color: AppColors.background,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: forcerReseau(() => cubit.charger(silencieux: true)),
            child: ContenuCentre(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                itemCount: state.membres.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _LigneMembre(membre: state.membres[i], peutRetirer: peutAffecter),
              ),
            ),
          ),
        );
    }
  }
}

class _LigneMembre extends StatelessWidget {
  final MembreChantier membre;
  final bool peutRetirer;
  const _LigneMembre({required this.membre, required this.peutRetirer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fonction = membre.fonction;
    final sousTitre = [
      membre.role.label(l10n),
      if (fonction != null && fonction.isNotEmpty) fonction,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary100,
            child: Text(
              membre.initiales,
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  membre.nomComplet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(sousTitre, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                if (membre.roleChantier != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.primary100, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      membre.roleChantier!,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                if (membre.email != null && membre.email!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    membre.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (peutRetirer)
            IconButton(
              tooltip: l10n.membresChantierRetirer,
              icon: const Icon(Icons.person_remove_outlined, color: AppColors.danger),
              onPressed: () => _retirer(context, membre),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════ GESTES ═══════════════════════════════════

class _ChoixAffectation {
  final List<String> membreIds;
  final String? roleChantier;
  const _ChoixAffectation(this.membreIds, this.roleChantier);
}

Future<void> _affecter(BuildContext context) async {
  final cubit = context.read<MembresChantierCubit>();
  if (cubit.state.actionEnCours) return;
  final l10n = context.l10n;

  // Le cubit est passé explicitement : la feuille monte sur le Navigator
  // racine, où le BlocProvider de l'écran n'est pas visible.
  final choix = await showModalBottomSheet<_ChoixAffectation>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FeuilleAffectation(cubit: cubit),
  );
  if (choix == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final erreur = await cubit.affecter(choix.membreIds, roleChantier: choix.roleChantier);
  if (!context.mounted) return;
  if (erreur != null) {
    AppAlert.error(context, message: erreur);
  } else {
    AppAlert.confirmation(context, messenger: messenger, message: l10n.membresChantierAffectes);
  }
}

Future<void> _retirer(BuildContext context, MembreChantier membre) async {
  final cubit = context.read<MembresChantierCubit>();
  final l10n = context.l10n;
  final confirme = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(l10n.membresChantierRetirerTitre(membre.nomComplet)),
      content: Text(
        l10n.membresChantierRetirerTexte,
        style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.membresChantierRetirer),
        ),
      ],
    ),
  );
  if (confirme != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final erreur = await cubit.retirer(membre.id);
  if (!context.mounted) return;
  if (erreur != null) {
    AppAlert.error(context, message: erreur);
  } else {
    AppAlert.confirmation(context, messenger: messenger, message: l10n.membresChantierRetire);
  }
}

/// Choix des membres à affecter, avec un rôle sur le chantier facultatif.
class _FeuilleAffectation extends StatefulWidget {
  final MembresChantierCubit cubit;
  const _FeuilleAffectation({required this.cubit});

  @override
  State<_FeuilleAffectation> createState() => _FeuilleAffectationState();
}

class _FeuilleAffectationState extends State<_FeuilleAffectation> {
  late final Future<Either<Failure, List<MembreChantier>>> _candidats = widget.cubit.candidats();
  final Set<String> _choisis = <String>{};
  final _role = TextEditingController();
  String _filtre = '';

  @override
  void dispose() {
    _role.dispose();
    super.dispose();
  }

  void _valider() {
    final role = _role.text.trim();
    Navigator.of(context).pop(_ChoixAffectation(_choisis.toList(), role.isEmpty ? null : role));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hauteurMax = MediaQuery.sizeOf(context).height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: hauteurMax),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ContenuFormulaire(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(99)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    l10n.membresChantierAffecter,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ),
                Flexible(
                  child: FutureBuilder<Either<Failure, List<MembreChantier>>>(
                    future: _candidats,
                    builder: (context, snapshot) {
                      final resultat = snapshot.data;
                      if (resultat == null) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                        );
                      }
                      return resultat.fold(
                        (failure) => Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(failure.errorMessage, style: const TextStyle(color: AppColors.danger)),
                        ),
                        (candidats) => _liste(context, candidats),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _role,
                    maxLength: 50,
                    decoration: InputDecoration(
                      labelText: l10n.membresChantierRoleChantier,
                      hintText: l10n.membresChantierRoleChantierHint,
                      isDense: true,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: FilledButton(
                    onPressed: _choisis.isEmpty ? null : _valider,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(l10n.membresChantierAffecterBouton(_choisis.length)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _liste(BuildContext context, List<MembreChantier> candidats) {
    final l10n = context.l10n;
    if (candidats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l10n.membresChantierAucunCandidat,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
        ),
      );
    }

    final filtres = _filtre.isEmpty
        ? candidats
        : candidats.where((m) => m.nomComplet.toLowerCase().contains(_filtre)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: l10n.equipeRechercheHint,
              isDense: true,
            ),
            onChanged: (v) => setState(() => _filtre = v.trim().toLowerCase()),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final m in filtres)
                CheckboxListTile(
                  value: _choisis.contains(m.id),
                  activeColor: AppColors.primary,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(m.nomComplet, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    m.role.label(l10n),
                    if (m.fonction != null && m.fonction!.isNotEmpty) m.fonction!,
                  ].join(' · ')),
                  onChanged: (coche) => setState(() {
                    if (coche == true) {
                      _choisis.add(m.id);
                    } else {
                      _choisis.remove(m.id);
                    }
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
