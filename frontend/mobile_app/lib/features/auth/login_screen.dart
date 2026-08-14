import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import 'auth_api.dart';

class LoginScreen extends StatefulWidget {
  final AuthApi authApi;
  const LoginScreen({super.key, required this.authApi});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _pwHidden = true;
  bool _disclaimerShown = false;

  static const String _disclaimerTitle = 'Önemli Bilgilendirme';
  static const String _disclaimerMessage =
      'Bu uygulama teşhis veya tedavi amacı taşımaz; tıbbi tavsiye vermez.\n\n'
      'Tarif önerileri, mutfak/ilaç stok takibi, profil bilgileri (alerji, sevilmeyen besinler vb.) '
      've ilaç hatırlatma gibi özelliklerle daha kontrollü bir kullanım hedefler.\n\n'
      'Sağlıkla ilgili kararlar için doktorunuza/uzmanınıza danışın.';

  @override
  void initState() {
    super.initState();

    // Ekran açılır açılmaz bilgilendirme (1 kere)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disclaimerShown) return;
      _disclaimerShown = true;
      await _showDialog(
        title: _disclaimerTitle,
        message: _disclaimerMessage,
        okText: 'Anladım',
      );
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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

  String? _validate() {
    final email = _email.text.trim();
    final pw = _password.text;

    if (email.isEmpty) return 'E-posta boş olamaz.';
    if (!email.contains('@')) return 'Geçerli bir e-posta girin.';
    if (pw.isEmpty) return 'Şifre boş olamaz.';
    return null;
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    final err = _validate();
    if (err != null) {
      await _showDialog(title: 'Giriş Uyarısı', message: err);
      return;
    }

    setState(() => _loading = true);

    try {
      await widget.authApi.login(
        email: _email.text.trim(),
        password: _password.text,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/main');
    } on DioException catch (e) {
      final code = e.response?.statusCode;

      if (code == 401) {
        await _showDialog(
          title: 'Giriş Başarısız',
          message: 'E-posta veya şifre hatalı.',
        );
      } else if (code == 403) {
        await _showDialog(
          title: 'Giriş Engellendi',
          message: 'Hesabınız pasif görünüyor.',
        );
      } else {
        await _showDialog(
          title: 'Giriş Başarısız',
          message: 'Bir hata oluştu. Lütfen tekrar deneyin.',
        );
      }
    } catch (e) {
      await _showDialog(
        title: 'Giriş Başarısız',
        message: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
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
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(15),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/images/login_hero.png',
                            height: 160,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox(height: 120),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Akıllı Tarif ve İlaç\nYönetim Sistemi',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                                color: AppColors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: const [
                            _FeatureIcon(
                              icon: Icons.restaurant_menu_rounded,
                              label: 'Tarif Önerisi',
                              color: AppColors.accent,
                            ),
                            _FeatureIcon(
                              icon: Icons.inventory_2_rounded,
                              label: 'Stok Takibi',
                              color: AppColors.primary,
                            ),
                            _FeatureIcon(
                              icon: Icons.vaccines_rounded,
                              label: 'İlaç Hatırlatma',
                              color: AppColors.accent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Card(
                          elevation: 6,
                          shadowColor: Colors.black.withOpacity(0.10),
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Hoş geldiniz',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Devam etmek için giriş yap.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: AppColors.textSecondary),
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
                                    prefixIcon:
                                        Icon(Icons.alternate_email_rounded),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _password,
                                  obscureText: _pwHidden,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) =>
                                      _loading ? null : _login(),
                                  autofillHints: const [AutofillHints.password],
                                  decoration: InputDecoration(
                                    labelText: 'Şifre',
                                    prefixIcon:
                                        const Icon(Icons.lock_rounded),
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                          () => _pwHidden = !_pwHidden),
                                      icon: Icon(_pwHidden
                                          ? Icons.visibility
                                          : Icons.visibility_off),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _loading ? null : _login,
                                  child: Text(
                                    _loading
                                        ? 'Giriş yapılıyor...'
                                        : 'Giriş Yap',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton(
                                  onPressed: _loading
                                      ? null
                                      : () => Navigator.pushNamed(
                                          context, '/register'),
                                  child: const Text('Hesap Oluştur'),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Not: Bu uygulama tıbbi tavsiye vermez.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  tooltip: 'Bilgilendirme',
                  icon: const Icon(Icons.info_outline_rounded),
                  onPressed: () => _showDialog(
                    title: _disclaimerTitle,
                    message: _disclaimerMessage,
                    okText: 'Anladım',
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

class _FeatureIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _FeatureIcon({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 28, color: color),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}