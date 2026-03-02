import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'recipe_chat_screen.dart';

/// Tarif sekmesine girince ilk görülen ekran:
/// Kullanıcı önce modu seçer (stok olmadan / stoka göre),
/// sonra sohbet ekranına geçer.
class RecipeModeScreen extends StatefulWidget {
  final ApiClient client;

  const RecipeModeScreen({super.key, required this.client});

  @override
  State<RecipeModeScreen> createState() => _RecipeModeScreenState();
}

class _RecipeModeScreenState extends State<RecipeModeScreen> {
  /// 1 = stok durumu olmadan, 2 = stok durumuna göre öneri
  int _mode = 1;

  void _goToChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeChatScreen(
          client: widget.client,
          initialMode: _mode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarif Önerisi'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 180,
                child: Image.asset(
                  'assets/images/recipe_mode_hero.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Öneri modu seçin',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('Stok olmadan'),
                            selected: _mode == 1,
                            onSelected: (selected) {
                              if (selected) setState(() => _mode = 1);
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Stoka göre'),
                            selected: _mode == 2,
                            onSelected: (selected) {
                              if (selected) setState(() => _mode = 2);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _mode == 1
                            ? 'İsteğinize uygun tarifler profil bilgilerinizle birlikte önerilir.'
                            : 'Kileriniz ve profil bilgileriniz dikkate alınarak tarifler önceliklenir.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Bu uygulama tıbbi tedavi veya tanı yerine geçmez; tarifler yalnızca genel beslenme amaçlıdır.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _goToChat,
                  child: const Text('Sohbete başla'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

