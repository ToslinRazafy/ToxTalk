import 'package:flutter/material.dart';
import 'package:toxtalk/models/user.dart';
import 'package:toxtalk/page/auth/login_page.dart';
import 'package:toxtalk/page/auth/reset_password_page.dart';
import 'package:toxtalk/services/auth_service.dart';
import 'dart:io';

class VerifyOtpPage extends StatefulWidget {
  final File? avatar;
  final User user;
  final bool isRegister;

  const VerifyOtpPage({
    super.key,
    this.avatar,
    required this.user,
    this.isRegister = true,
  });

  @override
  State<VerifyOtpPage> createState() => _VerifyOtpPageState();
}

class _VerifyOtpPageState extends State<VerifyOtpPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _otpController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.isRegister) {
        // Vérification du code OTP pour l'inscription
        await _authService.verifyOtpCode(
          email: widget.user.email,
          code: _otpController.text.trim(),
        );

        // Inscription de l'utilisateur
        await _authService.signUp(user: widget.user, avatar: widget.avatar);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Inscription réussie ! Veuillez vous connecter.'),
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
        }
      } else {
        // Vérification du code de réinitialisation de mot de passe
        await _authService.verifyResetCode(
          email: widget.user.email,
          code: _otpController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Code de réinitialisation valide')),
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResetPasswordPage(
                email: widget.user.email,
                code: _otpController.text.trim(),
              ),
            ),
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Une erreur inattendue est survenue')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isRegister ? 'Vérification OTP' : 'Vérification du code',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isRegister
                    ? 'Vérifiez votre email'
                    : 'Vérifiez votre code',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isRegister
                    ? 'Entrez le code OTP envoyé à ${widget.user.email}'
                    : 'Entrez le code de réinitialisation envoyé à ${widget.user.email}',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _otpController,
                decoration: const InputDecoration(
                  labelText: 'Code OTP',
                  hintText: 'Entrez le code à 6 chiffres',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Veuillez entrer le code OTP';
                  }
                  if (!RegExp(r'^\d{6}$').hasMatch(value)) {
                    return 'Le code doit être composé de 6 chiffres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          widget.isRegister
                              ? 'Vérifier OTP'
                              : 'Vérifier le code',
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
