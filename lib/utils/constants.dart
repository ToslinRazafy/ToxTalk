import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class AppConstants {
  static const _otpLength = 6;
  static const _otpExpirationMinutes = 5;
  static const _resetTokenExpirationMinutes = 15;
  static final _logger = Logger();

  static String hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  static bool verifyPassword(String password, String hashedPassword) {
    return BCrypt.checkpw(password, hashedPassword);
  }

  static String generateJwtToken(String userId) {
    final payload = {
      'sub': userId,
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp':
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
          1000,
    };

    final header = {'alg': 'HS256', 'typ': 'JWT'};
    final encodedHeader = base64Url.encode(utf8.encode(jsonEncode(header)));
    final encodedPayload = base64Url.encode(utf8.encode(jsonEncode(payload)));

    final secret = dotenv.env['JWT_SECRET'] ?? '';
    if (secret.isEmpty) {
      throw Exception('Clé JWT manquante');
    }

    final signature = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode('$encodedHeader.$encodedPayload'));
    final encodedSignature = base64Url
        .encode(signature.bytes)
        .replaceAll('=', '');

    return '$encodedHeader.$encodedPayload.$encodedSignature';
  }

  static bool isValidJwtToken(String token) {
    try {
      final isExpired = JwtDecoder.isExpired(token);
      if (isExpired) {
        _logger.w('Token JWT expiré');
        return false;
      }

      final secret = dotenv.env['JWT_SECRET'] ?? '';
      if (secret.isEmpty) {
        throw Exception('Clé JWT manquante');
      }

      final parts = token.split('.');
      if (parts.length != 3) {
        return false;
      }
      final signature = Hmac(
        sha256,
        utf8.encode(secret),
      ).convert(utf8.encode('${parts[0]}.${parts[1]}'));
      final encodedSignature = base64Url
          .encode(signature.bytes)
          .replaceAll('=', '');

      return encodedSignature == parts[2];
    } catch (e) {
      _logger.e('Erreur lors de la validation du token JWT : $e');
      return false;
    }
  }

  static bool isValidEmail(String email) =>
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);

  static bool isValidOtp(String otp) => RegExp(r'^\d{6}$').hasMatch(otp);

  static bool isValidPassword(String password) =>
      RegExp(r'^.{8,}$').hasMatch(password);

  static String generateOtp() =>
      Random().nextInt(999999).toString().padLeft(_otpLength, '0');

  static Future<void> sendEmail({
    required String email,
    required String subject,
    required String content,
  }) async {
    try {
      final smtpHost = dotenv.env['MAIL_HOST'] ?? '';
      final smtpPort = int.tryParse(dotenv.env['MAIL_PORT'] ?? '587') ?? 587;
      final smtpUsername = dotenv.env['MAIL_USERNAME'] ?? '';
      final smtpPassword = dotenv.env['MAIL_PASSWORD'] ?? '';

      if (smtpHost.isEmpty || smtpUsername.isEmpty || smtpPassword.isEmpty) {
        _logger.e('Erreur : Variables d\'environnement SMTP manquantes');
        throw Exception('Configuration SMTP invalide : variables manquantes');
      }

      _logger.i(
        'Configuration SMTP : host=$smtpHost, port=$smtpPort, username=$smtpUsername',
      );

      final smtpServer = SmtpServer(
        smtpHost,
        port: smtpPort,
        username: smtpUsername,
        password: smtpPassword,
        ssl: false,
        allowInsecure: true,
      );

      final message = Message()
        ..from = Address(smtpUsername)
        ..recipients.add(email)
        ..subject = subject
        ..html = content;

      final sendReport = await send(message, smtpServer);
      _logger.i('Email envoyé avec succès à $email : $sendReport');
    } catch (e) {
      _logger.e('Erreur lors de l\'envoi de l\'email : $e');
      throw Exception('Échec de l\'envoi de l\'email : $e');
    }
  }

  static String buildVerificationEmailContent(String code) =>
      '''
    <div style='font-family: Arial, sans-serif; padding: 20px; background: #f9f9f9;'>
      <h2 style='color: #1a73e8;'>Vérification de compte</h2>
      <p>Merci de vous être inscrit ! Voici votre code de vérification :</p>
      <h3 style='background: #e8f0fe; padding: 10px; display: inline-block; border-radius: 5px; color: #1a73e8;'>$code</h3>
      <p>Ce code expirera dans <strong>$_otpExpirationMinutes minutes</strong>.</p>
      <p>Si vous n'avez pas initié cette demande, veuillez ignorer cet email.</p>
    </div>
  ''';

  static String buildResetEmailContent(String token) =>
      '''
    <div style='font-family: Arial, sans-serif; padding: 20px; background: #f9f9f9;'>
      <h2 style='color: #1a73e8;'>Réinitialisation de mot de passe</h2>
      <p>Vous avez demandé une réinitialisation de mot de passe. Utilisez ce code pour continuer :</p>
      <h3 style='background: #e8f0fe; padding: 10px; display: inline-block; border-radius: 5px; color: #1a73e8;'>$token</h3>
      <p>Ce code expirera dans <strong>$_resetTokenExpirationMinutes minutes</strong>.</p>
      <p>Si vous n'avez pas initié cette demande, veuillez ignorer cet email.</p>
    </div>
  ''';

  static String buildExpirationNotificationContent({
    required String nom,
    required String notifType,
    required String message,
  }) {
    return """
        <!DOCTYPE html>
        <html lang="fr">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body { font-family: Arial, sans-serif; background-color: #f5f5f5; padding: 20px; }
          .container { max-width: 600px; margin: auto; background: white; padding: 20px; border-radius: 8px; }
          h2 { color: #2c3e50; }
          p { font-size: 16px; line-height: 1.5; }
          .badge { display: inline-block; padding: 5px 10px; border-radius: 4px; color: white; }
          .preavis { background-color: #27ae60; }
          .alerte { background-color: #f39c12; }
          .urgence { background-color: #c0392b; }
        </style>
        </head>
        <body>
          <div class="container">
            <h2>Bonjour $nom,</h2>
            <p>Nous vous informons que votre assurance est en cours d’expiration.</p>
            <p>
              <span class="badge ${notifType.contains('25')
                ? 'preavis'
                : notifType.contains('15')
                ? 'alerte'
                : 'urgence'}">
                $notifType
              </span>
            </p>
            <p>$message</p>
            <p>Merci de prendre les dispositions nécessaires pour renouveler votre assurance.</p>
            <p>Cordialement,<br><strong>Votre compagnie d’assurance</strong></p>
          </div>
        </body>
        </html>
      """;
  }
}
