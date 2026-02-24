import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api_client.dart';
import '../drugs_api.dart';

class DrugFormScreen extends StatefulWidget {
  final ApiClient client;
  final Map<String, dynamic>? existingDrug; // null => create

  const DrugFormScreen({
    super.key,
    required this.client,
    this.existingDrug,
  });

  @override
  State<DrugFormScreen> createState() => _DrugFormScreenState();
}

class _DrugFormScreenState extends State<DrugFormScreen> {
  late final DrugsApi api;

  final nameCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  final qtyCtrl = TextEditingController();
  final unitCtrl = TextEditingController(text: 'tablet');
  final thresholdCtrl = TextEditingController();

  // 🔥 AUTOCOMPLETE: FocusNode kesinlikle state’te olmalı (her build’de yeni node üretme!)
  final FocusNode nameFocusNode = FocusNode();

  final formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> schedules = [];
  List<String> suggestions = [];
  bool suggesting = false;

  Timer? _debounce;

  bool get isEdit => widget.existingDrug != null;

  @override
  void initState() {
    super.initState();
    api = DrugsApi(widget.client);

    if (isEdit) {
      final d = widget.existingDrug!;
      nameCtrl.text = (d['drug_name'] ?? '').toString();
      notesCtrl.text = (d['notes'] ?? '').toString();

      schedules = [];
      for (final s in (d['schedules'] ?? []) as List<dynamic>) {
        schedules.add({
          // stable key: schedule_id varsa onu kullan
          '_key': (s['schedule_id'] ?? '${s['time_of_day']}-${s.hashCode}').toString(),
          'time_of_day': s['time_of_day'],
          // eski kayıt "1 tablet" ise "1" çekmeye çalış
          'dose_text': _extractLeadingIntString((s['dose_text'] ?? '').toString()).isEmpty
              ? '1'
              : _extractLeadingIntString((s['dose_text'] ?? '').toString()),
          'days_mask': s['days_mask'] ?? 127,
          'is_active': s['is_active'] ?? true,
        });
      }

      final inv = d['inventory'];
      if (inv != null) {
        qtyCtrl.text = (inv['quantity'] ?? '').toString();
        unitCtrl.text = (inv['unit'] ?? 'tablet').toString();
        thresholdCtrl.text = (inv['low_threshold'] ?? '').toString();
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    nameCtrl.dispose();
    notesCtrl.dispose();
    qtyCtrl.dispose();
    unitCtrl.dispose();
    thresholdCtrl.dispose();
    nameFocusNode.dispose();
    super.dispose();
  }

  static String _extractLeadingIntString(String s) {
    final m = RegExp(r'^\s*(\d+)').firstMatch(s);
    return (m?.group(1) ?? s.trim());
  }

  void _onNameChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      setState(() => suggestions = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => suggesting = true);
      try {
        final res = await api.suggest(query);
        if (!mounted) return;

        // backend DISTINCT dönüyor ama frontta da garantiye al
        final uniq = res.toSet().toList()..sort();

        setState(() => suggestions = uniq);

        // 🔥 dropdown açılma problemine “yardımcı” olur:
        // focus’u kaybetmediği sürece options view daha stabil açılır.
        if (nameFocusNode.hasFocus) {
          // requestFocus tekrar çağrısı dropdown davranışını toparlıyor
          nameFocusNode.requestFocus();
        }
      } finally {
        if (mounted) setState(() => suggesting = false);
      }
    });
  }

  TimeOfDay _parseTime(String t) {
    final parts = t.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '9') ?? 9;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) async {
    return showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: const Locale('tr', 'TR'),
          child: child!,
        );
      },
    );
  }

  String _fmtTime(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  Future<void> _addScheduleWithPicker() async {
    final picked = await _pickTime(const TimeOfDay(hour: 9, minute: 0));
    if (picked == null) return;

    final time = _fmtTime(picked);

    final exists = schedules.any((s) => (s['time_of_day'] ?? '').toString() == time);
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu saat zaten ekli.')),
      );
      return;
    }

    setState(() {
      schedules.add({
        '_key': DateTime.now().microsecondsSinceEpoch.toString(),
        'time_of_day': time,
        'dose_text': '1', // ✅ boş kalmasın
        'days_mask': 127,
        'is_active': true,
      });
    });
  }

  Future<void> _editScheduleTime(int idx) async {
    final s = schedules[idx];
    final current = (s['time_of_day'] ?? '09:00:00').toString();
    final picked = await _pickTime(_parseTime(current));
    if (picked == null) return;

    final newTime = _fmtTime(picked);

    final exists = schedules.asMap().entries.any((e) =>
    e.key != idx && (e.value['time_of_day']?.toString() == newTime));
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu saat zaten ekli.')),
      );
      return;
    }

    setState(() {
      s['time_of_day'] = newTime;
    });
  }

  bool _isPositiveIntString(String s) {
    final t = s.trim();
    final n = int.tryParse(t);
    return n != null && n > 0;
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;

    if (schedules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az 1 kullanım saati eklemelisin.')),
      );
      return;
    }

    // ✅ DOZ validasyonu: boş olamaz, pozitif int
    for (final s in schedules) {
      final dose = (s['dose_text'] ?? '').toString().trim();
      if (!_isPositiveIntString(dose)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Doz boş olamaz ve sayı olmalı. Örn: 1')),
        );
        return;
      }
    }

    // inventory: boş bırakılabilir, ama doldurulmuşsa int olmalı
    Map<String, dynamic>? inventory;
    final qtyText = qtyCtrl.text.trim();
    final thText = thresholdCtrl.text.trim();
    final unitText = unitCtrl.text.trim();

    if (qtyText.isNotEmpty || thText.isNotEmpty || unitText.isNotEmpty) {
      final qty = qtyText.isEmpty ? null : int.tryParse(qtyText);
      final th = thText.isEmpty ? null : int.tryParse(thText);

      if (qty == null || th == null || unitText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stok alanları geçersiz. Miktar/eşik sayı olmalı.')),
        );
        return;
      }

      inventory = {
        'quantity': qty,
        'unit': unitText,
        'low_threshold': th,
      };
    }

    final payload = <String, dynamic>{
      'drug_name': nameCtrl.text.trim(),
      'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      'schedules': schedules
          .map((s) => {
        'time_of_day': s['time_of_day'],
        'dose_text': (s['dose_text'] ?? '').toString().trim(), // sadece sayı string’i
        'days_mask': s['days_mask'] ?? 127,
        'is_active': s['is_active'] ?? true,
      })
          .toList(),
      'inventory': inventory,
    };

    try {
      if (isEdit) {
        final id = widget.existingDrug!['user_drug_id'].toString();
        await api.updateDrug(id, payload);
      } else {
        await api.createDrug(payload);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme hatası: $e')),
      );
    }
  }

  Widget _drugNameAutocomplete() {
    return RawAutocomplete<String>(
      textEditingController: nameCtrl,
      focusNode: nameFocusNode, // ✅ tek focus node
      optionsBuilder: (TextEditingValue value) {
        final q = value.text.trim();
        if (q.length < 2) return const Iterable<String>.empty();
        return suggestions.where((s) => s.toLowerCase().contains(q.toLowerCase()));
      },
      onSelected: (s) {
        nameCtrl.text = s;
        setState(() => suggestions = []);
        FocusScope.of(context).unfocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return 'İlaç adı zorunlu';
            return null;
          },
          decoration: InputDecoration(
            labelText: 'İlaç adı',
            prefixIcon: const Icon(Icons.medication_outlined),
            suffixIcon: suggesting
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
                : null,
          ),
          onChanged: _onNameChanged,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        if (options.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: options.take(8).map((opt) {
                  return ListTile(
                    leading: const Icon(Icons.search_rounded),
                    title: Text(opt),
                    onTap: () => onSelected(opt),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'İlaç Düzenle' : 'İlaç Ekle'),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _drugNameAutocomplete(),
            const SizedBox(height: 12),
            TextFormField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Not (opsiyonel)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 18),

            Text('Kullanım Saatleri',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),

            if (schedules.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 10),
                    Expanded(
                        child: Text('Henüz saat eklemedin. “Saat ekle” ile ekle.')),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            ...schedules.asMap().entries.map((entry) {
              final idx = entry.key;
              final s = entry.value;

              return Container(
                key: ValueKey(s['_key']),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.black.withOpacity(0.03),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center, // hizayı sabitle
                      children: [
                        const Icon(Icons.schedule_rounded),
                        const SizedBox(width: 8),
                        Text(
                          (s['time_of_day'] ?? '').toString(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Saati düzenle',
                          icon: const Icon(Icons.edit_rounded),
                          onPressed: () => _editScheduleTime(idx),
                        ),
                        IconButton(
                          tooltip: 'Sil',
                          onPressed: () => setState(() => schedules.removeAt(idx)),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // DOZ: sadece sayı, zorunlu
                    TextFormField(
                      initialValue: (s['dose_text'] ?? '').toString(),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Doz (sayı) — ör: 1',
                        prefixIcon: Icon(Icons.local_pharmacy_outlined),
                      ),
                      onChanged: (v) => s['dose_text'] = v,
                    ),

                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: (s['is_active'] ?? true) == true,
                      onChanged: (v) => setState(() => s['is_active'] = v),
                      title: const Text('Aktif'),
                    ),
                  ],
                ),
              );
            }),

            TextButton.icon(
              onPressed: _addScheduleWithPicker,
              icon: const Icon(Icons.add_alarm_rounded),
              label: const Text('Saat ekle'),
            ),

            const SizedBox(height: 18),
            Text('Stok', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Miktar',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: unitCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Birim',
                      prefixIcon: Icon(Icons.straighten_rounded),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: thresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Azaldı eşiği',
                prefixIcon: Icon(Icons.warning_amber_rounded),
              ),
            ),

            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}