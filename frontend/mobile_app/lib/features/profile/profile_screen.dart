import 'package:flutter/material.dart';
import '../auth/auth_api.dart';
import '../../core/api_client.dart';
import 'profile_api.dart';

import 'screens/profile_edit_screen.dart';
import 'screens/diseases_screen.dart';
import 'screens/allergies_screen.dart';
import 'screens/disliked_ingredients_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ApiClient client;
  final AuthApi authApi;

  const ProfileScreen({
    super.key,
    required this.client,
    required this.authApi,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileApi _api;

  Map<String, dynamic>? _me;
  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _api = ProfileApi(widget.client);
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = await _api.me();
      final profile = await _api.getProfile();
      if (!mounted) return;
      setState(() {
        _me = me;
        _profile = profile;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _genderLabel(String? raw) {
    final g = (raw ?? '').trim().toLowerCase();
    if (g == 'male') return 'Erkek';
    if (g == 'female') return 'Kadın';
    return null;
  }

  bool _hasAnyProfileValue(Map<String, dynamic>? p) {
    if (p == null) return false;

    bool hasStr(dynamic v) => v != null && v.toString().trim().isNotEmpty;
    bool hasNum(dynamic v) => v != null && v.toString().trim().isNotEmpty;

    return hasStr(p['full_name']) ||
        hasNum(p['birth_year']) ||
        hasStr(p['gender']) ||
        hasNum(p['height_cm']) ||
        hasNum(p['weight_kg']);
  }

  Future<void> _confirmLogout() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Çıkış'),
          content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Çıkış'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      await widget.authApi.logout();
      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hata: $_error', style: TextStyle(color: cs.error)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _busy ? null : _load, child: const Text('Tekrar Dene')),
            ],
          ),
        ),
      );
    }

    final email = _me?['email']?.toString() ?? '-';
    final fullName = _profile?['full_name']?.toString().trim();
    final birthYear = _profile?['birth_year']?.toString();
    final height = _profile?['height_cm']?.toString();
    final weight = _profile?['weight_kg']?.toString();
    final genderLabel = _genderLabel(_profile?['gender']?.toString());

    final subtitleParts = <String>[
      if (fullName != null && fullName.isNotEmpty) fullName,
      if (birthYear != null && birthYear.isNotEmpty) 'Doğum: $birthYear',
      if (genderLabel != null) 'Cinsiyet: $genderLabel',
      if (height != null && height.isNotEmpty) 'Boy: $height cm',
      if (weight != null && weight.isNotEmpty) 'Kilo: $weight kg',
    ];

    final subtitle = subtitleParts.join(' • ');
    final hasProfile = _hasAnyProfileValue(_profile);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.person, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle.isEmpty ? 'Profil bilgilerinizi tamamlayın' : subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text('Profil Ayarları', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),

          _MenuTile(
            icon: Icons.edit,
            title: 'Kişisel Bilgiler',
            subtitle: hasProfile ? 'Bilgileri güncelle' : 'Profil oluştur',
            onTap: () async {
              final saved = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileEditScreen(
                    api: _api,
                    initial: _profile ?? const {},
                  ),
                ),
              );

              // ✅ sadece reload. SnackBar yok.
              if (saved == true) {
                await _load();
              }
            },
          ),
          const SizedBox(height: 10),

          _MenuTile(
            icon: Icons.monitor_heart,
            title: 'Hastalıklar',
            subtitle: 'Kronik hastalıklar (filtreleme)',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DiseasesScreen(api: _api)),
              );
            },
          ),
          const SizedBox(height: 10),

          _MenuTile(
            icon: Icons.warning_amber,
            title: 'Alerjiler',
            subtitle: 'Mutlak eleme (allergen)',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AllergiesScreen(api: _api, client: widget.client)),
              );
            },
          ),
          const SizedBox(height: 10),

          _MenuTile(
            icon: Icons.block,
            title: 'Sevmediğim Besinler',
            subtitle: 'Tercih filtresi',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DislikedIngredientsScreen(api: _api, client: widget.client)),
              );
            },
          ),

          const SizedBox(height: 18),
          Text('Hesap', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),

          _MenuTile(
            icon: Icons.logout,
            title: 'Çıkış',
            subtitle: null,
            danger: true,
            onTap: _busy ? null : _confirmLogout,
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: danger ? cs.errorContainer : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: danger ? cs.onErrorContainer : cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}