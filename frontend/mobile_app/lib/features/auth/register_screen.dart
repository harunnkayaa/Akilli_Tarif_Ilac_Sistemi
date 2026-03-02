import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import 'auth_api.dart';

class RegisterScreen extends StatefulWidget {
  final AuthApi authApi;
  const RegisterScreen({super.key, required this.authApi});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();

  bool _loading = false;
  bool _pwHidden = true;
  bool _pw2Hidden = true;

  static const String _disclaimerTitle = 'Önemli Bilgilendirme';
  static const String _disclaimerMessage =
      'Bu uygulama teşhis veya tedavi amacı taşımaz; tıbbi tavsiye vermez.\n\n'
      'Tarif önerileri, mutfak/ilaç stok takibi, profil bilgileri (alerji, sevilmeyen besinler vb.) '
      've ilaç hatırlatma gibi özelliklerle daha kontrollü bir kullanım hedefler.\n\n'
      'Sağlıkla ilgili kararlar için doktorunuza/uzmanınıza danışın.';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _showDialog({
    required String title,
    required String message,
    String okText = 'Tamam',
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(okText),
          ),
        ],
      ),
    );
  }

  bool _isPasswordValid(String pw) {
    // en az 8, en az 1 harf ve 1 sayı
    final re = RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,}$');
    return re.hasMatch(pw);
  }

  String? _validate() {
    final email = _email.text.trim();
    final pw = _password.text;
    final pw2 = _password2.text;

    if (email.isEmpty) return 'E-posta boş olamaz.';
    if (!email.contains('@')) return 'Geçerli bir e-posta girin.';
    if (!_isPasswordValid(pw)) {
      return 'Şifre en az 8 karakter olmalı ve en az 1 harf + 1 sayı içermeli.';
    }
    if (pw != pw2) return 'Şifreler eşleşmiyor.';
    return null;
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    final err = _validate();
    if (err != null) {
      await _showDialog(title: 'Kayıt Uyarısı', message: err);
      return;
    }

    setState(() => _loading = true);

    try {
      await widget.authApi.register(
        email: _email.text.trim(),
        password: _password.text,
      );

      await _showDialog(
        title: 'Kayıt Başarılı',
        message: 'Hesabınız oluşturuldu. Giriş yapabilirsiniz.',
        okText: 'Devam',
      );

      await _showDialog(
        title: _disclaimerTitle,
        message: _disclaimerMessage,
        okText: 'Anladım',
      );

      if (!mounted) return;
      Navigator.pop(context); // login'e dön
    } on DioException catch (e) {
      final code = e.response?.statusCode;

      if (code == 409) {
        await _showDialog(
          title: 'Kayıt Başarısız',
          message: 'Bu e-posta adresiyle daha önce kayıt yapılmış.',
        );
      } else {
        await _showDialog(
          title: 'Kayıt Başarısız',
          message: 'Bir hata oluştu. Lütfen tekrar deneyin.',
        );
      }
    } catch (_) {
      await _showDialog(
        title: 'Kayıt Başarısız',
        message: 'Bir hata oluştu. Lütfen tekrar deneyin.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hesap Oluştur'),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.backgroundTop,
              AppColors.backgroundBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  elevation: 6,
                  shadowColor: Colors.black.withOpacity(0.10),
                  color: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Hadi başlayalım',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Birkaç saniyede hesabını oluştur.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'E-posta',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: _pwHidden,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Şifre',
                            helperText: 'En az 8 karakter, 1 harf + 1 sayı',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _pwHidden = !_pwHidden),
                              icon: Icon(_pwHidden
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password2,
                          obscureText: _pw2Hidden,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _loading ? null : _register(),
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Şifre (Tekrar)',
                            prefixIcon:
                                const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _pw2Hidden = !_pw2Hidden),
                              icon: Icon(_pw2Hidden
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loading ? null : _register,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                              _loading ? 'Kaydediliyor...' : 'Kayıt Ol'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}