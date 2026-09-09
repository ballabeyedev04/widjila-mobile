import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/liste_chrome.dart' show ContenuFormulaire;
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../referentiel/domain/entities/code_appartement.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../cubit/depot_plans_cubit.dart';

/// Extensions acceptées — les mêmes que le reste du parcours.
const _extensions = ['pdf', 'png', 'jpg', 'jpeg', 'dwg', 'dxf'];

/// Extensions qu'on peut RÉELLEMENT prévisualiser comme une image. Un PDF ou
/// un DWG n'a pas de rendu ici — le fichier de niveau s'en contente déjà avec
/// une simple icône — mais une photo de plan, si.
bool _estImageAffichable(String nom) {
  final ext = nom.split('.').last.toLowerCase();
  return ext == 'png' || ext == 'jpg' || ext == 'jpeg';
}

/// Ce que l'utilisateur a saisi pour un nouveau niveau.
class SaisieNiveau {
  final String code;
  final String? description;
  final String? cheminFichier;
  final String? nomFichier;

  /// Les appartements ajoutés dans la MÊME feuille, chacun avec son plan
  /// éventuel — demandé explicitement par le client : pouvoir en ajouter
  /// plusieurs et ne tout enregistrer qu'une fois la saisie terminée.
  final List<SaisieAppartement> appartements;

  const SaisieNiveau({
    required this.code,
    this.description,
    this.cheminFichier,
    this.nomFichier,
    this.appartements = const [],
  });
}

/// Formulaire d'ajout d'un niveau — le « + » d'une section.
///
/// Trois choses, comme demandé par le client : un CODE choisi dans une liste
/// (avec un « + » pour en créer un absent), une DESCRIPTION, et le PLAN à
/// téléverser. Une quatrième s'y ajoute désormais : la liste de ses
/// APPARTEMENTS, chacun avec son propre plan — l'entreprise construit tout
/// l'étage en une seule fois plutôt que de rouvrir un formulaire par
/// logement.
///
/// Le cubit est passé explicitement plutôt que relu du contexte : la feuille
/// s'ouvre dans une autre branche de l'arbre (`showModalBottomSheet` monte sur
/// le `Navigator` racine), où le `BlocProvider` de l'écran n'est pas visible.
Future<SaisieNiveau?> ouvrirFeuilleNiveau(
  BuildContext context, {
  required TypeNiveau type,
  required DepotPlansCubit cubit,
}) {
  return showModalBottomSheet<SaisieNiveau>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _FeuilleNiveau(type: type),
    ),
  );
}

/// Un fichier choisi pour un plan, avec de quoi le prévisualiser.
class _FichierChoisi {
  final String chemin;
  final String nom;
  const _FichierChoisi({required this.chemin, required this.nom});
}

/// Une ligne d'appartement dans la feuille — le code CHOISI dans le
/// référentiel, et son fichier éventuel.
///
/// Vit tant que la feuille est ouverte ; rien ici n'est envoyé avant la
/// validation finale, conformément à la demande du client : « ne sauvegarder
/// le niveau qu'après que l'utilisateur a terminé et validé les appartements
/// et leurs plans ».
///
/// Le code n'est plus un texte libre mais une valeur du référentiel
/// (`codes_appartement`), servie par le serveur — même mécanique que les
/// codes de niveau et les bâtiments.
class _LigneAppartement {
  String? code;
  _FichierChoisi? fichier;
  String? erreur;
}

class _FeuilleNiveau extends StatefulWidget {
  final TypeNiveau type;

  const _FeuilleNiveau({required this.type});

  @override
  State<_FeuilleNiveau> createState() => _FeuilleNiveauState();
}

class _FeuilleNiveauState extends State<_FeuilleNiveau> {
  final _description = TextEditingController();
  final _nouveauCode = TextEditingController();

  /// Champ de création d'un code d'APPARTEMENT — le « + » de chaque ligne.
  final _nouveauCodeAppartement = TextEditingController();

  /// La ligne dont le champ de création est ouvert, s'il y en a une. Une
  /// seule à la fois : deux champs de création ouverts côte à côte ne se
  /// distingueraient pas.
  _LigneAppartement? _ligneEnCreation;
  bool _creationAppartementEnCours = false;

  String? _codeChoisi;
  String? _erreurCode;

  /// Le champ de création est replié par défaut : la liste suffit dans
  /// l'immense majorité des cas, et l'afficher d'emblée inviterait à créer un
  /// doublon de « RDC » plutôt qu'à le chercher.
  bool _creationOuverte = false;
  bool _creationEnCours = false;

  _FichierChoisi? _fichierNiveau;

  /// Les appartements ajoutés jusqu'ici. Une `List` mutable, et non un état
  /// immuable recopié à chaque frappe : chaque ligne porte son PROPRE
  /// contrôleur de texte, qui doit survivre aux reconstructions du widget
  /// parent — sans quoi le curseur sauterait au début à chaque caractère
  /// tapé dans un CHAMP D'UNE AUTRE LIGNE.
  final List<_LigneAppartement> _appartements = [];

  @override
  void dispose() {
    _description.dispose();
    _nouveauCode.dispose();
    _nouveauCodeAppartement.dispose();
    super.dispose();
  }

  Future<void> _choisirFichierNiveau() async {
    final choisi = await _choisirFichier();
    if (choisi == null) return;
    setState(() => _fichierNiveau = choisi);
  }

  Future<_FichierChoisi?> _choisirFichier() async {
    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _extensions,
      withData: false,
    );
    final fichier = choix?.files.singleOrNull;
    final chemin = fichier?.path;
    if (fichier == null || chemin == null) return null;
    return _FichierChoisi(chemin: chemin, nom: fichier.name);
  }

  Future<void> _creerCode() async {
    final saisi = _nouveauCode.text.trim();
    if (saisi.isEmpty) return;

    setState(() => _creationEnCours = true);
    final cree = await context.read<DepotPlansCubit>().ajouterCode(
          typeNiveau: widget.type,
          code: saisi,
        );
    if (!mounted) return;

    setState(() {
      _creationEnCours = false;
      if (cree != null) {
        // Le code fraîchement créé est SÉLECTIONNÉ : l'utilisateur vient de le
        // taper pour l'utiliser, le lui faire rechercher dans la liste serait
        // une étape de trop.
        _codeChoisi = cree.code;
        _creationOuverte = false;
        _nouveauCode.clear();
        _erreurCode = null;
      }
    });
  }

  /// Crée un code d'appartement absent de la liste, et le sélectionne sur la
  /// ligne qui l'a demandé.
  Future<void> _creerCodeAppartement(_LigneAppartement ligne) async {
    final saisi = _nouveauCodeAppartement.text.trim();
    if (saisi.isEmpty) return;

    setState(() => _creationAppartementEnCours = true);
    final cree = await context.read<DepotPlansCubit>().ajouterCodeAppartement(saisi);
    if (!mounted) return;

    setState(() {
      _creationAppartementEnCours = false;
      if (cree != null) {
        // Le code fraîchement créé est SÉLECTIONNÉ : l'utilisateur vient de le
        // taper pour l'utiliser, le lui faire rechercher serait une étape de
        // trop.
        ligne.code = cree.code;
        ligne.erreur = null;
        _ligneEnCreation = null;
        _nouveauCodeAppartement.clear();
      }
    });
  }

  void _ajouterAppartement() {
    setState(() => _appartements.add(_LigneAppartement()));
  }

  void _retirerAppartement(_LigneAppartement ligne) {
    setState(() {
      _appartements.remove(ligne);
      // Plus de contrôleur à libérer : le code vient désormais du référentiel,
      // la ligne ne porte qu'une valeur choisie.
      if (identical(_ligneEnCreation, ligne)) _ligneEnCreation = null;
    });
  }

  Future<void> _choisirFichierAppartement(_LigneAppartement ligne) async {
    final choisi = await _choisirFichier();
    if (choisi == null) return;
    setState(() => ligne.fichier = choisi);
  }

  void _valider() {
    if (_codeChoisi == null) {
      setState(() => _erreurCode = context.l10n.depotNiveauCodeRequis);
      return;
    }

    // Un appartement AJOUTÉ mais SANS code n'a rien à transmettre : plutôt
    // que de l'ignorer silencieusement — l'utilisateur croirait l'avoir
    // enregistré — on bloque et on montre lequel corriger.
    var enErreur = false;
    for (final a in _appartements) {
      final vide = (a.code ?? '').trim().isEmpty;
      if (vide) enErreur = true;
      a.erreur = vide ? context.l10n.depotAppartementCodeRequis : null;
    }
    if (enErreur) {
      setState(() {});
      return;
    }

    Navigator.of(context).pop(SaisieNiveau(
      code: _codeChoisi!,
      description: _description.text.trim(),
      cheminFichier: _fichierNiveau?.chemin,
      nomFichier: _fichierNiveau?.nom,
      appartements: [
        for (final a in _appartements)
          SaisieAppartement(
            code: a.code!.trim(),
            cheminFichier: a.fichier?.chemin,
            nomFichier: a.fichier?.nom,
          ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<DepotPlansCubit, DepotPlansState>(
      builder: (context, etat) {
        final codes = etat.codesDe(widget.type);

        return Padding(
          // Remonte la feuille au-dessus du clavier : sans cela, le champ de
          // création se retrouve caché au moment précis où on y tape.
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          // Sur une tablette, la feuille s'etirait sur toute la largeur : un
          // champ de saisie de pres de 1000 px pour nommer un etage. La borne
          // de 440 px est celle de tous les formulaires de l'application, et
          // reste sans effet sur telephone.
          child: ContenuFormulaire(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              // La feuille peut désormais contenir plusieurs appartements :
              // une hauteur maximale et un défilement INTERNE gardent le
              // titre et le bouton final accessibles, plutôt que de laisser
              // la feuille pousser hors de l'écran.
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    l10n.depotNiveauTitre,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Le code ────────────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _codeChoisi,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: l10n.depotNiveauCode,
                                    errorText: _erreurCode,
                                    prefixIcon: const Icon(Icons.layers_outlined),
                                  ),
                                  items: [
                                    for (final c in codes)
                                      DropdownMenuItem(
                                        value: c.code,
                                        child: Text(c.libelle, overflow: TextOverflow.ellipsis),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _codeChoisi = v;
                                    _erreurCode = null;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Le « + » demandé par le client : créer un code
                              // absent de la liste, sans quitter la saisie en
                              // cours.
                              IconButton.filledTonal(
                                tooltip: l10n.depotNiveauNouveauCode,
                                icon: Icon(_creationOuverte ? Icons.close_rounded : Icons.add_rounded),
                                onPressed: () => setState(() => _creationOuverte = !_creationOuverte),
                              ),
                            ],
                          ),

                          if (_creationOuverte) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _nouveauCode,
                                    autofocus: true,
                                    textCapitalization: TextCapitalization.characters,
                                    decoration: InputDecoration(
                                      labelText: l10n.depotNiveauNouveauCode,
                                      helperText: l10n.depotNiveauNouveauCodeAide,
                                      helperMaxLines: 2,
                                      prefixIcon: const Icon(Icons.tag_rounded),
                                    ),
                                    onSubmitted: (_) => _creerCode(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _creationEnCours ? null : _creerCode,
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                                  child: _creationEnCours
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text(l10n.depotNiveauCreerCode),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 14),

                          // ── La description ─────────────────────────────
                          TextField(
                            controller: _description,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: l10n.depotNiveauDescription,
                              alignLabelWithHint: true,
                              prefixIcon: const Icon(Icons.notes_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── Le plan du niveau ───────────────────────────
                          _CarteFichier(
                            label: l10n.depotNiveauPlan,
                            fichier: _fichierNiveau,
                            onChoisir: _choisirFichierNiveau,
                            onRetirer: () => setState(() => _fichierNiveau = null),
                          ),

                          const SizedBox(height: 22),

                          // ── Les appartements ────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.depotAppartementsTitre,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                    ),
                                    Text(
                                      l10n.depotAppartementsAide,
                                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          for (final ligne in _appartements) ...[
                            _CarteAppartement(
                              ligne: ligne,
                              codes: etat.codesAppartement,
                              onChoisirCode: (v) => setState(() {
                                ligne.code = v;
                                ligne.erreur = null;
                              }),
                              creationOuverte: identical(_ligneEnCreation, ligne),
                              onBasculerCreation: () => setState(() {
                                _ligneEnCreation = identical(_ligneEnCreation, ligne) ? null : ligne;
                                _nouveauCodeAppartement.clear();
                              }),
                              controleurNouveauCode: _nouveauCodeAppartement,
                              creationEnCours: _creationAppartementEnCours,
                              onCreerCode: () => _creerCodeAppartement(ligne),
                              onChoisirFichier: () => _choisirFichierAppartement(ligne),
                              onRetirerFichier: () => setState(() => ligne.fichier = null),
                              onSupprimer: () => _retirerAppartement(ligne),
                            ),
                            const SizedBox(height: 10),
                          ],

                          OutlinedButton.icon(
                            onPressed: _ajouterAppartement,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(l10n.depotAppartementAjouter),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              minimumSize: const Size.fromHeight(44),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _valider,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(l10n.depotNiveauEnregistrer),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Vignette + nom d'un fichier choisi, avec la possibilité de le remplacer ou
/// de le retirer — demandé par le client : « pouvoir modifier ou remplacer
/// une image en cas d'erreur ».
///
/// Une IMAGE (png/jpg/jpeg) est réellement prévisualisée : c'est le fichier
/// même que l'utilisateur vient de choisir, lu depuis le disque. Un PDF ou un
/// DWG n'a pas de rendu ici — l'application ne l'ouvre nulle part sans le
/// serveur — et garde une icône, comme le reste du parcours de dépôt.
class _CarteFichier extends StatelessWidget {
  final String label;
  final _FichierChoisi? fichier;
  final VoidCallback onChoisir;
  final VoidCallback onRetirer;

  const _CarteFichier({
    required this.label,
    required this.fichier,
    required this.onChoisir,
    required this.onRetirer,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final f = fichier;
    final image = f != null && _estImageAffichable(f.nom);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onChoisir,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              // La vignette : l'IMAGE réelle si le format le permet, sinon
              // l'icône générique qui existait déjà.
              // Un APPUI sur la vignette l'ouvre en grand. Le client demande
              // de pouvoir vérifier l'image avant d'enregistrer : 40 points de
              // côté ne suffisent pas à distinguer deux plans d'appartement.
              GestureDetector(
                onTap: image ? () => _ouvrirApercu(context, f.chemin, f.nom) : null,
                child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: image
                    ? Image.file(
                        File(f.chemin),
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        // Un fichier déplacé ou effacé entre le choix et le
                        // rendu ne doit pas faire disparaître la carte —
                        // seulement son aperçu.
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textMuted,
                        ),
                      )
                    : SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          f == null ? Icons.upload_file_rounded : Icons.description_rounded,
                          color: f == null ? AppColors.textMuted : AppColors.primary,
                        ),
                      ),
              ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      f?.nom ?? l10n.depotNiveauAucunFichier,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (f == null)
                Text(
                  l10n.depotNiveauChoisirFichier,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.primary),
                )
              else ...[
                // REMPLACER : rouvre le sélecteur, comme un appui sur la
                // carte — présent aussi en icône pour qui n'a pas deviné que
                // la carte entière est cliquable.
                IconButton(
                  tooltip: l10n.depotFichierRemplacer,
                  icon: const Icon(Icons.sync_alt_rounded, size: 19),
                  color: AppColors.primary,
                  onPressed: onChoisir,
                  visualDensity: VisualDensity.compact,
                ),
                // RETIRER : vide le champ sans en choisir un autre — c'est ce
                // qui manquait pour corriger une erreur sans devoir enchaîner
                // sur un nouveau fichier immédiatement.
                IconButton(
                  tooltip: l10n.depotFichierRetirer,
                  icon: const Icon(Icons.close_rounded, size: 19),
                  color: AppColors.danger,
                  onPressed: onRetirer,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Une ligne d'appartement : son code, son plan, et de quoi le retirer.
class _CarteAppartement extends StatelessWidget {
  final _LigneAppartement ligne;

  /// Le référentiel servi par le serveur — « A001 » à « A015 », plus ce que
  /// l'organisation a ajouté.
  final List<CodeAppartement> codes;

  final ValueChanged<String?> onChoisirCode;
  final bool creationOuverte;
  final VoidCallback onBasculerCreation;
  final TextEditingController controleurNouveauCode;
  final bool creationEnCours;
  final VoidCallback onCreerCode;
  final VoidCallback onChoisirFichier;
  final VoidCallback onRetirerFichier;
  final VoidCallback onSupprimer;

  const _CarteAppartement({
    required this.ligne,
    required this.codes,
    required this.onChoisirCode,
    required this.creationOuverte,
    required this.onBasculerCreation,
    required this.controleurNouveauCode,
    required this.creationEnCours,
    required this.onCreerCode,
    required this.onChoisirFichier,
    required this.onRetirerFichier,
    required this.onSupprimer,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Le code de la ligne peut ne plus figurer dans la liste : il a été retiré
    // du référentiel depuis. On le rajoute plutôt que de laisser le menu vider
    // la sélection en silence — l'utilisateur perdrait un appartement déjà
    // saisi sans comprendre pourquoi.
    final valeurs = [
      for (final c in codes) c.code,
      if (ligne.code != null && !codes.any((c) => c.code == ligne.code)) ligne.code!,
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: ligne.code,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.depotAppartementCode,
                    errorText: ligne.erreur,
                    isDense: true,
                    prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
                  ),
                  items: [
                    for (final v in valeurs)
                      DropdownMenuItem(
                        value: v,
                        child: Text(
                          codes.firstWhere(
                            (c) => c.code == v,
                            orElse: () => CodeAppartement(id: v, code: v),
                          ).libelle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onChoisirCode,
                ),
              ),
              const SizedBox(width: 6),
              // Le « + » demandé par le client, exactement comme pour les
              // niveaux et les bâtiments : créer un code absent de la liste
              // sans quitter la saisie en cours. Il part en base et devient
              // disponible pour toute l'organisation.
              IconButton.filledTonal(
                tooltip: l10n.depotAppartementNouveauCode,
                icon: Icon(creationOuverte ? Icons.close_rounded : Icons.add_rounded),
                onPressed: onBasculerCreation,
              ),
              IconButton(
                tooltip: l10n.depotAppartementSupprimer,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppColors.danger,
                onPressed: onSupprimer,
              ),
            ],
          ),

          if (creationOuverte) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controleurNouveauCode,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: l10n.depotAppartementNouveauCode,
                      helperText: l10n.depotAppartementNouveauCodeAide,
                      helperMaxLines: 2,
                      isDense: true,
                      prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                    ),
                    onSubmitted: (_) => onCreerCode(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: creationEnCours ? null : onCreerCode,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: creationEnCours
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(l10n.depotNiveauCreerCode),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),
          _CarteFichier(
            label: l10n.depotAppartementPlan,
            fichier: ligne.fichier,
            onChoisir: onChoisirFichier,
            onRetirer: onRetirerFichier,
          ),
        ],
      ),
    );
  }
}

/// Ouvre l'image choisie EN GRAND, avant tout enregistrement.
///
/// Le client : « l'utilisateur doit avoir la possibilité de prévisualiser
/// l'image qu'il vient d'ajouter avant de l'enregistrer ». Une vignette de 40
/// points ne permet pas de reconnaître un plan d'appartement d'un autre — et
/// c'est précisément l'erreur qu'il veut pouvoir rattraper.
///
/// Zoom et déplacement : un plan se lit de près.
void _ouvrirApercu(BuildContext context, String chemin, String nom) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.file(
                File(chemin),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Text(
              nom,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ],
      ),
    ),
  );
}
