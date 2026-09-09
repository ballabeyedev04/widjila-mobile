import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/envoi_rapport.dart';
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
    // Diffuser un rapport à des tiers engage l'organisation : même garde que
    // la génération côté serveur (`PILOTAGE`). Le serveur tranche, l'écran ne
    // fait qu'éviter de proposer un geste qui sera refusé.
    final role = context.select((AuthBloc b) => b.state.utilisateur?.role);
    final peutEnvoyer = role?.peutPiloter ?? false;

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
          itemBuilder: (_, index) => _CarteRapport(
            rapport: state.items[index],
            peutEnvoyer: peutEnvoyer,
          ),
        ),
      ),
    );
  }
}

class _CarteRapport extends StatelessWidget {
  final Rapport rapport;
  final bool peutEnvoyer;
  const _CarteRapport({required this.rapport, required this.peutEnvoyer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _ouvrirFichier,
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
              if (!peutEnvoyer)
                const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textMuted)
              else
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textMuted),
                  onSelected: (choix) {
                    if (choix == 'apercu') {
                      _ouvrirFichier();
                    } else {
                      _ouvrirEnvoi(context);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'apercu',
                      child: Row(
                        children: [
                          const Icon(Icons.visibility_outlined, size: 18, color: AppColors.textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(l10n.rapportPrevisualiser, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'envoi',
                      child: Row(
                        children: [
                          const Icon(Icons.mail_outline_rounded, size: 18, color: AppColors.textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(l10n.rapportEnvoyerMail, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ouvrirFichier() => sl<OuvertureFichier>().ouvrir(
        url: rapport.fichierUrl,
        nomFichier: 'rapport-${rapport.type.raw}.pdf',
      );

  void _ouvrirEnvoi(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FeuilleEnvoi(rapportId: rapport.id),
    );
  }

  static String _formaterDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Vérification AVANT envoi.
///
/// Le client a été explicite : « ne pas envoyer automatiquement le mail sans
/// validation de l'utilisateur ». Cette feuille montre exactement ce qui
/// partira — entreprise en destinataire, clients du chantier en copie, objet,
/// message, pièce jointe — et n'envoie qu'au appui sur « Envoyer ».
///
/// Les adresses viennent du SERVEUR et ne sont pas saisissables : on peut en
/// décocher, jamais en ajouter. Accepter une adresse libre ferait de la route
/// un relais capable d'expédier un document interne n'importe où.
class _FeuilleEnvoi extends StatefulWidget {
  final String rapportId;
  const _FeuilleEnvoi({required this.rapportId});

  @override
  State<_FeuilleEnvoi> createState() => _FeuilleEnvoiState();
}

class _FeuilleEnvoiState extends State<_FeuilleEnvoi> {
  EnvoiRapport? _envoi;
  String? _erreur;
  bool _chargement = true;
  bool _envoiEnCours = false;

  /// Adresses décochées — transmises telles quelles au serveur, qui retire.
  final Set<String> _exclues = <String>{};

  @override
  void initState() {
    super.initState();
    _preparer();
  }

  Future<void> _preparer() async {
    final resultat = await sl<PreparerEnvoiRapport>()(widget.rapportId);
    if (!mounted) return;
    setState(() {
      _chargement = false;
      resultat.fold(
        (echec) => _erreur = echec.errorMessage,
        (envoi) => _envoi = envoi,
      );
    });
  }

  Future<void> _envoyer() async {
    setState(() => _envoiEnCours = true);
    final resultat = await sl<EnvoyerRapport>()(
      widget.rapportId,
      exclure: _exclues.toList(),
    );
    if (!mounted) return;

    final l10n = context.l10n;
    resultat.fold(
      (echec) {
        setState(() {
          _envoiEnCours = false;
          _erreur = echec.errorMessage;
        });
      },
      (message) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message.isEmpty ? l10n.rapportEnvoiReussi : message)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final envoi = _envoi;

    // Un envoi sans destinataire principal n'a pas de sens : le rapport
    // s'adresse à l'entreprise qui doit lever les réserves.
    final peutEnvoyer = envoi != null &&
        envoi.destinatairesJoignables.any((d) => !_exclues.contains(d.email));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
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
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.rapportEnvoiTitre,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (_chargement)
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    l10n.rapportEnvoiPreparation,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                )
              else if (envoi == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Text(
                    _erreur ?? l10n.commonError,
                    style: const TextStyle(fontSize: 13, color: AppColors.danger),
                  ),
                )
              else
                Flexible(child: _corps(envoi, l10n)),
              if (envoi != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (peutEnvoyer && !_envoiEnCours) ? _envoyer : null,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _envoiEnCours ? l10n.rapportEnvoiEnCours : l10n.rapportEnvoiConfirmer,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _corps(EnvoiRapport envoi, AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _liste(
            titre: l10n.rapportEnvoiDestinataires,
            vide: l10n.rapportEnvoiAucunDestinataire,
            entrees: envoi.destinatairesJoignables,
            aide: l10n.rapportEnvoiDecocher,
          ),
          const SizedBox(height: 14),
          _liste(
            titre: l10n.rapportEnvoiCopies,
            vide: l10n.rapportEnvoiAucuneCopie,
            entrees: envoi.copiesJoignables,
            aide: null,
          ),
          if (envoi.sansEmail.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.rapportEnvoiSansEmail(envoi.sansEmail.join(', ')),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _bloc(l10n.rapportEnvoiObjet, envoi.objet),
          const SizedBox(height: 12),
          _bloc(l10n.rapportEnvoiPieceJointe, envoi.pieceJointeNom),
          const SizedBox(height: 12),
          Text(
            envoi.message,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.rapportEnvoiAvertissement,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(
              _erreur!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bloc(String titre, String valeur) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
          ),
          const SizedBox(height: 3),
          Text(valeur, style: const TextStyle(fontSize: 13.5)),
        ],
      );

  Widget _liste({
    required String titre,
    required String vide,
    required List<DestinataireRapport> entrees,
    required String? aide,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
        ),
        if (entrees.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(vide, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          )
        else ...[
          for (final e in entrees)
            CheckboxListTile(
              value: !_exclues.contains(e.email),
              onChanged: (coche) => setState(() {
                if (coche == true) {
                  _exclues.remove(e.email);
                } else {
                  _exclues.add(e.email!);
                }
              }),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(e.nom, style: const TextStyle(fontSize: 13.5)),
              subtitle: Text(
                e.email!,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          if (aide != null)
            Text(aide, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ],
      ],
    );
  }
}
