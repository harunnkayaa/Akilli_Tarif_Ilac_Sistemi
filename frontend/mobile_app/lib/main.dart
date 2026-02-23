import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api_client.dart';
import 'core/token_store.dart';

import 'features/auth/auth_api.dart';
import 'features/auth/boot_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/main/main_screen.dart';
import 'features/drugs/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tokenStore = TokenStore();
    final client = ApiClient(tokenStore);
    final authApi = AuthApi(client, tokenStore);

    final seed = const Color(0xFF2E7D32); // daha oturaklı yeşil

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Akıllı Tarif & İlaç',

      // ✅ TR locale + time picker/metinlerin Türkçeleşmesi
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),

        scaffoldBackgroundColor: const Color(0xFFF6F7F3),

        appBarTheme: const AppBarTheme(
          centerTitle: true,
          surfaceTintColor: Colors.transparent,
        ),

        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE3E6E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: seed, width: 1.4),
          ),
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
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