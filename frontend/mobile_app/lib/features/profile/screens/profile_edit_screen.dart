import 'package:flutter/material.dart';
import '../profile_api.dart';

class ProfileEditScreen extends StatefulWidget {
  final ProfileApi api;
  final Map<String, dynamic> initial;

  const ProfileEditScreen({
    super.key,
    required this.api,
    required this.initial,
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _birthYearCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _weightCtrl;

  // sadece: belirtmek istemiyorum (null), male, female
  String? _gender; // null = belirtmek istemiyorum
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;

    _fullNameCtrl = TextEditingController(text: (i['full_name'] ?? '').toString());

    final by = i['birth_year'];
    _birthYearCtrl = TextEditingController(text: by == null ? '' : by.toString());

    final h = i['height_cm'];
    _heightCtrl = TextEditingController(text: h == null ? '' : h.toString());

    final w = i['weight_kg'];
    _weightCtrl = TextEditingController(text: w == null ? '' : w.toString());

    final g = (i['gender'] ?? '').toString().trim().toLowerCase();
    _gender = (g == 'male' || g == 'female') ? g : null;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _birthYearCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  bool _hasAnyInitialValue() {
    final i = widget.initial;
    bool has(dynamic v) => v != null && v.toString().trim().isNotEmpty;
    return has(i['full_name']) || has(i['birth_year']) || has(i['gender']) || has(i['height_cm']) || has(i['weight_kg']);
  }

  String? _strOrNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  int? _intOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  double? _doubleOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    setState(() => _error = null);

    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'full_name': _strOrNull(_fullNameCtrl.text),
        'birth_year': _intOrNull(_birthYearCtrl.text),
        'gender': _gender, // null / male / female
        'height_cm': _intOrNull(_heightCtrl.text),
        'weight_kg': _doubleOrNull(_weightCtrl.text),
      };

      await widget.api.updateProfile(payload);

      if (!mounted) return;

      // Mesaj EDIT ekranında
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşleminiz başarıyla gerçekleşti')),
      );

      // kısa bir an görünsün, sonra geri dön
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUpdate = _hasAnyInitialValue();
    final buttonText = isUpdate ? 'Güncelle' : 'Kaydet';

    return Scaffold(
      appBar: AppBar(title: const Text('Kişisel Bilgiler')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: _fullNameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Ad Soyad',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.length > 120) return '120 karakteri geçemez';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _birthYearCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Doğum Yılı',
                  hintText: '2002',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  final n = int.tryParse(t);
                  if (n == null) return 'Sayı olmalı';
                  if (n < 1900) return '1900 sonrası olmalı';
                  final yearNow = DateTime.now().year;
                  if (n > yearNow) return 'Gelecek yıl olmaz';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String?>(
                value: _gender,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Belirtmek istemiyorum')),
                  DropdownMenuItem(value: 'male', child: Text('Erkek')),
                  DropdownMenuItem(value: 'female', child: Text('Kadın')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _gender = v),
                decoration: const InputDecoration(
                  labelText: 'Cinsiyet',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _heightCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Boy (cm)',
                  hintText: '180',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  final n = int.tryParse(t);
                  if (n == null) return 'Sayı olmalı';
                  if (n < 40 || n > 260) return '40–260 arası olmalı';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Kilo (kg)',
                  hintText: '75.5',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  final n = double.tryParse(t.replaceAll(',', '.'));
                  if (n == null) return 'Sayı olmalı';
                  if (n < 2 || n > 400) return '2–400 arası olmalı';
                  return null;
                },
                onFieldSubmitted: (_) => _saving ? null : _save(),
              ),
              const SizedBox(height: 20),

              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : Text(buttonText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}