import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:logger/logger.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:toxtalk/models/user.dart';
import 'package:toxtalk/utils/constants.dart';

class UserServiceException implements Exception {
  final String message;
  UserServiceException(this.message);
}

class UserService {
  static const _maxNameLength = 255;
  static final _logger = Logger();

  final _supabase = supa.Supabase.instance.client;
  final _storage = const FlutterSecureStorage();

  Future<List<User>> getAllUsers() async {
    try {
      final response = await _supabase.from('users').select();

      final data = response as List<dynamic>;
      return data.map((json) => User.fromJson(json)).toList();
    } catch (e) {
      _logger.e(
        'Erreur inattendue lors de la récupération des utilisateurs : $e',
      );
      throw UserServiceException(
        'Échec de la récupération des utilisateurs : ${e.toString()}',
      );
    }
  }

  Future<User?> getUserById(String id) async {
    try {
      if (id.isEmpty) {
        throw UserServiceException(
          'L\'ID de l\'utilisateur ne peut pas être vide',
        );
      }

      final response = await _supabase
          .from('users')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response != null) {
        _logger.e(
          'Erreur lors de la récupération de l\'utilisateur : ${response}',
        );
        throw UserServiceException(
          'Échec de la récupération de l\'utilisateur : ${response}',
        );
      }

      if (response == null) {
        return null;
      }

      return User.fromJson(response);
    } catch (e) {
      _logger.e(
        'Erreur inattendue lors de la récupération de l\'utilisateur : $e',
      );
      throw UserServiceException(
        'Échec de la récupération de l\'utilisateur : ${e.toString()}',
      );
    }
  }

  Future<void> updateUser(User user, File? avatar) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null || !AppConstants.isValidJwtToken(token)) {
        throw UserServiceException('Token invalide ou absent');
      }

      final decodedToken = JwtDecoder.decode(token);
      final userId = decodedToken['sub'];
      if (user.id != userId) {
        throw UserServiceException(
          'Vous ne pouvez pas modifier un autre utilisateur',
        );
      }

      if (user.firstName.length > _maxNameLength ||
          user.lastName.length > _maxNameLength) {
        throw UserServiceException(
          'Les noms ne doivent pas dépasser $_maxNameLength caractères',
        );
      }
      if (!AppConstants.isValidEmail(user.email)) {
        throw UserServiceException('Format d\'email invalide');
      }
      if (user.username.length > _maxNameLength) {
        throw UserServiceException(
          'Le pseudo ne doit pas dépasser $_maxNameLength caractères',
        );
      }

      String? avatarUrl = user.avatarUrl;
      if (avatar != null) {
        final fileName =
            '${user.email}_${DateTime.now().millisecondsSinceEpoch}';
        await _supabase.storage.from('avatars').upload(fileName, avatar);
        avatarUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      }

      final updates = {
        'first_name': user.firstName.trim(),
        'last_name': user.lastName.trim(),
        'email': user.email.toLowerCase().trim(),
        'username': user.username.trim(),
        'avatar_url': avatarUrl,
        'gender': user.gender,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from('users')
          .update(updates)
          .eq('id', user.id!);

      if (response.error != null) {
        _logger.e(
          'Erreur lors de la mise à jour de l\'utilisateur : ${response.error!.message}',
        );
        throw UserServiceException(
          'Échec de la mise à jour de l\'utilisateur : ${response.error!.message}',
        );
      }
    } catch (e) {
      _logger.e(
        'Erreur inattendue lors de la mise à jour de l\'utilisateur : $e',
      );
      throw UserServiceException(
        'Échec de la mise à jour de l\'utilisateur : ${e.toString()}',
      );
    }
  }

  /// Met à jour le mot de passe d'un utilisateur
  Future<void> updatePassword(String email, String newPassword) async {
    try {
      // Vérifier le token de l'utilisateur connecté
      final token = await _storage.read(key: 'token');
      if (token == null || !AppConstants.isValidJwtToken(token)) {
        throw UserServiceException('Token invalide ou absent');
      }

      final decodedToken = JwtDecoder.decode(token);
      final userId = decodedToken['sub'];

      // Vérifier que l'email correspond à l'utilisateur connecté
      final userData = await _supabase
          .from('users')
          .select('id, email')
          .eq('id', userId)
          .single();
      if (userData['email'] != email.toLowerCase().trim()) {
        throw UserServiceException(
          'Vous ne pouvez pas modifier le mot de passe d\'un autre utilisateur',
        );
      }

      // Valider le mot de passe
      if (!AppConstants.isValidPassword(newPassword)) {
        throw UserServiceException(
          'Le mot de passe doit contenir au moins 8 caractères, incluant une majuscule, une minuscule et un chiffre',
        );
      }

      // Hacher le mot de passe
      final hashedPassword = AppConstants.hashPassword(newPassword);

      final response = await _supabase
          .from('users')
          .update({
            'password': hashedPassword,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('email', email.toLowerCase().trim());

      if (response.error != null) {
        _logger.e(
          'Erreur lors de la mise à jour du mot de passe : ${response.error!.message}',
        );
        throw UserServiceException(
          'Échec de la mise à jour du mot de passe : ${response.error!.message}',
        );
      }
    } catch (e) {
      _logger.e(
        'Erreur inattendue lors de la mise à jour du mot de passe : $e',
      );
      throw UserServiceException(
        'Échec de la mise à jour du mot de passe : ${e.toString()}',
      );
    }
  }

  /// Supprime un utilisateur
  Future<void> deleteUser(String id) async {
    try {
      // Vérifier le token de l'utilisateur connecté
      final token = await _storage.read(key: 'token');
      if (token == null || !AppConstants.isValidJwtToken(token)) {
        throw UserServiceException('Token invalide ou absent');
      }

      final decodedToken = JwtDecoder.decode(token);
      final userId = decodedToken['sub'];
      if (id != userId) {
        throw UserServiceException(
          'Vous ne pouvez pas supprimer un autre utilisateur',
        );
      }

      final response = await _supabase.from('users').delete().eq('id', id);

      if (response.error != null) {
        _logger.e(
          'Erreur lors de la suppression de l\'utilisateur : ${response.error!.message}',
        );
        throw UserServiceException(
          'Échec de la suppression de l\'utilisateur : ${response.error!.message}',
        );
      }

      // Supprimer le token après la suppression
      await _storage.delete(key: 'token');
    } catch (e) {
      _logger.e(
        'Erreur inattendue lors de la suppression de l\'utilisateur : $e',
      );
      throw UserServiceException(
        'Échec de la suppression de l\'utilisateur : ${e.toString()}',
      );
    }
  }
}
