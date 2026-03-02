import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import '../../../core/app_colors.dart';
import '../drugs_api.dart';
import 'drug_form_screen.dart';
import 'drug_detail_screen.dart';
import '../services/notification_service.dart';

class DrugsScreen extends StatefulWidget {
  final ApiClient client;
  const DrugsScreen({super.key, required this.client});

  @override
  State<DrugsScreen> createState() => _DrugsScreenState();
}

class _DrugsScreenState extends State<DrugsScreen> {
  late final DrugsApi api;
  bool loading = true;
  List<dynamic> items = [];

  @override
  void initState() {
    super.initState();
    api = DrugsApi(widget.client);
    _load();
  }

  Future<void> _testNotification() async {
    try {
      await NotificationService.showNow(
        title: 'İlaç hatırlatıcı',
        body: 'Bildirim çalışıyor — ilaç saatlerinde de böyle gelecek.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirim gönderildi. Çekmeceye bak.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bildirim hatası: $e')),
      );
    }
  }

  Future<void> _testScheduledNotification() async {
    try {
      await NotificationService.scheduleTestInOneMinute();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('1 dakika sonra bildirim planlandı.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Planlama hatası: $e')),
      );
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      items = await api.listMyDrugs();
      await NotificationService.rescheduleAllFromServerList(items);
    } on DioException catch (e) {
      // 401: token yok/bozuk
      if (e.response?.statusCode == 401) {
        if (!mounted) return;
        setState(() {
          items = [];
          loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oturum süresi doldu. Lütfen tekrar giriş yap.')),
        );
        return;
      }
      rethrow;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _deleteDrug(Map<String, dynamic> d) async {
    final name = (d['drug_name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('İlacı sil?'),
        content: Text('“$name” silinecek. Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final id = d['user_drug_id'].toString();
      // Silinen ilaç için tüm bildirimleri iptal et
      await NotificationService.cancelAllForDrug(d);
      await api.deleteDrug(id);

      // silinen ilaç listeden çıkarılmış gibi yeniden planla (anlık)
      final remaining = items
          .where((x) => (x as Map<String, dynamic>)['user_drug_id'].toString() != id)
          .toList();
      await NotificationService.rescheduleAllFromServerList(remaining);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İlaç silindi.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Silme hatası: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İlaçlar'),
        actions: [
          IconButton(
            tooltip: 'Şimdi bildirim',
            icon: const Icon(Icons.notifications_active_rounded),
            onPressed: _testNotification,
          ),
          IconButton(
            tooltip: '1 dk sonra planlı bildirim testi',
            icon: const Icon(Icons.schedule_rounded),
            onPressed: _testScheduledNotification,
          ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('İlaç ekle'),
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => DrugFormScreen(client: widget.client)),
          );
          if (ok == true) _load();
        },
      ),
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
          top: false,
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 80),
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                'assets/images/empty_medication.png',
                                height: 200,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.medication_liquid_rounded,
                                  size: 80,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Henüz ilaç eklenmedi',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '“İlaç ekle” butonuna dokunarak\nilk hatırlatıcını oluşturabilirsin.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final d = items[i] as Map<String, dynamic>;
                            final name = (d['drug_name'] ?? '').toString();
                            final lowStock = (d['low_stock'] ?? false) == true;
                            final scheduleCount =
                                (d['schedule_count_active'] ?? 0).toString();

                            return InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () async {
                                final changed =
                                    await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DrugDetailScreen(
                                      client: widget.client,
                                      drug: d,
                                    ),
                                  ),
                                );
                                if (changed == true) _load();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: lowStock
                                            ? AppColors.warningLight
                                            : AppColors.primaryLight,
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: lowStock
                                          ? Icon(
                                              Icons.warning_amber_rounded,
                                              color: AppColors.warning,
                                            )
                                          : Image.asset(
                                              'assets/images/icon_medication.png',
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(
                                                Icons.medication_outlined,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.schedule_rounded,
                                                size: 16,
                                                color: Colors.black54,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Aktif saat: $scheduleCount',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Colors.black54,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (lowStock)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          color: AppColors.warningLight,
                                        ),
                                        child: const Text(
                                          'Stok az',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: 'Sil',
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                      onPressed: () => _deleteDrug(d),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ),
    );
  }
}