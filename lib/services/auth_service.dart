import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:logger/logger.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:toxtalk/models/User.dart';
import 'package:toxtalk/utils/constants.dart';

class AuthService {
  static const _otpExpirationMinutes = 5;
  static const _resetTokenExpirationMinutes = 15;
  static const _maxNameLength = 255;
  static final _logger = Logger();

  final supabase = supa.Supabase.instance.client;
  final storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> register({required User user}) async {
    try {
      if (user.firstName.isEmpty || user.lastName.length > _maxNameLength) {
        throw Exception(
          'Le nom est requis et doit contenir moins de $_maxNameLength caractères',
        );
      }

      if (!AppConstants.isValidEmail(user.email)) {
        throw Exception('Format d\'email invalide');
      }

      if (!AppConstants.isValidPassword(user.password)) {
        throw Exception(
          'Le mot de passe doit contenir au moins 8 caractères avec une majuscule, une minuscule, un chiffre et un caractère spécial',
        );
      }

      final existingUser = await supabase
          .from('users')
          .select('email')
          .eq('email', user.email)
          .maybeSingle();

      if (existingUser != null) {
        throw Exception('Email déjà utilisé');
      }

      await supabase
          .from('verify_otps')
          .delete()
          .eq('email', user.email);

      final verificationCode = AppConstants.generateOtp();

      await AppConstants.sendEmail(
        email: user.email,
        subject: 'Vérification de l\'email',
        content: AppConstants.buildVerificationEmailContent(verificationCode),
      );

      await supabase.from('verify_otps').insert({
        'email': user.email,
        'code': verificationCode,
        'expires_at': DateTime.now()
            .add(const Duration(minutes: _otpExpirationMinutes))
            .toIso8601String(),
      });

      return {'message': 'Code de vérification envoyé à votre email'};
    } catch (e) {
      _logger.e('Erreur lors de l\'enregistrement : $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required User user,
    required String code,
  }) async {
    try {
      if (!AppConstants.isValidOtp(code)) {
        throw Exception('Le code doit être un nombre à 6 chiffres');
      }

      final verification = await supabase
          .from('verify_otps')
          .select()
          .eq('email', user.email)
          .eq('code', code)
          .gt('expires_at', DateTime.now().toIso8601String())
          .maybeSingle();

      if (verification == null) {
        throw Exception('Code invalide ou expiré.');
      }

      final hashedPassword = AppConstants.hashPassword(user.password);

final userResponse = await supabase
          .from('users')
          .insert({
            'first_name': user.firstName,
            'last_name': user.lastName,
            'email': user.email,
            'username': user.username,
            'password': hashedPassword,
            'avatar_url': user.avatarUrl,
            'address': user.address,
            'gender': user.gender,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();


      final token = AppConstants.generateJwtToken(
        userResponse['id'].toString()
      );

      await supabase
          .from('verify_otps')
          .delete()
          .eq('email', user.email);
      await storage.write(key: 'token', value: token);

      return {
        'token': token,
        'id': userResponse['id'],
      };
    } catch (e) {
      _logger.e('Erreur lors de la vérification OTP : $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      if (!AppConstants.isValidEmail(email)) {
        throw Exception('Format d\'email invalide');
      }

      final userData = await supabase
          .from('users')
          .select()
          .eq('email', email)
          .single();

      if (!AppConstants.verifyPassword(password, userData['password'])) {
        throw Exception('Mot de passe incorrect');
      }

      final token = AppConstants.generateJwtToken(
        userData['id'].toString(),
      );

      await supabase
          .from('users')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userData['id']);

      await storage.write(key: 'token', value: token);

      return {
        'token': token,
        'id': userData['id'],
      };
    } catch (e) {
      _logger.e('Erreur de connexion : $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      final token = await storage.read(key: 'token');
      if (token == null || !AppConstants.isValidJwtToken(token)) {
        throw Exception('Token invalide ou absent');
      }

      final decodedToken = JwtDecoder.decode(token);
      final userId = decodedToken['sub'];

      await supabase
          .from('users')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userId);

      await storage.delete(key: 'token');
    } catch (e) {
      _logger.e('Erreur de déconnexion : $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      if (!AppConstants.isValidEmail(email)) {
        throw Exception('Format d\'email invalide');
      }

      final user = await supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (user == null) {
        throw Exception('Email non trouvé');
      }

      final token = AppConstants.generateOtp();
      final expiresAt = DateTime.now().add(
        const Duration(minutes: _resetTokenExpirationMinutes),
      );

      await supabase
          .from('users')
          .update({
            'reset_code': token,
            'reset_expires': expiresAt.toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user['id']);

      await AppConstants.sendEmail(
        email: email,
        subject: 'Réinitialisation du mot de passe',
        content: AppConstants.buildResetEmailContent(token),
      );

      return {'message': 'Token de réinitialisation envoyé à votre email'};
    } catch (e) {
      _logger.e('Erreur mot de passe oublié : $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> resetPassword({
    required String code,
    required String password,
    required String email,
  }) async {
    try {
      if (!AppConstants.isValidPassword(password)) {
        throw Exception('Mot de passe invalide');
      }

      final user = await supabase
          .from('users')
          .select()
          .eq('reset_code', code)
          .eq('email', email)
          .gt('reset_expires', DateTime.now().toIso8601String())
          .maybeSingle();

      if (user == null) {
        throw Exception('Token invalide ou expiré');
      }

      final hashedPassword = AppConstants.hashPassword(password);

      await supabase
          .from('users')
          .update({
            'password': hashedPassword,
            'reset_code': null,
            'reset_expires': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('email', email);

      return {'message': 'Mot de passe réinitialisé avec succès'};
    } catch (e) {
      _logger.e('Erreur de réinitialisation : $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> verifyResetCode({
    required String code,
    required String email,
  }) async {
    try {
      final user = await supabase
          .from('users')
          .select()
          .eq('reset_code', code)
          .eq('email', email)
          .gt('reset_expires', DateTime.now().toIso8601String())
          .maybeSingle();

      if (user == null) {
        throw Exception('Token invalide ou expiré');
      }

      return {'message': 'Code valide'};
    } catch (e) {
      _logger.e('Erreur de vérification du code : $e');
      rethrow;
    }
  }

  Future<User> getCurrentUser() async {
    try {
      final token = await storage.read(key: 'token');
      if (token == null || !AppConstants.isValidJwtToken(token)) {
        throw Exception('Token invalide ou absent');
      }
      final decodedToken = JwtDecoder.decode(token);
      final userId = decodedToken['sub'];
      final response = await supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (response == null) {
        throw Exception('Utilisateur non trouvé');
      }
      return User.fromJson(response);
    } catch (e) {
      _logger.e(
        'Erreur lors de la récupération de l\'utilisateur courant : $e',
      );
      rethrow;
    }
  }
}
