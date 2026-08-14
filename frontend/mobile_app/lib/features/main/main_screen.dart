import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/token_store.dart';
import '../auth/auth_api.dart';
import '../drugs/drugs_api.dart';
import '../drugs/screens/drug_detail_screen.dart';
import '../drugs/screens/drugs_screen.dart';
import '../drugs/services/notification_service.dart';
import '../home/home_screen.dart';
import '../kitchen/kitchen_api.dart';
import '../kitchen/kitchen_home_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/recipes_api.dart';
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

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _index = 0;
  int _homeRefreshKey = 0;

  late final KitchenApi kitchenApi;
  late final DrugsApi drugsApi;
  late final RecipesApi recipesApi;
  late final Widget _drugsScreen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.configure(widget.client);
    kitchenApi = KitchenApi(widget.client.dio);
    drugsApi = DrugsApi(widget.client);
    recipesApi = RecipesApi(widget.client);
    // Sekme her değişiminde yeniden oluşturulmasın → tekrar tekrar reschedule olmasın
    _drugsScreen = DrugsScreen(client: widget.client);

    NotificationService.tappedPayload.addListener(_handleNotificationTap);
    // Uygulama zaten açıkken tıklanmış bir payload varsa hemen işle
    _handleNotificationTap();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileMissedDoses());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.tappedPayload.removeListener(_handleNotificationTap);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileMissedDoses();
    }
  }

  Future<void> _reconcileMissedDoses() async {
    try {
      final items = await drugsApi.listMyDrugs();
      await NotificationService.pruneOrphanedForDrugList(items);
      await NotificationService.reconcileMissedDoses(items);
    } catch (_) {}
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
      HomeScreen(
        key: ValueKey(_homeRefreshKey),
        kitchenApi: kitchenApi,
        drugsApi: drugsApi,
        recipesApi: recipesApi,
        onNavigateToTab: (i) => setState(() => _index = i),
      ),
      _drugsScreen,
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
        onDestinationSelected: (i) {
          setState(() {
            _index = i;
            if (i == 0) _homeRefreshKey++;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Ana Sayfa'),
          NavigationDestination(icon: Icon(Icons.vaccines_rounded), label: 'İlaç'),
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Market'),
          NavigationDestination(icon: Icon(Icons.restaurant), label: 'Tarif'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}