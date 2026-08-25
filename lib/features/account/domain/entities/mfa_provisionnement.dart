import 'package:equatable/equatable.dart';

/// Matériel de provisionnement MFA renvoyé par `POST /account/mfa/provision`
/// (`AccountService.provisionMfa`) : secret TOTP à saisir manuellement, URL
/// otpauth et QR code déjà encodé en PNG base64 (`data:image/png;base64,...`)
/// — pas besoin d'une librairie de génération de QR côté mobile.
class MfaProvisionnement extends Equatable {
  final String secret;
  final String otpauthUrl;
  final String qrDataUrl;

  const MfaProvisionnement({required this.secret, required this.otpauthUrl, required this.qrDataUrl});

  factory MfaProvisionnement.fromJson(Map<String, dynamic> json) => MfaProvisionnement(
        secret: json['secret'] as String,
        otpauthUrl: json['otpauthUrl'] as String,
        qrDataUrl: json['qr'] as String,
      );

  @override
  List<Object?> get props => [secret, otpauthUrl, qrDataUrl];
}
