import 'package:dio/dio.dart';
import 'token_store.dart';

class ApiClient {
  final Dio dio;

  ApiClient(TokenStore tokenStore)
      : dio = Dio(
    BaseOptions(
      baseUrl: 'http://10.0.2.2:8000',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'Content-Type': 'application/json'},
    ),
  ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final raw = await tokenStore.readToken();
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
        },
        onError: (e, handler) {
          // ignore: avoid_print
          print('[API][ERR] status=${e.response?.statusCode} uri=${e.requestOptions.uri}');
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
}