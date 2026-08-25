import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/offline/file_attente.dart';
import '../../../../core/offline/synchronisation_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../reserve/domain/entities/reserve.dart';

/// Écran « Voir toutes les tâches » — liste TOUTES les actions hors ligne
/// (en attente ET en échec définitif), avec un bouton de reprise individuel
/// par ligne et un bouton « Synchroniser tout » en tête de page.
///
/// Accessible depuis le bandeau rouge ([BandeauConnexion]) quand des tâches
/// nécessitent une intervention manuelle, et réutilise le chrome partagé
/// ([EnTeteListe], [ContenuCentre], [EmptyState], [PrimaryButton]) pour
/// rester visuellement jumelle des autres écrans de liste.
class TachesSynchronisationPage extends StatefulWidget {
  const TachesSynchronisationPage({super.key});

  @override
  State<TachesSynchronisationPage> createState() => _TachesSynchronisationPageState();
}

class _TachesSynchronisationPageState extends State<TachesSynchronisationPage> {
  final FileAttente _file = sl<FileAttente>();
  final SynchronisationService _service = sl<SynchronisationService>();

  List<ActionEnAttente> _taches = [];
  bool _chargement = true;

  /// Identifiants en cours d'envoi individuel — empêche un second appui sur
  /// la même ligne pendant que la première requête est en vol.
  final Set<String> _enCoursIndividuel = {};
  bool _synchroToutEnCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
    // Une synchronisation automatique peut vider la file PENDANT que
    // l'utilisateur a cet écran ouvert (reconnexion en tâche de fond) : on
    // rafraîchit la liste à chaque changement de statut plutôt que de la
    // figer au premier chargement.
    _service.statut.addListener(_charger);
  }

  @override
  void dispose() {
    _service.statut.removeListener(_charger);
    super.dispose();
  }

  Future<void> _charger() async {
    final taches = await _file.toutesLesTaches();
    if (!mounted) return;
    setState(() {
      _taches = taches;
      _chargement = false;
    });
  }

  Future<void> _synchroniserUne(String id) async {
    setState(() => _enCoursIndividuel.add(id));

    final succes = await _service.synchroniserUne(id);
    final tache = succes ? null : await _file.parId(id);
    await _charger();

    if (!mounted) return;
    setState(() => _enCoursIndividuel.remove(id));

    if (succes) {
      await AppAlert.success(context, message: context.l10n.syncTacheSuccesMessage);
    } else {
      await AppAlert.error(
        context,
        message: tache?.derniereErreur ?? context.l10n.syncTacheEchecMessage,
      );
    }
  }

  Future<void> _synchroniserTout() async {
    setState(() => _synchroToutEnCours = true);

    final toutSynchronise = await _service.synchroniserTout();
    await _charger();

    if (!mounted) return;
    setState(() => _synchroToutEnCours = false);

    if (toutSynchronise) {
      await AppAlert.success(context, message: context.l10n.syncToutSuccesMessage);
    } else {
      await AppAlert.error(context, message: context.l10n.syncToutPartielMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ContenuCentre(
              child: EnTeteListe(titre: l10n.syncPageTitre, avecRetour: true, avecCloche: false),
            ),
            if (_taches.isNotEmpty)
              ContenuCentre(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: l10n.syncBoutonTout,
                      icon: Icons.sync_rounded,
                      enCours: _synchroToutEnCours,
                      onPressed: _synchroToutEnCours ? null : _synchroniserTout,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _chargement
                  ? const LoadingList()
                  : _taches.isEmpty
                      ? EtatVideIllustre(
                          motif: MotifVide.synchronisation,
                          titre: l10n.syncEtatVideTitre,
                          description: l10n.syncEtatVideSousTitre,
                        )
                      : _Liste(
                          taches: _taches,
                          enCours: _enCoursIndividuel,
                          onSynchroniser: _synchroniserUne,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Libellé du TYPE d'opération — décision de présentation, la file
/// d'attente (`core/offline/file_attente.dart`) reste une brique de données
/// pure sans dépendance Flutter (voir son commentaire de classe).
String _typeLibelle(AppLocalizations l10n, TypeAction type) => switch (type) {
      TypeAction.creerReserve => l10n.syncTypeCreerReserve,
      TypeAction.changerStatutReserve => l10n.syncTypeChangerStatut,
      TypeAction.ajouterPhotoReserve => l10n.syncTypeAjouterPhoto,
    };

/// « Nom de la tâche » — plus parlant que le seul type d'opération : une
/// réserve porte son titre, un changement de statut affiche le nouveau statut
/// visé. Toujours une chaîne non vide, même si le champ attendu manque de la
/// charge (ne devrait pas arriver, mais un titre absent ne doit jamais
/// transformer une ligne de liste en texte vide affiché à l'écran).
String _nomAffiche(AppLocalizations l10n, ActionEnAttente tache) {
  switch (tache.type) {
    case TypeAction.creerReserve:
      final titre = tache.charge['titre'] as String?;
      return (titre != null && titre.isNotEmpty) ? titre : l10n.syncNomNouvelleReserve;
    case TypeAction.changerStatutReserve:
      final statutBrut = tache.charge['statut'] as String?;
      if (statutBrut == null) return l10n.syncTypeChangerStatut;
      final statutLabel = ReserveStatutX.fromString(statutBrut).label(l10n);
      return l10n.syncNomChangerStatut(statutLabel);
    case TypeAction.ajouterPhotoReserve:
      return l10n.syncNomPhoto;
  }
}

class _Liste extends StatelessWidget {
  final List<ActionEnAttente> taches;
  final Set<String> enCours;
  final ValueChanged<String> onSynchroniser;

  const _Liste({required this.taches, required this.enCours, required this.onSynchroniser});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: ContenuCentre(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: taches.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final tache = taches[i];
            return _TacheCard(
              tache: tache,
              enCours: enCours.contains(tache.id),
              onSynchroniser: () => onSynchroniser(tache.id),
            );
          },
        ),
      ),
    );
  }
}

class _TacheCard extends StatelessWidget {
  final ActionEnAttente tache;
  final bool enCours;
  final VoidCallback onSynchroniser;

  const _TacheCard({required this.tache, required this.enCours, required this.onSynchroniser});

  /// 🟠 En attente / 🔄 Synchronisation… / 🔴 Échec — l'état 🟢 « Synchronisée »
  /// n'apparaît jamais ici : une tâche réussie est retirée de la file et
  /// disparaît donc de cette liste au rafraîchissement qui suit son envoi.
  (BadgeTone, String) _statut(AppLocalizations l10n) {
    if (enCours) return (BadgeTone.info, l10n.syncStatutEnCours);
    if (tache.estDefinitivementEnEchec) return (BadgeTone.danger, l10n.syncStatutEchec);
    return (BadgeTone.warning, l10n.syncStatutEnAttente);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (tone, label) = _statut(l10n);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _nomAffiche(l10n, tache),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(label: label, tone: tone),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_typeLibelle(l10n, tache.type)} · ${DateFormat('dd/MM/yyyy à HH:mm').format(tache.creeLe)}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          if (tache.derniereErreur != null) ...[
            const SizedBox(height: 8),
            Text(
              tache.derniereErreur!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: l10n.syncBoutonUne,
              icon: Icons.sync_rounded,
              enCours: enCours,
              onPressed: enCours ? null : onSynchroniser,
            ),
          ),
        ],
      ),
    );
  }
}
