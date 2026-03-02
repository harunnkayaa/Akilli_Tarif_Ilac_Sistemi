import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/token_store.dart';
import '../auth/auth_api.dart';
import '../drugs/drugs_api.dart';
import '../drugs/screens/drug_detail_screen.dart';
import '../drugs/screens/drugs_screen.dart';
import '../drugs/services/notification_service.dart';
import '../kitchen/kitchen_api.dart';
import '../kitchen/kitchen_home_screen.dart';
import '../profile/profile_screen.dart';
import '../recipes/recipe_mode_screen.dart';

class MainScreen extends StatefulWidget {
  final AuthApi authApi;
  final ApiClient client;
  final TokenStore tokenStore;

  const MainScreen({
    super.key,
    required this.authApi,
    required this.client,
    required this.tokenStore,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  late final KitchenApi kitchenApi;
  late final DrugsApi drugsApi;

  @override
  void initState() {
    super.initState();
    kitchenApi = KitchenApi(widget.client.dio);
    drugsApi = DrugsApi(widget.client);

    NotificationService.tappedPayload.addListener(_handleNotificationTap);
    // Uygulama zaten açıkken tıklanmış bir payload varsa hemen işle
    _handleNotificationTap();
  }

  @override
  void dispose() {
    NotificationService.tappedPayload.removeListener(_handleNotificationTap);
    super.dispose();
  }

  Future<void> _handleNotificationTap() async {
    final payload = NotificationService.tappedPayload.value;
    if (payload == null) return;

    // Aynı payload'ın tekrar işlenmesini engelle
    NotificationService.tappedPayload.value = null;

    final userDrugId = payload['user_drug_id'];
    if (userDrugId == null || userDrugId.isEmpty) return;

    try {
      final drug = await drugsApi.getDrug(userDrugId);
      if (!mounted) return;

      setState(() => _index = 1); // İlaç sekmesine geç

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DrugDetailScreen(
            client: widget.client,
            drug: drug,
          ),
        ),
      );
    } catch (_) {
      // Sessizce geç; istenirse burada snackbar gösterilebilir.
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const _Placeholder(title: 'Home'),
      DrugsScreen(client: widget.client),
      KitchenHomeScreen(api: kitchenApi),
      RecipeModeScreen(client: widget.client),
      ProfileScreen(
        client: widget.client,
        authApi: widget.authApi,
      ),
    ];

    return Scaffold(
      body: SafeArea(child: screens[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.vaccines_rounded), label: 'İlaç'),
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Market'),
          NavigationDestination(icon: Icon(Icons.restaurant), label: 'Tarif'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String title;
  const _Placeholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}