import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/network/forcer_reseau.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/fiche_chrome.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../cubit/structure_chantier_cubit.dart';
import '../cubit/structure_chantier_state.dart';

/// Structure d'un chantier — bâtiments, niveaux, appartements.
///
/// La section était annoncée « Prochainement » sur la fiche chantier alors
/// que toutes les routes existaient côté serveur (création, renommage,
/// suppression à chaque niveau). Lecture pour tous ; modification pour le
/// groupe OPERATIONNEL, comme sur le serveur (`chantier.route.js`).
class StructureChantierPage extends StatelessWidget {
  final String chantierId;
  const StructureChantierPage({super.key, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<StructureChantierCubit>(param1: chantierId)..charger(),
      child: const _VueStructure(),
    );
  }
}

class _VueStructure extends StatelessWidget {
  const _VueStructure();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Miroir de `requireRole(...OPERATIONNEL)` sur toutes les routes de
    // structure : les autres rôles consultent sans se voir proposer un geste
    // que le serveur refuserait.
    final peutGerer = context.select((AuthBloc b) => b.state.utilisateur?.role.estOperationnel ?? false);

    return BlocBuilder<StructureChantierCubit, StructureChantierState>(
      builder: (context, state) {
        final avecBatiments = state.structure?.batiments.isNotEmpty ?? false;
        return Scaffold(
          backgroundColor: AppColors.surface,
          floatingActionButton: peutGerer && avecBatiments && state.status == StructureStatus.succes
              ? FloatingActionButton.extended(
                  onPressed: state.actionEnCours ? null : () => _ajouterBatiment(context),
                  backgroundColor: state.actionEnCours ? AppColors.textMuted : AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  icon: const Icon(Icons.add_home_work_outlined),
                  label: Text(l10n.structureAjouterBatiment, style: const TextStyle(fontWeight: FontWeight.w700)),
                )
              : null,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(titre: l10n.chantierSectionStructure, avecRetour: true, avecCloche: false),
                ),
                if (state.actionEnCours) const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
                Expanded(child: _corps(context, state, peutGerer)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _corps(BuildContext context, StructureChantierState state, bool peutGerer) {
    final l10n = context.l10n;
    final cubit = context.read<StructureChantierCubit>();

    switch (state.status) {
      case StructureStatus.chargement:
        return const LoadingList();
      case StructureStatus.erreur:
        return ErrorView(message: state.erreur ?? l10n.commonErrorUnknown, onRetry: cubit.charger);
      case StructureStatus.succes:
        final structure = state.structure!;
        if (structure.batiments.isEmpty) {
          return EtatVideIllustre(
            motif: MotifVide.chantier,
            titre: l10n.structureAucunBatiment,
            description: l10n.structureAucunBatimentDescription,
            cta: peutGerer
                ? BoutonAction(
                    icon: Icons.add_home_work_outlined,
                    label: l10n.structureAjouterBatiment,
                    enCours: state.actionEnCours,
                    onTap: () => _ajouterBatiment(context),
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                children: [
                  for (final batiment in structure.batiments) ...[
                    _CarteBatiment(batiment: batiment, peutGerer: peutGerer),
                    const SizedBox(height: 12),
                  ],
                  if (structure.lots.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TitreSectionFiche(l10n.structureLots, icone: Icons.view_module_outlined),
                    CarteFiche(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final lot in structure.lots)
                            Chip(label: Text(lot.nom), backgroundColor: AppColors.neutralBg),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
    }
  }
}

// ═══════════════════════════════ CARTES ═══════════════════════════════════

class _CarteBatiment extends StatelessWidget {
  final BatimentStructure batiment;
  final bool peutGerer;
  const _CarteBatiment({required this.batiment, required this.peutGerer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final niveaux = batiment.etages;
    final appartements = niveaux.fold<int>(0, (total, e) => total + e.zones.length);

    // Sous-sols du plus proche au plus profond (SS1 puis SS2), étages du bas
    // vers le haut : l'ordre dans lequel on parcourt un bâtiment.
    final sousSols = niveaux.where((e) => e.typeNiveau == TypeNiveau.sousSol).toList()
      ..sort((a, b) => b.niveau.compareTo(a.niveau));
    final etages = niveaux.where((e) => e.typeNiveau == TypeNiveau.etage).toList()
      ..sort((a, b) => a.niveau.compareTo(b.niveau));
    final toitures = niveaux.where((e) => e.typeNiveau == TypeNiveau.toiture).toList()
      ..sort((a, b) => a.niveau.compareTo(b.niveau));

    final groupes = [
      (l10n.structureSousSols, sousSols),
      (l10n.structureEtages, etages),
      (l10n.structureToiture, toitures),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          leading: _pastille(Icons.apartment_rounded),
          title: Text(
            batiment.nom,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          subtitle: Text(
            l10n.structureResume(niveaux.length, appartements),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          trailing: peutGerer
              ? _MenuElement(actions: [
                  _ActionMenu(
                    icone: Icons.layers_outlined,
                    libelle: l10n.structureAjouterNiveau,
                    onSelected: () => _ajouterNiveau(context, batiment),
                  ),
                  _ActionMenu(
                    icone: Icons.edit_outlined,
                    libelle: l10n.structureRenommer,
                    onSelected: () => _renommer(
                      context,
                      libelle: l10n.structureNomBatiment,
                      actuel: batiment.nom,
                      action: (cubit, nom) => cubit.renommerBatiment(batiment.id, nom),
                    ),
                  ),
                  _ActionMenu(
                    icone: Icons.delete_outline_rounded,
                    libelle: l10n.commonDelete,
                    danger: true,
                    onSelected: () => _supprimer(
                      context,
                      nom: batiment.nom,
                      action: (cubit) => cubit.retirerBatiment(batiment.id),
                    ),
                  ),
                ])
              : null,
          children: [
            if (niveaux.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l10n.structureAucunNiveau, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ),
            for (final (titre, liste) in groupes)
              if (liste.isNotEmpty) ...[
                _TitreGroupe(titre),
                for (final etage in liste)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _LigneNiveau(batiment: batiment, etage: etage, peutGerer: peutGerer),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

class _LigneNiveau extends StatelessWidget {
  final BatimentStructure batiment;
  final EtageStructure etage;
  final bool peutGerer;
  const _LigneNiveau({required this.batiment, required this.etage, required this.peutGerer});

  String get _libelle {
    final code = etage.codeNiveau;
    return code != null && code.isNotEmpty && code != etage.nom ? '${etage.nom} · $code' : etage.nom;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _libelle,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              if (peutGerer)
                _MenuElement(actions: [
                  _ActionMenu(
                    icone: Icons.door_front_door_outlined,
                    libelle: l10n.structureAjouterAppartement,
                    onSelected: () => _ajouterAppartement(context, batiment, etage),
                  ),
                  _ActionMenu(
                    icone: Icons.edit_outlined,
                    libelle: l10n.structureRenommer,
                    onSelected: () => _renommer(
                      context,
                      libelle: l10n.structureNomNiveau,
                      actuel: etage.nom,
                      action: (cubit, nom) => cubit.renommerNiveau(batiment.id, etage.id, nom),
                    ),
                  ),
                  _ActionMenu(
                    icone: Icons.delete_outline_rounded,
                    libelle: l10n.commonDelete,
                    danger: true,
                    onSelected: () => _supprimer(
                      context,
                      nom: etage.nom,
                      action: (cubit) => cubit.retirerNiveau(batiment.id, etage.id),
                    ),
                  ),
                ])
              else
                const SizedBox(height: 40),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 2, 8, 0),
            child: etage.zones.isEmpty
                ? Text(l10n.structureAucunAppartement, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final zone in etage.zones)
                        _PuceAppartement(batiment: batiment, etage: etage, zone: zone, peutGerer: peutGerer),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PuceAppartement extends StatelessWidget {
  final BatimentStructure batiment;
  final EtageStructure etage;
  final ZoneStructure zone;
  final bool peutGerer;
  const _PuceAppartement({required this.batiment, required this.etage, required this.zone, required this.peutGerer});

  @override
  Widget build(BuildContext context) {
    const avatar = Icon(Icons.door_front_door_outlined, size: 16, color: AppColors.primary);
    const bord = BorderSide(color: AppColors.border);
    if (!peutGerer) {
      return Chip(avatar: avatar, label: Text(zone.nom), backgroundColor: Colors.white, side: bord);
    }
    return ActionChip(
      avatar: avatar,
      label: Text(zone.nom),
      backgroundColor: Colors.white,
      side: bord,
      onPressed: () => _actionsAppartement(context, batiment, etage, zone),
    );
  }
}

class _TitreGroupe extends StatelessWidget {
  final String titre;
  const _TitreGroupe(this.titre);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 0, 6),
      child: Text(
        titre.toUpperCase(),
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textMuted),
      ),
    );
  }
}

Widget _pastille(IconData icone) => Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: AppColors.primary100, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Icon(icone, color: AppColors.primary, size: 21),
    );

class _ActionMenu {
  final IconData icone;
  final String libelle;
  final bool danger;
  final VoidCallback onSelected;
  const _ActionMenu({required this.icone, required this.libelle, required this.onSelected, this.danger = false});
}

class _MenuElement extends StatelessWidget {
  final List<_ActionMenu> actions;
  const _MenuElement({required this.actions});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (i) => actions[i].onSelected(),
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(
              children: [
                Icon(actions[i].icone, size: 19, color: actions[i].danger ? AppColors.danger : AppColors.textSecondary),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    actions[i].libelle,
                    style: actions[i].danger ? const TextStyle(color: AppColors.danger) : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════ GESTES ═══════════════════════════════════

/// Lance une modification et en rend compte : l'erreur du serveur telle
/// quelle (« des réserves y sont rattachées »), ou une confirmation discrète.
Future<void> _executer(
  BuildContext context,
  Future<String?> Function(StructureChantierCubit cubit) action,
) async {
  final cubit = context.read<StructureChantierCubit>();
  if (cubit.state.actionEnCours) return;
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  final erreur = await action(cubit);
  if (!context.mounted) return;
  if (erreur != null) {
    AppAlert.error(context, message: erreur);
  } else {
    messenger.showSnackBar(SnackBar(content: Text(l10n.structureEnregistre)));
  }
}

Future<void> _ajouterBatiment(BuildContext context) async {
  final l10n = context.l10n;
  final nom = await _saisirNom(context, titre: l10n.structureAjouterBatiment, libelle: l10n.structureNomBatiment);
  if (nom == null || !context.mounted) return;
  await _executer(context, (cubit) => cubit.ajouterBatiment(nom));
}

Future<void> _ajouterNiveau(BuildContext context, BatimentStructure batiment) async {
  final saisie = await showDialog<({String nom, TypeNiveau type})>(
    context: context,
    builder: (_) => const _DialogueNiveau(),
  );
  if (saisie == null || !context.mounted) return;
  await _executer(context, (cubit) => cubit.ajouterNiveau(batiment.id, nom: saisie.nom, type: saisie.type));
}

Future<void> _ajouterAppartement(BuildContext context, BatimentStructure batiment, EtageStructure etage) async {
  final l10n = context.l10n;
  final nom = await _saisirNom(context, titre: l10n.structureAjouterAppartement, libelle: l10n.structureNomAppartement);
  if (nom == null || !context.mounted) return;
  await _executer(context, (cubit) => cubit.ajouterAppartement(batiment.id, etage.id, nom));
}

Future<void> _renommer(
  BuildContext context, {
  required String libelle,
  required String actuel,
  required Future<String?> Function(StructureChantierCubit cubit, String nom) action,
}) async {
  final nom = await _saisirNom(context, titre: context.l10n.structureRenommer, libelle: libelle, initial: actuel);
  if (nom == null || nom == actuel || !context.mounted) return;
  await _executer(context, (cubit) => action(cubit, nom));
}

Future<void> _supprimer(
  BuildContext context, {
  required String nom,
  required Future<String?> Function(StructureChantierCubit cubit) action,
}) async {
  final l10n = context.l10n;
  final confirme = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(l10n.commonSupprimerNom(nom)),
      content: Text(
        l10n.structureSupprimerTexte,
        style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.commonDelete),
        ),
      ],
    ),
  );
  if (confirme != true || !context.mounted) return;
  await _executer(context, action);
}

Future<void> _actionsAppartement(
  BuildContext context,
  BatimentStructure batiment,
  EtageStructure etage,
  ZoneStructure zone,
) async {
  final l10n = context.l10n;
  final choix = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(
              zone.nom,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: AppColors.primary),
            title: Text(l10n.structureRenommer),
            onTap: () => Navigator.of(sheetContext).pop('renommer'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            title: Text(l10n.commonDelete, style: const TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.of(sheetContext).pop('supprimer'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choix == null || !context.mounted) return;

  if (choix == 'renommer') {
    await _renommer(
      context,
      libelle: l10n.structureNomAppartement,
      actuel: zone.nom,
      action: (cubit, nom) => cubit.renommerAppartement(batiment.id, etage.id, zone.id, nom),
    );
  } else {
    await _supprimer(
      context,
      nom: zone.nom,
      action: (cubit) => cubit.retirerAppartement(batiment.id, etage.id, zone.id),
    );
  }
}

Future<String?> _saisirNom(
  BuildContext context, {
  required String titre,
  required String libelle,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogueNom(titre: titre, libelle: libelle, initial: initial),
  );
}

// ═══════════════════════════════ DIALOGUES ════════════════════════════════

/// Saisie d'un nom — le contrôleur appartient au dialogue, et disparaît avec
/// lui, animation de fermeture comprise.
class _DialogueNom extends StatefulWidget {
  final String titre;
  final String libelle;
  final String initial;
  const _DialogueNom({required this.titre, required this.libelle, this.initial = ''});

  @override
  State<_DialogueNom> createState() => _DialogueNomState();
}

class _DialogueNomState extends State<_DialogueNom> {
  late final TextEditingController _controleur = TextEditingController(text: widget.initial);
  final _cle = GlobalKey<FormState>();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _valider() {
    if (_cle.currentState?.validate() ?? false) Navigator.of(context).pop(_controleur.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.titre),
      content: Form(
        key: _cle,
        child: TextFormField(
          controller: _controleur,
          autofocus: true,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.libelle),
          validator: (v) => (v == null || v.trim().isEmpty) ? l10n.structureNomRequis : null,
          onFieldSubmitted: (_) => _valider(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: _valider,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

/// Nouveau niveau : sa NATURE (sous-sol, étage, toiture) et son nom. La cote
/// est déduite par le cubit, voir `StructureChantierCubit.coteSuivante`.
class _DialogueNiveau extends StatefulWidget {
  const _DialogueNiveau();

  @override
  State<_DialogueNiveau> createState() => _DialogueNiveauState();
}

class _DialogueNiveauState extends State<_DialogueNiveau> {
  final _controleur = TextEditingController();
  final _cle = GlobalKey<FormState>();
  TypeNiveau _type = TypeNiveau.etage;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _valider() {
    if (_cle.currentState?.validate() ?? false) {
      Navigator.of(context).pop((nom: _controleur.text.trim(), type: _type));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(l10n.structureAjouterNiveau),
      content: Form(
        key: _cle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<TypeNiveau>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: TypeNiveau.sousSol, label: Text(l10n.structureTypeSousSol)),
                ButtonSegment(value: TypeNiveau.etage, label: Text(l10n.structureTypeEtage)),
                ButtonSegment(value: TypeNiveau.toiture, label: Text(l10n.structureTypeToiture)),
              ],
              selected: {_type},
              onSelectionChanged: (choix) => setState(() => _type = choix.first),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _controleur,
              autofocus: true,
              maxLength: 100,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: l10n.structureNomNiveau),
              validator: (v) => (v == null || v.trim().isEmpty) ? l10n.structureNomRequis : null,
              onFieldSubmitted: (_) => _valider(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: _valider,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
