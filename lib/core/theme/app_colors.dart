import 'package:flutter/material.dart';

/// Palette — alignée sur l'admin web (`#f2600c`, variable CSS `--primary`
/// dans `admin/src/index.css`) pour une identité visuelle strictement
/// identique entre les deux plateformes (demande client : même orange
/// partout). Toute évolution de palette doit être répercutée dans les DEUX
/// fichiers à la fois.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFF2600C);
  static const Color primaryLight = Color(0xFFFF7A2E);
  static const Color primaryDark = Color(0xFFC94E09);
  static const Color primaryDarker = Color(0xFF9C3D07);
  static const Color primary100 = Color(0xFFFFEEE3);
  static const Color primary200 = Color(0xFFFFD3B0);

  // Or chaleureux — accent secondaire, complète l'orange sans s'y confondre
  // (identique à --accent côté admin).
  static const Color accent = Color(0xFFFFB020);
  static const Color accentDark = Color(0xFFE08E00);
  static const Color accentLight = Color(0xFFFFCB66);

  static const Color background = Color(0xFFF3F5F8);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE4E9EF);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF52606E);
  static const Color textMuted = Color(0xFF94A3B8);

  // ── Sémantique — statuts métier (chantiers, réserves, inspections) ────────
  static const Color success = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerBg = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF2563EB);
  static const Color infoBg = Color(0xFFDBEAFE);
  static const Color neutral = Color(0xFF64748B);
  static const Color neutralBg = Color(0xFFF1F5F9);
}
