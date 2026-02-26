import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/token_store.dart';
import '../drugs/screens/drugs_screen.dart';
import '../auth/auth_api.dart';
import '../profile/profile_screen.dart';

// ✅ ekle
import '../kitchen/kitchen_api.dart';
import '../kitchen/kitchen_home_screen.dart';

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

  @override
  void initState() {
    super.initState();
    kitchenApi = KitchenApi(widget.client.dio);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const _Placeholder(title: 'Home'),
      DrugsScreen(client: widget.client),
      KitchenHomeScreen(api: kitchenApi),
      const _Placeholder(title: 'Recipes'),
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