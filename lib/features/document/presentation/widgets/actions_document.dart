import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/document.dart';
import '../pages/document_viewer_page.dart';

// Les trois gestes possibles sur un fichier de la médiathèque :
//   - VOIR : dans l'application quand elle sait l'afficher (PDF, photo) —
//     rien n'est enregistré sur le téléphone ; sinon, l'application du
//     téléphone qui sait le lire (lecteur vidéo, Word, visionneuse DWG…) ;
//   - TÉLÉCHARGER : copie durable, à l'emplacement choisi par l'utilisateur ;
//   - OUVRIR AVEC : l'application du téléphone, même pour un PDF — pour
//     l'annoter, l'imprimer ou le partager.

/// « Voir » : aperçu intégré si possible, application du téléphone sinon.
Future<void> voirDocument(BuildContext context, ChantierDocument document) async {
  if (document.apercuIntegre) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DocumentViewerPage(document: document)),
    );
    return;
  }
  await ouvrirDocumentAvec(context, document);
}

/// Ouverture dans l'application système.
///
/// `/uploads/*` exige le jeton d'authentification : un lien direct confié au
/// navigateur système répondrait 401. Les octets transitent donc par le Dio
/// applicatif, sont écrits dans un dossier temporaire, puis confiés à
/// l'application système capable de les lire — voir [OuvertureFichier].
///
/// Un indicateur modal couvre l'attente : sur un chantier, un PDF de plusieurs
/// mégaoctets en 3G prend plusieurs secondes, et un écran qui ne réagit pas
/// donne l'impression que le tap n'a pas été pris en compte.
Future<void> ouvrirDocumentAvec(BuildContext context, ChantierDocument document) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final progression = ValueNotifier<double?>(null);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DialogueAttente(texte: l10n.documentOuvertureEnCours, progression: progression),
  );

  final resultat = await sl<OuvertureFichier>().ouvrir(
    url: document.fichierUrl,
    nomFichier: document.nomFichier,
    onProgression: (valeur) => progression.value = valeur,
  );

  navigator.pop(); // referme l'indicateur
  if (!context.mounted) return;

  resultat.fold(
    (failure) => AppAlert.error(context, title: document.nomFichier, message: failure.errorMessage),
    (issue) {
      // Fichier bien téléchargé mais illisible par l'appareil (un DWG sur un
      // téléphone nu) : ce n'est pas une panne réseau, le message doit le dire.
      if (issue == ResultatOuverture.aucuneApplication) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.documentAucuneApplication)));
      }
    },
  );
}

/// « Télécharger » : récupère le fichier puis propose de l'enregistrer.
Future<void> telechargerDocument(BuildContext context, ChantierDocument document) async {
  final l10n = context.l10n;
  final navigator = Navigator.of(context, rootNavigator: true);
  final progression = ValueNotifier<double?>(null);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DialogueAttente(texte: l10n.documentTelechargementEnCours, progression: progression),
  );

  final resultat = await sl<OuvertureFichier>().telecharger(
    url: document.fichierUrl,
    onProgression: (valeur) => progression.value = valeur,
  );

  // L'indicateur se referme AVANT la boîte « Enregistrer sous » du système,
  // qui s'ouvre par-dessus l'application.
  navigator.pop();
  if (!context.mounted) return;

  await resultat.fold(
    (failure) => AppAlert.error(context, title: document.nomFichier, message: failure.errorMessage),
    (octets) => enregistrerSurAppareil(context, octets: octets, nomFichier: document.nomFichier),
  );
}

/// Enregistre des octets déjà chargés sur l'appareil — depuis l'aperçu, sans
/// second téléchargement. Une annulation dans la boîte du système ne produit
/// aucun message.
Future<void> enregistrerSurAppareil(
  BuildContext context, {
  required Uint8List octets,
  required String nomFichier,
}) async {
  final l10n = context.l10n;
  final resultat = await sl<OuvertureFichier>().enregistrer(octets: octets, nomFichier: nomFichier);
  if (!context.mounted) return;

  await resultat.fold(
    (_) => AppAlert.error(context, title: nomFichier, message: l10n.documentEnregistrementEchec),
    (enregistre) async {
      if (enregistre) await AppAlert.success(context, message: l10n.documentEnregistre);
    },
  );
}

enum _ActionDocument { voir, telecharger, ouvrirAvec, supprimer }

/// Menu des actions d'un fichier — bouton « ⋮ » ou appui long.
///
/// [onSupprimer] ajoute l'entrée « Supprimer » — nul quand le rôle ne le
/// permet pas, l'entrée n'apparaît alors pas. La confirmation revient à
/// l'appelant, qui sait ce qu'il supprime.
Future<void> afficherActionsDocument(
  BuildContext context,
  ChantierDocument document, {
  Future<void> Function()? onSupprimer,
}) async {
  final l10n = context.l10n;

  final action = await showModalBottomSheet<_ActionDocument>(
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
              document.nomFichier,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_outlined, color: AppColors.primary),
            title: Text(l10n.documentActionVoir),
            onTap: () => Navigator.of(sheetContext).pop(_ActionDocument.voir),
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded, color: AppColors.primary),
            title: Text(l10n.documentActionTelecharger),
            onTap: () => Navigator.of(sheetContext).pop(_ActionDocument.telecharger),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded, color: AppColors.primary),
            title: Text(l10n.documentActionOuvrirAvec),
            onTap: () => Navigator.of(sheetContext).pop(_ActionDocument.ouvrirAvec),
          ),
          if (onSupprimer != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: Text(l10n.commonDelete, style: const TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.of(sheetContext).pop(_ActionDocument.supprimer),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (action == null || !context.mounted) return;
  switch (action) {
    case _ActionDocument.voir:
      await voirDocument(context, document);
    case _ActionDocument.telecharger:
      await telechargerDocument(context, document);
    case _ActionDocument.ouvrirAvec:
      await ouvrirDocumentAvec(context, document);
    case _ActionDocument.supprimer:
      await onSupprimer?.call();
  }
}

/// Indicateur d'attente pendant un téléchargement, avec le pourcentage reçu
/// quand le serveur annonce la taille du fichier.
class DialogueAttente extends StatelessWidget {
  final String texte;
  final ValueListenable<double?>? progression;

  const DialogueAttente({super.key, required this.texte, this.progression});

  @override
  Widget build(BuildContext context) {
    final suivi = progression;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: suivi == null
            ? _contenu(null)
            : ValueListenableBuilder<double?>(
                valueListenable: suivi,
                builder: (_, valeur, _) => _contenu(valeur),
              ),
      ),
    );
  }

  Widget _contenu(double? valeur) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(value: valeur, strokeWidth: 2.4, color: AppColors.primary),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            valeur == null ? texte : '$texte ${(valeur * 100).round()} %',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
