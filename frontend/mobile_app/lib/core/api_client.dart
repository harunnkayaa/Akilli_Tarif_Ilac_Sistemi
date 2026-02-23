import 'package:dio/dio.dart';
import 'token_store.dart';

class ApiClient {
  final Dio dio;

  ApiClient(TokenStore tokenStore)
      : dio = Dio(
    BaseOptions(
      baseUrl: 'http://10.0.2.2:8000',
      //baseUrl: 'http://192.168.1.171:8000',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'Content-Type': 'application/json'},
    ),
  ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStore.readToken();

          // Kanıt: token var mı?
          final hasToken = token != null && token.isNotEmpty;
          // ignore: avoid_print
          print('[API] ${options.method} ${options.uri} token=${hasToken ? "yes" : "no"} len=${token?.length ?? 0}');

          if (hasToken) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          // Debug sırasında token silmek YASAK. Sadece logla.
          // ignore: avoid_print
          print('[API][ERR] status=${e.response?.statusCode} path=${e.requestOptions.uri}');
          handler.next(e);
        },
      ),
    );

    // İstersen response body/snippet görmek için:
    dio.interceptors.add(
      LogInterceptor(
        requestHeader: true,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
        error: true,
      ),
    );
  }
}
