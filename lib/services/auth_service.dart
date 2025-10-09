import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:logger/logger.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:toxtalk/models/user.dart';
import 'package:toxtalk/utils/constants.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
}

class AuthService {
  static const _otpExpirationMinutes = 5;
  static const _resetTokenExpirationMinutes = 15;
  static const _maxNameLength = 255;
  static final _logger = Logger();

  final _supabase = supa.Supabase.instance.client;
  final _storage = const FlutterSecureStorage();

  /// Connexion d'un utilisateur avec email et mot de passe
  Future<User> signIn(String email, String password) async {
    try {
      if (!AppConstants.isValidEmail(email)) {
        throw AuthException('Format d\'email invalide');
      }

      final userData = await _supabase
          .from('users')
          .select()
          .eq('email', email)
          .single();

      if (!AppConstants.verifyPassword(password, userData['password'])) {
        throw AuthException('Mot de passe incorrect');
      }

      final token = AppConstants.generateJwtToken(userData['id'].toString());

      await _supabase
          .from('users')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userData['id']);

      await _storage.write(key: 'token', value: token);

      return User.fromJson(userData);
    } catch (e) {
      _logger.e('Erreur lors de la connexion : $e');
      throw AuthException('Échec de la connexion : ${e.toString()}');
    }
  }

  /// Connexion avec Google
  Future<User> signInWithGoogle() async {
    try {
      final GoogleSignIn signIn = GoogleSignIn.instance;

      await signIn.initialize(
        clientId: dotenv.env['GOOGLE_CLIENT_ID'],
        serverClientId: dotenv.env['GOOGLE_SERVER_CLIENT_ID'],
      );

      final GoogleSignInAccount account = await signIn.authenticate();

      final GoogleSignInAuthentication auth = account.authentication;
      final String? idToken = auth.idToken;

      if (idToken == null) {
        throw Exception("ID Token manquant.");
      }

      final email = account.email;
      final displayName = account.displayName ?? '';
      final photoUrl = account.photoUrl ?? '';
      final firstName = displayName.split(' ').first;
      final lastName = displayName.split(' ').length > 1
          ? displayName.split(' ').last
          : '';

      final userData = await _supabase
          .from('users')
          .select()
          .eq('id', email)
          .maybeSingle();

      User user;
      if (userData == null) {
        final userResponse = await _supabase
            .from('users')
            .insert({
              'email': email,
              'first_name': firstName,
              'last_name': lastName,
              'username': email.split('@').first,
              'avatar_url': photoUrl,
              'gender': '',
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .select()
            .single();

        user = User.fromJson(userResponse);
      } else {
        // Mettre à jour la date de mise à jour
        await _supabase
            .from('users')
            .update({'updated_at': DateTime.now().toIso8601String()})
            .eq('email', email);
        user = User.fromJson(userData);
      }

      // Générer et stocker le token JWT
      final token = AppConstants.generateJwtToken(user.id!);
      await _storage.write(key: 'token', value: token);

      return user;
    } catch (e) {
      _logger.e('Erreur lors de la connexion avec Google : $e');
      throw AuthException(
        'Échec de la connexion avec Google : ${e.toString()}',
      );
    }
  }

  /// Inscription d'un nouvel utilisateur
  Future<User> signUp({required User user, File? avatar}) async {
    try {
      if (!AppConstants.isValidEmail(user.email)) {
        throw AuthException('Format d\'email invalide');
      }

      if (!AppConstants.isValidPassword(user.password)) {
        throw AuthException(
          'Le mot de passe doit contenir au moins 8 caractères, incluant une majuscule, une minuscule et un chiffre',
        );
      }

      if (user.firstName.length > _maxNameLength ||
          user.lastName.length > _maxNameLength) {
        throw AuthException(
          'Les noms ne doivent pas dépasser $_maxNameLength caractères',
        );
      }

      final hashedPassword = AppConstants.hashPassword(user.password);

      String? avatarUrl;
      if (avatar != null) {
        final fileName =
            '${user.email}_${DateTime.now().millisecondsSinceEpoch}';
        await _supabase.storage.from('avatars').upload(fileName, avatar);
        avatarUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      }

      final userResponse = await _supabase
          .from('users')
          .insert({
            'first_name': user.firstName.trim(),
            'last_name': user.lastName.trim(),
            'email': user.email.toLowerCase().trim(),
            'username': user.username.trim(),
            'password': hashedPassword,
            'avatar_url': avatarUrl,
            'address': user.address?.trim(),
            'gender': user.gender,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      return User.fromJson(userResponse);
    } catch (e) {
      _logger.e('Erreur lors de l\'inscription : $e');
      throw AuthException('Échec de l\'inscription : ${e.toString()}');
    }
  }

  /// Envoi d'un code de vérification par email
  Future<void> sendVerificationCode(String email) async {
    try {
      if (!AppConstants.isValidEmail(email)) {
        throw AuthException('Format d\'email invalide');
      }

      final userExists = await _supabase
          .from('users')
          .select('id')
          .eq('email', email.toLowerCase().trim())
          .maybeSingle();

      if (userExists != null) {
        throw AuthException('Cet email est déjà utilisé');
      }

      final code = AppConstants.generateOtp();
      final expiresAt = DateTime.now().add(
        const Duration(minutes: _otpExpirationMinutes),
      );

      final otpExists = await _supabase
          .from('verify_otps')
          .select('id')
          .eq('email', email.toLowerCase().trim())
          .maybeSingle();
      if (otpExists != null) {
        await _supabase
            .from('verify_otps')
            .update({
              'email': email.toLowerCase().trim(),
              'code': code,
              'expires_at': expiresAt.toIso8601String(),
            })
            .eq('email', email.toLowerCase().trim());
      } else {
        await _supabase.from('verify_otps').insert({
          'email': email.toLowerCase().trim(),
          'code': code,
          'expires_at': expiresAt.toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      await AppConstants.sendEmail(
        email: email,
        subject: 'Vérification de votre adresse email',
        content: AppConstants.buildVerificationEmailContent(code),
      );
    } catch (e) {
      _logger.e('Erreur lors de l\'envoi du code de vérification : $e');
      throw AuthException('Échec de l\'envoi du code : ${e.toString()}');
    }
  }

  /// Vérification du code OTP
  Future<void> verifyOtpCode({
    required String email,
    required String code,
  }) async {
    try {
      if (!AppConstants.isValidEmail(email)) {
        throw AuthException('Format d\'email invalide');
      }

      if (!AppConstants.isValidOtp(code)) {
        throw AuthException('Format de code invalide');
      }

      final existingOtp = await _supabase
          .from('verify_otps')
          .select()
          .eq('email', email.toLowerCase().trim())
          .eq('code', code)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existingOtp == null) {
        throw AuthException('Code invalide ou expiré');
      }
    } catch (e) {
      _logger.e('Erreur lors de la vérification du code OTP : $e');
      throw AuthException('Échec de la vérification : ${e.toString()}');
    }
  }

  /// Déconnexion de l'utilisateur
  Future<void> signOut() async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null || !AppConstants.isValidJwtToken(token)) {
        throw AuthException('Token invalide ou absent');
      }

      final decodedToken = JwtDecoder.decode(token);
      final userId = decodedToken['sub'];

      await _supabase
          .from('users')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userId);

      await _storage.delete(key: 'token');
    } catch (e) {
      _logger.e('Erreur lors de la déconnexion : $e');
      throw AuthException('Échec de la déconnexion : ${e.toString()}');
    }
  }

  /// Demande de réinitialisation de mot de passe
  Future<void> requestPasswordReset(String email) async {
    try {
      if (!AppConstants.isValidEmail(email)) {
        throw AuthException('Format d\'email invalide');
      }

      final user = await _supabase
          .from('users')
          .select('id')
          .eq('email', email.toLowerCase().trim())
          .maybeSingle();

      if (user == null) {
        throw AuthException('Email non trouvé');
      }

      final code = AppConstants.generateOtp();
      final expiresAt = DateTime.now().add(
        const Duration(minutes: _resetTokenExpirationMinutes),
      );

      await _supabase
          .from('users')
          .update({
            'reset_code': code,
            'reset_expires': expiresAt.toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user['id']);

      await AppConstants.sendEmail(
        email: email,
        subject: 'Réinitialisation de votre mot de passe',
        content: AppConstants.buildResetEmailContent(code),
      );
    } catch (e) {
      _logger.e('Erreur lors de la demande de réinitialisation : $e');
      throw AuthException(
        'Échec de la demande de réinitialisation : ${e.toString()}',
      );
    }
  }

  /// Réinitialisation du mot de passe
  Future<void> resetPassword({
    required String code,
    required String password,
    required String email,
  }) async {
    try {
      if (!AppConstants.isValidPassword(password)) {
        throw AuthException('Mot de passe invalide');
      }

      final user = await _supabase
          .from('users')
          .select()
          .eq('reset_code', code)
          .eq('email', email.toLowerCase().trim())
          .gt('reset_expires', DateTime.now().toIso8601String())
          .maybeSingle();

      if (user == null) {
        throw AuthException('Code invalide ou expiré');
      }

      final hashedPassword = AppConstants.hashPassword(password);

      await _supabase
          .from('users')
          .update({
            'password': hashedPassword,
            'reset_code': null, 
            'reset_expires': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('email', email.toLowerCase().trim());
    } catch (e) {
      _logger.e('Erreur lors de la réinitialisation du mot de passe : $e');
      throw AuthException('Échec de la réinitialisation : ${e.toString()}');
    }
  }

  /// Vérification du code de réinitialisation
  Future<void> verifyResetCode({
    required String code,
    required String email,
  }) async {
    try {
      final user = await _supabase
          .from('users')
          .select()
          .eq('reset_code', code)
          .eq('email', email.toLowerCase().trim())
          .gt('reset_expires', DateTime.now().toIso8601String())
          .maybeSingle();

      if (user == null) {
        throw AuthException('Code invalide ou expiré');
      }
    } catch (e) {
      _logger.e(
        'Erreur lors de la vérification du code de réinitialisation : $e',
      );
      throw AuthException('Échec de la vérification : ${e.toString()}');
    }
  }

  /// Récupération de l'utilisateur connecté
  Future<User> getCurrentUser() async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null || !AppConstants.isValidJwtToken(token)) {
        throw AuthException('Token invalide ou absent');
      }

      final decodedToken = JwtDecoder.decode(token);
      final userId = decodedToken['sub'];

      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        throw AuthException('Utilisateur non trouvé');
      }

      return User.fromJson(response);
    } catch (e) {
      _logger.e('Erreur lors de la récupération de l\'utilisateur : $e');
      throw AuthException(
        'Échec de la récupération de l\'utilisateur : ${e.toString()}',
      );
    }
  }
}
