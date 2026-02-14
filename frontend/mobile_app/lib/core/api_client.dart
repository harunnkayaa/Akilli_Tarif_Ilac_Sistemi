import 'package:dio/dio.dart';
import 'token_store.dart';

class ApiClient {
  final Dio dio;

  ApiClient._(this.dio);

  factory ApiClient(TokenStore tokenStore) {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://10.0.2.2:8000',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStore.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (e, handler) async {
          if (e.response?.statusCode == 401) {
            // Token invalid/expired -> cleanup
            await tokenStore.deleteToken();
            // TODO: navigate to login (we'll do later)
          }
          return handler.next(e);
        },
      ),
    );

    return ApiClient._(dio);
  }
}
