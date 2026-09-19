import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/envoi_rapport.dart';
import '../../domain/usecases/rapport_usecases.dart';

/// Ouvre la feuille d'envoi d'un rapport.
Future<void> afficherFeuilleEnvoiRapport(BuildContext context, String rapportId, {VoidCallback? apresEnvoi}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => FeuilleEnvoiRapport(rapportId: rapportId, apresEnvoi: apresEnvoi),
  );
}

/// Vérification AVANT envoi — § 13 du cahier des charges.
///
/// « Après génération, l'utilisateur clique sur Envoyer. Widjila propose les
/// destinataires, l'objet et le message. » Cette feuille montre exactement ce
/// qui partira — entreprises en destinataire, clients en copie, objet,
/// message, pièce jointe ou lien — et n'envoie qu'à l'appui sur « Envoyer ».
///
/// Les adresses viennent du SERVEUR. On peut en décocher, et en ajouter
/// PARMI celles du chantier ; jamais en saisir une libre — le serveur la
/// refuserait (§ 21, validation des destinataires).
class FeuilleEnvoiRapport extends StatefulWidget {
  final String rapportId;
  final VoidCallback? apresEnvoi;
  const FeuilleEnvoiRapport({super.key, required this.rapportId, this.apresEnvoi});

  @override
  State<FeuilleEnvoiRapport> createState() => _FeuilleEnvoiRapportState();
}

class _FeuilleEnvoiRapportState extends State<FeuilleEnvoiRapport> {
  EnvoiRapport? _envoi;
  String? _erreur;
  bool _chargement = true;
  bool _envoiEnCours = false;

  /// Adresses décochées — transmises telles quelles au serveur, qui retire.
  final Set<String> _exclues = <String>{};

  /// Candidats du chantier ajoutés par l'utilisateur.
  final List<DestinataireRapport> _ajoutes = [];

  final _objet = TextEditingController();
  final _message = TextEditingController();
  ModeEnvoiRapport _mode = ModeEnvoiRapport.pieceJointe;

  @override
  void initState() {
    super.initState();
    _preparer();
  }

  @override
  void dispose() {
    _objet.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _preparer() async {
    final resultat = await sl<PreparerEnvoiRapport>()(widget.rapportId);
    if (!mounted) return;
    setState(() {
      _chargement = false;
      resultat.fold(
        (echec) => _erreur = echec.errorMessage,
        (envoi) {
          _envoi = envoi;
          _objet.text = envoi.objet;
          _message.text = envoi.message;
          _mode = envoi.mode;
        },
      );
    });
  }

  /// La demande à transmettre.
  ///
  /// Sans aucune modification, seuls les RETRAITS partent — le serveur
  /// recalcule lui-même les destinataires. Dès que l'utilisateur ajoute
  /// quelqu'un ou retouche l'objet, le message ou la forme, les listes
  /// complètes sont envoyées, et le serveur vérifie chaque adresse.
  DemandeEnvoiRapport _demande(EnvoiRapport envoi) {
    final objetModifie = _objet.text.trim() != envoi.objet.trim();
    final messageModifie = _message.text.trim() != envoi.message.trim();
    final modeModifie = _mode != envoi.mode;

    if (_ajoutes.isEmpty && !objetModifie && !messageModifie && !modeModifie) {
      return DemandeEnvoiRapport(exclure: _exclues.toList());
    }
    return DemandeEnvoiRapport(
      exclure: _exclues.toList(),
      destinataires: [
        ...envoi.destinatairesJoignables.map((d) => d.email!).where((e) => !_exclues.contains(e)),
        ..._ajoutes.map((a) => a.email!),
      ],
      copies: envoi.copiesJoignables.map((c) => c.email!).where((e) => !_exclues.contains(e)).toList(),
      objet: objetModifie ? _objet.text.trim() : null,
      message: messageModifie ? _message.text.trim() : null,
      mode: modeModifie ? _mode : null,
    );
  }

  Future<void> _envoyer() async {
    final envoi = _envoi;
    if (envoi == null) return;
    setState(() => _envoiEnCours = true);
    final resultat = await sl<EnvoyerRapport>()(widget.rapportId, _demande(envoi));
    if (!mounted) return;

    final l10n = context.l10n;
    resultat.fold(
      (echec) => setState(() {
        _envoiEnCours = false;
        _erreur = echec.errorMessage;
      }),
      (issue) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        widget.apresEnvoi?.call();
        if (issue.enFileAttente) {
          // Mis en file d'attente, pas envoyé : un bandeau, sans le son de
          // succès — le serveur n'a encore rien confirmé.
          messenger.showSnackBar(SnackBar(content: Text(l10n.rapportEnvoiHorsLigne)));
        } else {
          AppAlert.confirmation(
            context,
            messenger: messenger,
            message: issue.message.isEmpty ? l10n.rapportEnvoiReussi : issue.message,
          );
        }
      },
    );
  }

  Future<void> _ajouter(EnvoiRapport envoi) async {
    final proposes = envoi.candidatsSupplementaires.where((c) => !_ajoutes.contains(c)).toList();
    if (proposes.isEmpty) return;
    final choisi = await showModalBottomSheet<DestinataireRapport>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (feuille) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in proposes)
              ListTile(
                leading: Icon(
                  c.type == 'membre' ? Icons.person_outline_rounded : Icons.business_outlined,
                  color: AppColors.textMuted,
                ),
                title: Text(c.nom),
                subtitle: Text(c.email!),
                onTap: () => Navigator.of(feuille).pop(c),
              ),
          ],
        ),
      ),
    );
    if (choisi != null && mounted) setState(() => _ajoutes.add(choisi));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final envoi = _envoi;

    // Un envoi sans destinataire principal n'a pas de sens : le rapport
    // s'adresse à l'entreprise qui doit lever les réserves.
    final peutEnvoyer = envoi != null &&
        envoi.genere &&
        (envoi.destinatairesJoignables.any((d) => !_exclues.contains(d.email)) || _ajoutes.isNotEmpty);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(99)),
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
                      label: Text(_envoiEnCours ? l10n.rapportEnvoiEnCours : l10n.rapportEnvoiConfirmer),
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
    final tailleMo = (envoi.taille / (1024 * 1024)).toStringAsFixed(1);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!envoi.genere) ...[
            Text(l10n.rapportEnvoiNonGenere, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
            const SizedBox(height: 12),
          ],
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
          if (_ajoutes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(l10n.rapportEnvoiAjoutes, style: _titre),
            for (final a in _ajoutes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(a.nom, style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(a.email!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _ajoutes.remove(a)),
                ),
              ),
          ],
          if (envoi.candidatsSupplementaires.any((c) => !_ajoutes.contains(c)))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _ajouter(envoi),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(l10n.rapportEnvoiAjouter),
              ),
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
          Text(l10n.rapportEnvoiMode, style: _titre),
          const SizedBox(height: 6),
          SegmentedButton<ModeEnvoiRapport>(
            segments: [
              ButtonSegment(
                value: ModeEnvoiRapport.pieceJointe,
                icon: const Icon(Icons.attach_file_rounded, size: 16),
                label: Text(l10n.rapportEnvoiModePieceJointe, overflow: TextOverflow.ellipsis),
              ),
              ButtonSegment(
                value: ModeEnvoiRapport.lien,
                icon: const Icon(Icons.link_rounded, size: 16),
                label: Text(l10n.rapportEnvoiModeLien, overflow: TextOverflow.ellipsis),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          if (envoi.mode == ModeEnvoiRapport.lien) ...[
            const SizedBox(height: 6),
            Text(
              l10n.rapportEnvoiModeLienConseille(tailleMo),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _objet,
            maxLength: 250,
            decoration: InputDecoration(labelText: l10n.rapportEnvoiObjet, counterText: ''),
          ),
          const SizedBox(height: 12),
          if (_mode == ModeEnvoiRapport.pieceJointe) ...[
            _bloc(l10n.rapportEnvoiPieceJointe, envoi.pieceJointeNom),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 8,
            maxLength: 5000,
            decoration: InputDecoration(labelText: l10n.rapportEnvoiMessage, counterText: ''),
          ),
          const SizedBox(height: 14),
          Text(
            _mode == ModeEnvoiRapport.lien ? l10n.rapportEnvoiAvertissementLien : l10n.rapportEnvoiAvertissement,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(_erreur!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.35)),
          ],
        ],
      ),
    );
  }

  static const _titre = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted);

  Widget _bloc(String titre, String valeur) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: _titre),
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
        Text(titre, style: _titre),
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
              subtitle: Text(e.email!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          if (aide != null) Text(aide, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ],
      ],
    );
  }
}
