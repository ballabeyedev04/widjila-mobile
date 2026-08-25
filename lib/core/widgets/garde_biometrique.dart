import 'package:flutter/material.dart';

import '../../l10n/l10n_extension.dart';
import '../services/verrou_biometrique.dart';
import '../theme/app_colors.dart';
import 'liste_chrome.dart';

/// Voile de verrouillage posé au-dessus de l'application.
///
/// Placé dans le `builder` de `MaterialApp.router`, comme `OfflineBootstrap`
/// et `PushBootstrap` : il couvre donc TOUS les écrans, y compris ceux ouverts
/// depuis une notification push — un deep link ne doit pas être un chemin de
/// contournement du verrou.
///
/// Le contenu reste MONTÉ derrière le voile plutôt que d'être remplacé : le
/// démonter viderait chaque cubit et forcerait un rechargement complet à
/// chaque retour d'arrière-plan, sur un réseau de chantier.
class GardeBiometrique extends StatefulWidget {
  final VerrouBiometrique verrou;
  final Widget child;

  const GardeBiometrique({super.key, required this.verrou, required this.child});

  @override
  State<GardeBiometrique> createState() => _GardeBiometriqueState();
}

class _GardeBiometriqueState extends State<GardeBiometrique> with WidgetsBindingObserver {
  bool _verrouille = false;
  bool _demandeEnCours = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.verrou.actif) {
      _verrouille = true;
      // Après le premier rendu : `authenticate` ouvre une boîte de dialogue
      // système, impossible pendant la construction de l'arbre.
      WidgetsBinding.instance.addPostFrameCallback((_) => _demander());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (!widget.verrou.actif) return;

    // `paused` et non `inactive` : `inactive` survient aussi pendant l'appel
    // biométrique lui-même et pour un simple centre de contrôle déroulé —
    // s'y verrouiller créerait une boucle dont on ne sort jamais.
    if (etat == AppLifecycleState.paused) {
      if (mounted) setState(() => _verrouille = true);
    } else if (etat == AppLifecycleState.resumed && _verrouille) {
      _demander();
    }
  }

  Future<void> _demander() async {
    if (_demandeEnCours) return;
    _demandeEnCours = true;

    final ok = await widget.verrou.authentifier(motif: context.l10n.bioInvite);
    _demandeEnCours = false;
    if (!mounted) return;
    if (ok) setState(() => _verrouille = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_verrouille) _Voile(onReessayer: _demander),
      ],
    );
  }
}

/// Écran opaque affiché tant que l'identité n'est pas confirmée.
///
/// Opaque et non flouté : le flou laisse deviner les noms et les montants
/// d'une liste, ce qui est précisément ce que le verrou doit empêcher.
class _Voile extends StatelessWidget {
  final VoidCallback onReessayer;
  const _Voile({required this.onReessayer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Positioned.fill(
      child: Material(
        color: AppColors.background,
        child: SafeArea(
          child: ContenuFormulaire(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.12),
                      ),
                      child: const Icon(Icons.fingerprint_rounded, size: 44, color: AppColors.primary),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      l10n.bioVerrouille,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.bioInvite,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: onReessayer,
                        icon: const Icon(Icons.lock_open_rounded, size: 20),
                        label: Text(
                          l10n.bioReessayer,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
