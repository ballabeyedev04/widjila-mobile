import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/chantier/domain/entities/chantier.dart';
import '../../features/chantier/presentation/cubit/chantiers_list_cubit.dart';
import '../../features/chantier/presentation/cubit/chantiers_list_state.dart';
import '../../features/chantier/presentation/widgets/chantier_statut_badge.dart';
import '../../injection_container.dart';
import '../../l10n/l10n_extension.dart';
import '../theme/app_colors.dart';
import 'empty_state.dart';
import 'liste_chrome.dart';
import 'error_view.dart';
import 'loading_list.dart';
import 'status_badge.dart';

/// Sélecteur de chantier — étape obligatoire des actions rapides du menu.
///
/// Une réserve, un plan ou un document appartiennent TOUJOURS à un chantier
/// (contrainte `chantierId NOT NULL` côté back). Le bouton « + » de la barre
/// de navigation, lui, est global : il faut donc demander le chantier avant
/// d'ouvrir le formulaire, plutôt que de deviner un chantier « courant » qui
/// n'existe pas à ce niveau de l'application.
///
/// Retourne le [Chantier] choisi, ou `null` si l'utilisateur referme.
Future<Chantier?> choisirChantier(BuildContext context, {required String titre}) {
  return showModalBottomSheet<Chantier>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider(
      create: (_) => sl<ChantiersListCubit>()..charger(),
      child: _ChantierPickerSheet(titre: titre),
    ),
  );
}

class _ChantierPickerSheet extends StatefulWidget {
  final String titre;
  const _ChantierPickerSheet({required this.titre});

  @override
  State<_ChantierPickerSheet> createState() => _ChantierPickerSheetState();
}

class _ChantierPickerSheetState extends State<_ChantierPickerSheet> {
  final _rechercheCtrl = TextEditingController();

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _EnTeteDegrade(
                titre: widget.titre,
                controleurRecherche: _rechercheCtrl,
              ),
              const _LigneCompteur(),
              Expanded(child: _Corps(scrollController: scrollController)),
            ],
          ),
        );
      },
    );
  }
}

/// Bandeau supérieur — dégradé orange, poignée, titre, croix, et la barre de
/// recherche posée dessus.
///
/// La recherche vit DANS le bandeau plutôt qu'en dessous : le champ blanc sur
/// l'aplat coloré se détache immédiatement, et la liste en dessous démarre
/// sur un fond neutre sans élément d'interface intercalé.
class _EnTeteDegrade extends StatelessWidget {
  final String titre;
  final TextEditingController controleurRecherche;

  const _EnTeteDegrade({required this.titre, required this.controleurRecherche});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ContenuCentre(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(Icons.construction_rounded, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.chantierPickerSousTitre,
                          style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ContenuCentre(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: _ChampRecherche(controleur: controleurRecherche),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChampRecherche extends StatelessWidget {
  final TextEditingController controleur;
  const _ChampRecherche({required this.controleur});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ChantiersListCubit>();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: TextField(
        controller: controleur,
        textInputAction: TextInputAction.search,
        onChanged: cubit.rechercher,
        style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: l10n.chantierPickerRechercheHint,
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
          // La croix n'apparaît QUE si le champ contient quelque chose :
          // affichée en permanence, elle donnerait à un champ vide l'air
          // d'un champ rempli.
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controleur,
            builder: (context, valeur, _) {
              if (valeur.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                tooltip: l10n.chantierPickerEffacer,
                onPressed: () {
                  controleur.clear();
                  cubit.rechercher('');
                },
              );
            },
          ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary200, width: 1.6),
          ),
        ),
      ),
    );
  }
}

/// Ligne de contexte entre le bandeau et la liste : nombre de chantiers
/// visibles, et mention discrète d'une recherche en vol.
///
/// C'est elle qui rend la recherche LISIBLE : les résultats précédents
/// restent affichés pendant la requête (voir [_Corps]), il faut donc dire
/// quelque part que la liste est en train d'être rafraîchie.
class _LigneCompteur extends StatelessWidget {
  const _LigneCompteur();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<ChantiersListCubit, ChantiersListState>(
      builder: (context, state) {
        if (state.status == ChantiersListStatus.erreur) return const SizedBox.shrink();

        final enRecherche = state.status == ChantiersListStatus.chargement && state.items.isNotEmpty;
        // Le TOTAL serveur, pas la page chargée : « 45 chantiers » avec 20
        // cartes à l'écran est juste — c'est le « Voir plus » qui donnera la
        // suite. Afficher 20 laisserait croire que le compte est complet.
        final nombre = state.total > 0 ? state.total : state.items.length;
        if (nombre == 0 && !enRecherche) return const SizedBox.shrink();

        return ContenuCentre(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
            child: Row(
              children: [
                Icon(
                  enRecherche ? Icons.search_rounded : Icons.format_list_bulleted_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    enRecherche ? l10n.chantierPickerRechercheEnCours : l10n.chantierPickerCompteur(nombre),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                // Fine barre de progression alignée à droite plutôt qu'un
                // spinner centré : elle signale l'activité sans déplacer ni
                // masquer les résultats déjà lus.
                if (enRecherche)
                  const SizedBox(
                    width: 54,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: AppColors.border,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Corps extends StatefulWidget {
  final ScrollController scrollController;
  const _Corps({required this.scrollController});

  @override
  State<_Corps> createState() => _CorpsState();
}

class _CorpsState extends State<_Corps> {
  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_surDefilement);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_surDefilement);
    super.dispose();
  }

  /// Pagination au fil du défilement — la liste des chantiers est paginée
  /// côté serveur (20 par page) et le sélecteur doit pouvoir atteindre le
  /// 21ᵉ chantier autrement qu'en le cherchant par son nom.
  void _surDefilement() {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      context.read<ChantiersListCubit>().chargerPageSuivante();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<ChantiersListCubit, ChantiersListState>(
      builder: (context, state) {
        switch (state.status) {
          case ChantiersListStatus.initial:
            return const LoadingList(itemHeight: 96);

          case ChantiersListStatus.chargement:
            // Premier chargement seulement : dès qu'il y a des résultats à
            // l'écran, on les GARDE pendant la requête suivante plutôt que de
            // les remplacer par un squelette. Repartir d'un écran gris à
            // chaque frappe donnait l'impression que l'application redémarre.
            if (state.items.isEmpty) return const LoadingList(itemHeight: 96);
            return _Liste(state: state, controleur: widget.scrollController);

          case ChantiersListStatus.erreur:
            return _EtatPleinePage(
              controleur: widget.scrollController,
              child: ErrorView(
                message: state.erreur ?? l10n.commonErrorUnknown,
                onRetry: () => context.read<ChantiersListCubit>().charger(),
              ),
            );

          case ChantiersListStatus.succes:
            if (state.items.isEmpty) {
              // Distinguer « l'organisation n'a aucun chantier » de « la
              // recherche ne renvoie rien » : le premier cas s'adresse à
              // l'administration, le second demande juste un autre mot-clé.
              final enRecherche = state.recherche.trim().isNotEmpty;
              return _EtatPleinePage(
                controleur: widget.scrollController,
                child: EmptyState(
                  icon: enRecherche ? Icons.search_off_rounded : Icons.construction_outlined,
                  title: enRecherche ? l10n.commonNoResults : l10n.chantierAucun,
                  subtitle: enRecherche ? l10n.chantierAucunRecherche : l10n.chantierAucunSousTitre,
                ),
              );
            }
            return _Liste(state: state, controleur: widget.scrollController);
        }
      },
    );
  }
}

/// Enveloppe un état non défilable (vide, erreur) dans un défilement rattaché
/// au contrôleur de la feuille.
///
/// [DraggableScrollableSheet] pilote sa hauteur DEPUIS ce contrôleur : sans
/// scrollable rattaché, la feuille se fige et ne peut plus être agrandie ni
/// refermée au glissement — précisément dans les moments où l'utilisateur
/// veut en sortir.
class _EtatPleinePage extends StatelessWidget {
  final ScrollController controleur;
  final Widget child;

  const _EtatPleinePage({required this.controleur, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) => SingleChildScrollView(
        controller: controleur,
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: contraintes.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

class _Liste extends StatelessWidget {
  final ChantiersListState state;
  final ScrollController controleur;

  const _Liste({required this.state, required this.controleur});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = state.items;

    return ContenuCentre(
      child: ListView.separated(
        controller: controleur,
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 26),
        itemCount: items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == items.length) {
            // Pied de liste : indicateur de page suivante, ou mot de fin —
            // dans les deux cas, l'utilisateur sait s'il a tout vu.
            if (state.chargementPage) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
                  ),
                ),
              );
            }
            if (state.aPlusDeResultats) {
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => context.read<ChantiersListCubit>().chargerPageSuivante(),
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: Text(l10n.chantierPickerChargerPlus),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Center(
                child: Text(
                  l10n.chantierPickerToutAffiche,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted.withValues(alpha: 0.9)),
                ),
              ),
            );
          }

          return _ApparitionCarte(
            // Clé stable : une carte déjà à l'écran ne rejoue pas son
            // animation à chaque frappe, seules les nouvelles apparaissent.
            key: ValueKey(items[i].id),
            rang: i,
            child: _CarteChantier(chantier: items[i], recherche: state.recherche),
          );
        },
      ),
    );
  }
}

/// Apparition en fondu + léger glissement, décalée selon le rang.
///
/// Le décalage (40 ms par carte, plafonné) donne à la liste une arrivée en
/// cascade au lieu d'un bloc qui surgit d'un coup — c'est ce qui fait la
/// différence entre « les résultats sont affichés » et « les résultats
/// arrivent ». Plafonné à 6 cartes : au-delà, l'attente se verrait.
class _ApparitionCarte extends StatefulWidget {
  final int rang;
  final Widget child;

  const _ApparitionCarte({super.key, required this.rang, required this.child});

  @override
  State<_ApparitionCarte> createState() => _ApparitionCarteState();
}

class _ApparitionCarteState extends State<_ApparitionCarte> with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    final decalage = Duration(milliseconds: 40 * (widget.rang.clamp(0, 6)));
    Future<void>.delayed(decalage, () {
      if (mounted) _controleur.forward();
    });
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final courbe = CurvedAnimation(parent: _controleur, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: courbe,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(courbe),
        child: widget.child,
      ),
    );
  }
}

/// Carte d'un chantier dans le sélecteur.
///
/// Elle porte tout ce qui sert à CHOISIR : le nom (avec la portion cherchée
/// surlignée), le code, l'adresse, le statut, et l'avancement des réserves.
/// Un simple nom + statut obligeait à ouvrir le chantier pour vérifier qu'on
/// avait pris le bon.
class _CarteChantier extends StatelessWidget {
  final Chantier chantier;
  final String recherche;

  const _CarteChantier({required this.chantier, required this.recherche});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tone = toneStatutChantier(chantier.statut);
    final couleur = tone.fg;

    final total = chantier.reservesTotal;
    final ouvertes = chantier.reservesOuvertes ?? 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).pop(chantier),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            // Liseré gauche de la teinte du statut : la liste se lit d'un
            // coup d'œil vertical, sans avoir à parcourir chaque pastille.
            border: Border(left: BorderSide(color: couleur, width: 4)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(13, 13, 12, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [couleur.withValues(alpha: 0.18), couleur.withValues(alpha: 0.07)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.construction_rounded, color: couleur, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NomSurligne(nom: chantier.nom, motif: recherche),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusBadge(label: chantier.statut.label(l10n), tone: tone),
                        if (chantier.code != null && chantier.code!.isNotEmpty) _PastilleCode(code: chantier.code!),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _LigneInfo(
                      icone: Icons.location_on_outlined,
                      texte: (chantier.adresse != null && chantier.adresse!.isNotEmpty)
                          ? chantier.adresse!
                          : l10n.chantierPickerSansAdresse,
                      attenue: chantier.adresse == null || chantier.adresse!.isEmpty,
                    ),
                    if (chantier.responsable != null) ...[
                      const SizedBox(height: 4),
                      _LigneInfo(
                        icone: Icons.person_outline_rounded,
                        texte: l10n.chantierPickerResponsable(chantier.responsable!.nomComplet),
                      ),
                    ],
                    if (total != null) ...[
                      const SizedBox(height: 10),
                      _JaugeReserves(total: total, ouvertes: ouvertes),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12, left: 2),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nom du chantier avec la portion recherchée surlignée.
///
/// Sur une liste de « Résidence Les Tilleuls / Résidence Les Ormes / … », voir
/// EXACTEMENT ce qui a fait correspondre la ligne évite de relire les noms
/// caractère par caractère.
class _NomSurligne extends StatelessWidget {
  final String nom;
  final String motif;

  const _NomSurligne({required this.nom, required this.motif});

  @override
  Widget build(BuildContext context) {
    const styleBase = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      height: 1.2,
    );

    final terme = motif.trim().toLowerCase();
    final debut = terme.isEmpty ? -1 : nom.toLowerCase().indexOf(terme);

    if (debut < 0) {
      return Text(nom, style: styleBase, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final fin = debut + terme.length;
    return Text.rich(
      TextSpan(
        style: styleBase,
        children: [
          TextSpan(text: nom.substring(0, debut)),
          TextSpan(
            text: nom.substring(debut, fin),
            style: const TextStyle(
              color: AppColors.primaryDark,
              backgroundColor: AppColors.primary100,
            ),
          ),
          TextSpan(text: nom.substring(fin)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _PastilleCode extends StatelessWidget {
  final String code;
  const _PastilleCode({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.neutralBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        code,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _LigneInfo extends StatelessWidget {
  final IconData icone;
  final String texte;
  final bool attenue;

  const _LigneInfo({required this.icone, required this.texte, this.attenue = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 13.5, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            texte,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: attenue ? AppColors.textMuted : AppColors.textSecondary,
              fontStyle: attenue ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Avancement des réserves — barre de progression + libellés.
///
/// C'est l'information qui départage deux chantiers au moment de choisir :
/// « 3 réserves ouvertes sur 40 » ne se lit pas comme « 38 sur 40 », et la
/// barre le montre avant même qu'on lise les chiffres.
class _JaugeReserves extends StatelessWidget {
  final int total;
  final int ouvertes;

  const _JaugeReserves({required this.total, required this.ouvertes});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (total == 0) {
      return Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded, size: 13.5, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            l10n.chantierPickerAucuneReserve,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      );
    }

    final levees = (total - ouvertes).clamp(0, total);
    final ratio = levees / total;
    final pourcent = (ratio * 100).round();
    // Vert quand tout est levé, orange tant qu'il reste des réserves
    // ouvertes : la couleur dit « fini / pas fini » sans lire le chiffre.
    final couleur = ouvertes == 0 ? AppColors.success : AppColors.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.report_gmailerrorred_outlined, size: 13.5, color: couleur),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                l10n.chantierReservesOuvertesSur(ouvertes, total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.chantierPickerAvancement(pourcent),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: couleur),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, valeur, _) => LinearProgressIndicator(
              value: valeur,
              minHeight: 5,
              backgroundColor: AppColors.border,
              color: couleur,
            ),
          ),
        ),
      ],
    );
  }
}
