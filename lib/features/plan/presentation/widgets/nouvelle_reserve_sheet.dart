import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../corps_etat/domain/entities/corps_etat.dart';
import '../../../phase/domain/entities/phase_referentiel.dart';
import '../../../phase/domain/usecases/get_phases_actives.dart';
import '../../../corps_etat/domain/usecases/get_corps_etat_actifs.dart';
import '../../../organisation/domain/entities/partenaire.dart';
import '../../../organisation/domain/usecases/get_partenaires.dart';
import '../../../reserve/domain/entities/reserve.dart';
import '../../../reserve/domain/usecases/ajouter_media_reserve.dart';
import '../../../reserve/domain/usecases/creer_reserve.dart';

/// Localisation héritée du parcours de navigation — jamais saisie à la main.
class LocalisationReserve {
  final String chantierId;
  final String? planId;
  final String? batimentId;
  final String? etageId;
  final String? zoneId;

  /// Chemin lisible affiché à l'utilisateur (« Bâtiment A › R+2 › A203 »).
  final String chemin;

  const LocalisationReserve({
    required this.chantierId,
    this.planId,
    this.batimentId,
    this.etageId,
    this.zoneId,
    this.chemin = '',
  });
}

/// Fenêtre « Nouvelle réserve », ouverte par un appui sur le plan.
///
/// Reprend exactement les champs obligatoires du guide client : titre,
/// observation, entreprise concernée, photo, gravité, délai de levée — et une
/// localisation NON SAISISSABLE, héritée du parcours et du point appuyé.
/// C'est tout l'intérêt de créer la réserve depuis le plan : la localisation
/// ne peut pas être fausse.
///
/// La PHOTO part en second appel (`POST /reserves/:id/medias`), l'API de
/// création étant en JSON. Si la réserve est créée mais que la photo échoue,
/// on garde la réserve et on le dit : perdre le constat parce que la pièce
/// jointe n'est pas passée serait le pire des deux résultats.
class NouvelleReserveSheet extends StatefulWidget {
  final LocalisationReserve localisation;

  /// Point appuyé sur le plan, en POURCENTAGES de la page (0-100).
  final double positionX;
  final double positionY;

  const NouvelleReserveSheet({
    super.key,
    required this.localisation,
    required this.positionX,
    required this.positionY,
  });

  @override
  State<NouvelleReserveSheet> createState() => _NouvelleReserveSheetState();
}

class _NouvelleReserveSheetState extends State<NouvelleReserveSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titreCtrl = TextEditingController();
  final _observationCtrl = TextEditingController();

  ReserveSeverite _gravite = ReserveSeverite.moyenne;
  /// Corps d'état choisi — identifiant du catalogue servi par l'API, et non
  /// plus une valeur d'énumération figée dans le code.
  String? _corpsEtatId;

  /// Phase du chantier — OBLIGATOIRE : le serveur refuse une réserve sans.
  String? _phaseId;
  DateTime? _dateLimite;
  String? _partenaireId;
  File? _photo;

  List<Partenaire> _partenaires = const [];
  List<CorpsEtat> _corpsEtat = const [];
  List<PhaseReferentiel> _phases = const [];
  bool _envoiEnCours = false;

  /// Signale la phase manquante SOUS le champ, plutôt que par une alerte :
  /// l'utilisateur voit immédiatement lequel des champs bloque.
  bool _phaseManquante = false;

  @override
  void initState() {
    super.initState();
    _chargerPartenaires();
    _chargerCorpsEtat();
    _chargerPhases();
  }

  @override
  void dispose() {
    _titreCtrl.dispose();
    _observationCtrl.dispose();
    super.dispose();
  }

  /// L'annuaire alimente « Entreprise concernée ». Un échec ne bloque rien :
  /// le champ reste vide et la réserve part sans entreprise, ce qui vaut
  /// mieux que d'empêcher d'enregistrer un défaut constaté sur place.
  Future<void> _chargerPartenaires() async {
    final resultat = await sl<GetPartenaires>()();
    if (!mounted) return;
    resultat.fold(
      (_) {},
      (liste) => setState(() => _partenaires = liste.where((p) => p.actif).toList()),
    );
  }

  /// Le catalogue des métiers alimente « Corps d'état ». Comme l'annuaire,
  /// un échec ne bloque pas la saisie : le champ reste vide et la réserve
  /// part sans métier — un défaut constaté sur place doit toujours pouvoir
  /// être enregistré.
  Future<void> _chargerCorpsEtat() async {
    final resultat = await sl<GetCorpsEtatActifs>()();
    if (!mounted) return;
    resultat.fold(
      (_) {},
      (liste) => setState(() => _corpsEtat = liste),
    );
  }

  /// Le référentiel des phases alimente un champ OBLIGATOIRE. Contrairement
  /// au catalogue des métiers, un échec ici empêche réellement d'enregistrer :
  /// le repository sert alors son cache, et à défaut le bouton reste bloqué
  /// avec un message explicite plutôt que de partir vers un refus serveur.
  Future<void> _chargerPhases() async {
    final resultat = await sl<GetPhasesActives>()();
    if (!mounted) return;
    resultat.fold(
      (_) {},
      (liste) => setState(() => _phases = liste),
    );
  }

  Future<void> _choisirPhoto(ImageSource source) async {
    final fichier = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1920);
    if (fichier == null || !mounted) return;
    setState(() => _photo = File(fichier.path));
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: _dateLimite ?? maintenant.add(const Duration(days: 14)),
      // Une réserve se lève dans le futur : proposer une échéance passée
      // n'aurait aucun sens et fausserait le suivi des retards.
      firstDate: maintenant,
      lastDate: maintenant.add(const Duration(days: 365 * 5)),
    );
    if (choisie != null && mounted) setState(() => _dateLimite = choisie);
  }

  Future<void> _enregistrer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // La phase est obligatoire. Le serveur l'impose aussi
    // (`creerReserveSchema`) : ce contrôle évite un aller-retour réseau et
    // signale le champ fautif SOUS le sélecteur, pas dans une alerte.
    if (_phaseId == null) {
      setState(() => _phaseManquante = true);
      return;
    }
    // Verrou de double soumission — même raison que dans `ReserveWizardCubit` :
    // deux appuis rapprochés créaient deux réserves distinctes, et la
    // désactivation du bouton n'agit qu'à la frame suivante.
    if (_envoiEnCours) return;
    setState(() => _envoiEnCours = true);

    final l10n = context.l10n;
    final loc = widget.localisation;

    final resultat = await sl<CreerReserve>()(
      chantierId: loc.chantierId,
      titre: _titreCtrl.text.trim(),
      description: _observationCtrl.text.trim().isEmpty ? null : _observationCtrl.text.trim(),
      // Le guide client ne demande qu'un seul curseur : la gravité pilote
      // aussi la priorité de traitement. Les deux restent dissociables depuis
      // le détail de la réserve.
      priorite: _gravite,
      severite: _gravite,
      corpsEtatId: _corpsEtatId,
      phaseId: _phaseId,
      batimentId: loc.batimentId,
      etageId: loc.etageId,
      zoneId: loc.zoneId,
      planId: loc.planId,
      positionX: widget.positionX,
      positionY: widget.positionY,
      partenaireId: _partenaireId,
      dateLimite: _dateLimite,
    );

    if (!mounted) return;

    await resultat.fold(
      (failure) async {
        setState(() => _envoiEnCours = false);
        AppAlert.error(context, message: failure.errorMessage);
      },
      (reserve) async {
        if (_photo != null) {
          final envoi = await sl<AjouterMediaReserve>()(
            reserveId: reserve.id,
            cheminFichier: _photo!.path,
          );
          if (!mounted) return;
          envoi.fold(
            (_) => AppAlert.error(context, message: l10n.reserveNouvPhotoEchouee),
            (_) {},
          );
        }
        if (!mounted) return;
        setState(() => _envoiEnCours = false);
        Navigator.of(context).pop(reserve);
        AppAlert.success(context, message: l10n.reserveNouvCreee);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      // Remonte la feuille au-dessus du clavier : sans cela, les derniers
      // champs restaient cachés dessous, hors d'atteinte.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.planNouvelleReserve,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textSecondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      TextFormField(
                        controller: _titreCtrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: l10n.reserveNouvTitreLabel,
                          hintText: l10n.reserveNouvTitreHint,
                        ),
                        // Miroir de `creerReserveSchema` côté serveur
                        // (`titre` : min 2, max 200) — bloquer ici évite un
                        // aller-retour réseau pour un 422 générique.
                        maxLength: 200,
                        validator: (v) =>
                            (v ?? '').trim().length < 2 ? l10n.reserveNouvTitreRequis : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _observationCtrl,
                        maxLines: 3,
                        maxLength: 5000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: l10n.reserveNouvObservation,
                          hintText: l10n.reserveNouvObservationHint,
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 8),

                      DropdownButtonFormField<String?>(
                        initialValue: _partenaireId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: l10n.reserveNouvEntreprise),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(l10n.reserveNouvAucuneEntreprise),
                          ),
                          for (final p in _partenaires)
                            DropdownMenuItem<String?>(
                              value: p.id,
                              child: Text(p.nom, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => _partenaireId = v),
                      ),
                      const SizedBox(height: 16),

                      _ChampPhoto(
                        photo: _photo,
                        onAppareil: () => _choisirPhoto(ImageSource.camera),
                        onGalerie: () => _choisirPhoto(ImageSource.gallery),
                        onRetirer: () => setState(() => _photo = null),
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<ReserveSeverite>(
                        initialValue: _gravite,
                        decoration: InputDecoration(labelText: l10n.reserveNouvGravite),
                        items: [
                          for (final s in ReserveSeverite.values)
                            DropdownMenuItem(
                              value: s,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(color: _couleurGravite(s), shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(s.label(l10n)),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _gravite = v ?? ReserveSeverite.moyenne),
                      ),
                      const SizedBox(height: 12),

                      // Phase — champ OBLIGATOIRE, d'où l'astérisque et
                      // l'absence d'option « aucune ».
                      DropdownButtonFormField<String?>(
                        initialValue: _phaseId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: '${l10n.phaseLabel} *',
                          errorText: _phaseManquante ? l10n.phaseRequise : null,
                        ),
                        items: [
                          DropdownMenuItem(value: null, child: Text(l10n.phaseChoisir)),
                          for (final ph in _phases)
                            DropdownMenuItem(value: ph.id, child: Text(ph.nom)),
                        ],
                        onChanged: (v) => setState(() {
                          _phaseId = v;
                          _phaseManquante = false;
                        }),
                      ),
                      const SizedBox(height: 12),

                      // Catalogue servi par l'API : la liste s'enrichit depuis
                      // l'espace d'administration, sans livraison mobile.
                      DropdownButtonFormField<String?>(
                        initialValue: _corpsEtatId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: l10n.corpsEtatLabel),
                        items: [
                          DropdownMenuItem(value: null, child: Text(l10n.corpsEtatAucun)),
                          for (final c in _corpsEtat)
                            DropdownMenuItem(value: c.id, child: Text(c.nom)),
                        ],
                        onChanged: (v) => setState(() => _corpsEtatId = v),
                      ),
                      const SizedBox(height: 12),

                      InkWell(
                        onTap: _choisirDate,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: l10n.reserveNouvDelai,
                            suffixIcon: const Icon(Icons.event_outlined, size: 20),
                          ),
                          child: Text(
                            _dateLimite == null
                                ? l10n.reserveNouvChoisirDate
                                : DateFormat.yMd(Localizations.localeOf(context).toString()).format(_dateLimite!),
                            style: TextStyle(
                              color: _dateLimite == null ? AppColors.textMuted : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      _ChampLocalisation(
                        chemin: widget.localisation.chemin,
                        x: widget.positionX,
                        y: widget.positionY,
                      ),
                      const SizedBox(height: 22),

                      PrimaryButton(
                        label: l10n.reserveNouvEnregistrer,
                        onPressed: _enregistrer,
                        enCours: _envoiEnCours,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _couleurGravite(ReserveSeverite s) => switch (s) {
      ReserveSeverite.faible => AppColors.info,
      ReserveSeverite.moyenne => AppColors.warning,
      ReserveSeverite.haute => AppColors.danger,
      ReserveSeverite.critique => AppColors.danger,
    };

/// Vignette de la photo + les deux sources possibles.
///
/// L'appareil photo est proposé EN PREMIER : sur un chantier, la photo est
/// prise sur place au moment du constat, la galerie n'est qu'un repli.
class _ChampPhoto extends StatelessWidget {
  final File? photo;
  final VoidCallback onAppareil;
  final VoidCallback onGalerie;
  final VoidCallback onRetirer;

  const _ChampPhoto({
    required this.photo,
    required this.onAppareil,
    required this.onGalerie,
    required this.onRetirer,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reserveNouvPhoto,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (photo != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      photo!,
                      width: 74,
                      height: 58,
                      fit: BoxFit.cover,
                      // La photo est déjà plafonnée à 1920 px par
                      // `image_picker` (voir `_choisirPhoto`), mais rien
                      // n'empêche `Image.file` de la décoder à cette pleine
                      // résolution pour un aperçu de 74×58 : jusqu'à 20 Mo
                      // de mémoire pour quelques centaines de pixels
                      // affichés. Même correctif que `FichierImage` —
                      // décoder à la taille d'affichage réelle.
                      cacheWidth: (74 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: onRetirer,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            else
              Container(
                width: 74,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                  color: AppColors.background,
                ),
                child: const Icon(Icons.photo_camera_outlined, color: AppColors.textMuted, size: 22),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: onAppareil,
                    icon: const Icon(Icons.photo_camera_outlined, size: 17),
                    label: Text(l10n.reserveNouvPrendrePhoto, style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: onGalerie,
                    icon: const Icon(Icons.photo_library_outlined, size: 17),
                    label: Text(l10n.reserveNouvChoisirGalerie, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Localisation présentée comme une donnée ACQUISE, pas comme un champ à
/// remplir : aucune bordure de saisie, fond neutre, rien de modifiable.
class _ChampLocalisation extends StatelessWidget {
  final String chemin;
  final double x;
  final double y;

  const _ChampLocalisation({required this.chemin, required this.x, required this.y});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reserveNouvLocalisation,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.place_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  chemin,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'x ${x.toStringAsFixed(0)} · y ${y.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
