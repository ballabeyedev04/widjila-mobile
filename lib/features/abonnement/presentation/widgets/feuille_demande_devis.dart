import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/abonnement.dart';

/// Le formulaire de demande de devis (écran 2 du cahier des charges).
///
/// Tous les champs sont FACULTATIFS. Une entreprise qui ne connaît pas encore
/// son volume exact doit pouvoir nous écrire quand même — c'est l'échange qui
/// précisera, et exiger un chiffre ici ferait abandonner au premier doute.
/// Les coordonnées manquantes sont reprises de l'organisation par le serveur.
///
/// Aucun champ de montant : le client décrit un BESOIN, il ne chiffre pas.
/// Le serveur refuserait d'ailleurs un prix, son schéma n'en comporte aucun.
Future<DemandeDevis?> demanderUnDevis(BuildContext context) {
  return showModalBottomSheet<DemandeDevis>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _FeuilleDemandeDevis(),
  );
}

class _FeuilleDemandeDevis extends StatefulWidget {
  const _FeuilleDemandeDevis();

  @override
  State<_FeuilleDemandeDevis> createState() => _FeuilleDemandeDevisState();
}

class _FeuilleDemandeDevisState extends State<_FeuilleDemandeDevis> {
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _telephone = TextEditingController();
  final _utilisateurs = TextEditingController();
  final _chantiers = TextEditingController();
  final _duree = TextEditingController();
  final _besoins = TextEditingController();

  @override
  void dispose() {
    for (final c in [_contact, _email, _telephone, _utilisateurs, _chantiers, _duree, _besoins]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Un nombre, ou `null` — jamais une chaîne vide, que le serveur refuse.
  int? _nombre(TextEditingController c) {
    final texte = c.text.trim();
    return texte.isEmpty ? null : int.tryParse(texte);
  }

  String? _texte(TextEditingController c) {
    final texte = c.text.trim();
    return texte.isEmpty ? null : texte;
  }

  void _envoyer() {
    Navigator.of(context).pop(DemandeDevis(
      contact: _texte(_contact),
      email: _texte(_email),
      telephone: _texte(_telephone),
      nbUtilisateurs: _nombre(_utilisateurs),
      nbChantiers: _nombre(_chantiers),
      dureeSouhaitee: _nombre(_duree),
      besoins: _texte(_besoins),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      // Le clavier ne doit jamais recouvrir le champ en cours de saisie.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Text(
                l10n.devisFormulaireTitre,
                style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.devisFormulaireSousTitre,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 18),

              _Champ(controleur: _contact, libelle: l10n.devisContact),
              _Champ(controleur: _email, libelle: l10n.devisEmail, clavier: TextInputType.emailAddress),
              _Champ(controleur: _telephone, libelle: l10n.devisTelephone, clavier: TextInputType.phone),
              _Champ(controleur: _utilisateurs, libelle: l10n.devisNbUtilisateurs, nombre: true),
              _Champ(controleur: _chantiers, libelle: l10n.devisNbChantiers, nombre: true),
              _Champ(controleur: _duree, libelle: l10n.devisDureeSouhaitee, nombre: true),
              _Champ(controleur: _besoins, libelle: l10n.devisBesoins, lignes: 4),

              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _envoyer,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: Text(l10n.devisEnvoyerDemande),
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
}

class _Champ extends StatelessWidget {
  final TextEditingController controleur;
  final String libelle;
  final bool nombre;
  final int lignes;
  final TextInputType? clavier;

  const _Champ({
    required this.controleur,
    required this.libelle,
    this.nombre = false,
    this.lignes = 1,
    this.clavier,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controleur,
        maxLines: lignes,
        keyboardType: nombre ? TextInputType.number : clavier,
        // Clavier numérique ET saisie bornée aux chiffres : un volume se
        // compte, et une lettre glissée là ferait refuser toute la demande.
        inputFormatters: nombre ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          labelText: libelle,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
      ),
    );
  }
}
