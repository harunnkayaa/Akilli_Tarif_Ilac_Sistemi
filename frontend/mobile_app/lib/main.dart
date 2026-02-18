import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/token_store.dart';

import 'features/auth/auth_api.dart';
import 'features/auth/boot_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/main/main_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tokenStore = TokenStore();
    final client = ApiClient(tokenStore);
    final authApi = AuthApi(client, tokenStore);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartApp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      routes: {
        '/': (_) => BootScreen(authApi: authApi),
        '/login': (_) => LoginScreen(authApi: authApi),
        '/register': (_) => RegisterScreen(authApi: authApi),
        '/main': (_) => MainScreen(
          authApi: authApi,
          client: client,
          tokenStore: tokenStore,
        ),
      },
    );
  }
}
