import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'app_navigator.dart';
import 'token_store.dart';

class ApiClient {
  /// Sunucu adresi derleme anında verilir, koda gömülü değil:
  ///   flutter build apk --release --dart-define=API_BASE_URL=https://sunucu-adresi
  ///
  /// Verilmezse Android emülatörünün "host makine" adresi kullanılır
  /// (emülatör içinden bilgisayarın localhost'u = 10.0.2.2).
  /// Gerçek cihazdan yerel ağa bağlanmak için:
  ///   `--dart-define=API_BASE_URL=http://BILGISAYARIN_YEREL_IP:8000`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  final Dio dio;
  final TokenStore _tokenStore;
  bool _sessionRedirecting = false;

  ApiClient(TokenStore tokenStore)
      : _tokenStore = tokenStore,
        dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      // Genel API zaman aşımı (chat dışındaki istekler için makul)
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        /*onRequest: (options, handler) async {
          final raw = await _tokenStore.readToken();
          final token = raw?.trim(); // ✅ KRİTİK: boşluk/newline öldürür

          final hasToken = token != null && token.isNotEmpty;

          if (hasToken) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }

          // ✅ KANIT: Authorization gerçekten set mi?
          final auth = options.headers['Authorization']?.toString();
          // ignore: avoid_print
          print('[API] ${options.method} ${options.uri}');
          // ignore: avoid_print
          print('[API] hasToken=$hasToken rawLen=${raw?.length ?? 0} trimLen=${token?.length ?? 0}');
          // ignore: avoid_print
          print('[API] Authorization=${auth == null ? "NULL" : auth.substring(0, auth.length > 20 ? 20 : auth.length)}...');

          handler.next(options);
        },*/
        onRequest: (options, handler) async {
        final path = options.path;

        final isAuthCall =
            path.contains('/auth/login') || path.contains('/auth/register');

        // Login/register isteklerinde token okumaya gerek yok.
        // Token okuma burada takılırsa istek backend'e hiç gitmez.
        if (isAuthCall) {
          options.headers.remove('Authorization');

          // ignore: avoid_print
          print('[API] ${options.method} ${options.uri} authCall=true');

          handler.next(options);
          return;
        }

        String? raw;

        try {
          raw = await _tokenStore
              .readToken()
              .timeout(const Duration(seconds: 2), onTimeout: () => null);
        } catch (_) {
          raw = null;
        }

        final token = raw?.trim();
        final hasToken = token != null && token.isNotEmpty;

        if (hasToken) {
          options.headers['Authorization'] = 'Bearer $token';
        } else {
          options.headers.remove('Authorization');
        }

        final auth = options.headers['Authorization']?.toString();

        // ignore: avoid_print
        print('[API] ${options.method} ${options.uri}');
        // ignore: avoid_print
        print('[API] hasToken=$hasToken rawLen=${raw?.length ?? 0} trimLen=${token?.length ?? 0}');
        // ignore: avoid_print
        print('[API] Authorization=${auth == null ? "NULL" : auth.substring(0, auth.length > 20 ? 20 : auth.length)}...');

        handler.next(options);
      },
        onError: (e, handler) async {
          // ignore: avoid_print
          print('[API][ERR] status=${e.response?.statusCode} uri=${e.requestOptions.uri}');

          final status = e.response?.statusCode;
          final path = e.requestOptions.path;
          final isAuthCall =
              path.contains('/auth/login') || path.contains('/auth/register');

          if (status == 401 && !isAuthCall) {
            await _handleSessionExpired();
          }

          handler.next(e);
        },
      ),
    );

    dio.interceptors.add(
      LogInterceptor(
        requestHeader: true, // ✅ header gör
        requestBody: true,   // ✅ PUT payload gör
        responseHeader: false,
        responseBody: true,
        error: true,
      ),
    );
  }

  Future<void> _handleSessionExpired() async {
    if (_sessionRedirecting) return;
    _sessionRedirecting = true;

    await _tokenStore.deleteToken();

    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      _sessionRedirecting = false;
      return;
    }

    nav.pushNamedAndRemoveUntil(
      '/login',
      (_) => false,
    );

    final messenger = ScaffoldMessenger.maybeOf(nav.context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Oturum süresi doldu. Lütfen tekrar giriş yapın.'),
        duration: Duration(seconds: 4),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      _sessionRedirecting = false;
    });
  }
}