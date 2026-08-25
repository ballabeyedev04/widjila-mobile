import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../widgets/auth_chrome.dart';

/// Écran affiché le temps que [AuthBloc] restaure (ou non) une session
/// existante — voir `AuthCheckRequested`. Le routeur (`app_router.dart`)
/// redirige automatiquement dès que `AuthState.status` change.
///
/// Volontairement minimal : fond neutre, uniquement le logo. Il porte une
/// seule animation d'entrée (montée + fondu + léger rebond), jouée une fois.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _translation;
  late final Animation<double> _echelle;
  late final Animation<double> _opacite;

  bool _imagePrechargee = false;

  @override
  void initState() {
    super.initState();
    context.read<AuthBloc>().add(const AuthCheckRequested());

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

    // Monte du bas vers sa place finale — pas de rebond ici (l'`Offset`
    // rebondirait aussi horizontalement/verticalement de façon peu naturelle
    // sur une simple translation verticale) : la douceur de la montée vient
    // du fondu et du zoom ci-dessous, joués en même temps.
    _translation = Tween<Offset>(begin: const Offset(0, 0.55), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.9, curve: Curves.easeOutCubic)),
    );

    // Léger rebond à l'arrivée (dépasse 1.0 puis se stabilise) — c'est ce qui
    // donne la touche « jolie » plutôt qu'un simple glissement mécanique.
    _echelle = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _opacite = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );

    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Précharger une seule fois : `didChangeDependencies` peut être rappelé
    // (changement de thème, de langue…) sans que ce soit une nouvelle entrée
    // sur l'écran.
    if (!_imagePrechargee) {
      _imagePrechargee = true;
      precacheImage(const AssetImage(authLogoImage), context);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Le logo est fourni sur fond blanc opaque (pas de transparence) : un
      // fond de page blanc est ce qui le fait se fondre sans bordure visible.
      backgroundColor: AppColors.surface,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, enfant) => Opacity(
            opacity: _opacite.value,
            child: FractionalTranslation(
              translation: _translation.value,
              child: Transform.scale(scale: _echelle.value, child: enfant),
            ),
          ),
          child: Image.asset(authLogoImage, width: 220, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
