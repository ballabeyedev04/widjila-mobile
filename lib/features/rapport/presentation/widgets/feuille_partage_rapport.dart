// `show Either` : dartz exporte aussi un `State`, qui masquerait celui de
// Flutter dans ce widget à état.
import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/suivi_rapport.dart';

typedef CreerLienPartage = Future<Either<Failure, LienPartageRapport>> Function({
  int? expireDansJours,
  bool authentificationRequise,
});

/// Partage par LIEN SÉCURISÉ — § 14 du cahier des charges.
///
/// L'utilisateur choisit la durée de validité (« éventuellement limité dans
/// le temps ») et s'il faut exiger une connexion (« éventuellement protégé
/// par authentification »). Le lien créé n'est affiché qu'UNE fois : le
/// serveur n'en garde que l'empreinte et ne pourra plus le redonner.
class FeuillePartageRapport extends StatefulWidget {
  final CreerLienPartage creer;
  const FeuillePartageRapport({super.key, required this.creer});

  @override
  State<FeuillePartageRapport> createState() => _FeuillePartageRapportState();
}

class _FeuillePartageRapportState extends State<FeuillePartageRapport> {
  /// `null` : sans limite.
  int? _jours = 30;
  bool _authentification = false;
  bool _enCours = false;
  String? _erreur;
  LienPartageRapport? _lien;

  Future<void> _creer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.creer(expireDansJours: _jours, authentificationRequise: _authentification);
    if (!mounted) return;
    setState(() {
      _enCours = false;
      resultat.fold((f) => _erreur = f.errorMessage, (lien) => _lien = lien);
    });
  }

  Future<void> _copier(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.rapportPartageCopie)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lien = _lien;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rapportPartageTitre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (lien == null) ...[
              Text(
                l10n.rapportPartageDuree,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (jours, libelle) in [
                    (7, l10n.rapportPartage7j),
                    (30, l10n.rapportPartage30j),
                    (null, l10n.rapportPartageIllimite),
                  ])
                    ChoiceChip(
                      label: Text(libelle),
                      selected: _jours == jours,
                      onSelected: (_) => setState(() => _jours = jours),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _authentification,
                onChanged: (v) => setState(() => _authentification = v),
                title: Text(l10n.rapportPartageAuth, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  l10n.rapportPartageAuthAide,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_erreur!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _enCours ? null : _creer,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: Text(l10n.rapportPartageCreer),
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(lien.url, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.rapportPartageUneFois,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _copier(lien.url),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(l10n.rapportPartageCopier),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
