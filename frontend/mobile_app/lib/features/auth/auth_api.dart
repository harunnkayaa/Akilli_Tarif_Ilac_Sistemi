import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/token_store.dart';

class AuthApi {
  final Dio _dio;
  final TokenStore _tokenStore;

  AuthApi(ApiClient client, this._tokenStore) : _dio = client.dio;

  Future<void> register({
    required String email,
    required String password,
  }) async {
    await _dio.post(
      '/auth/register',
      data: {'email': email, 'password': password},
    );
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );

    final data = res.data;
    final token = (data is Map && data['access_token'] is String)
        ? data['access_token'] as String
        : null;

    if (token == null || token.isEmpty) {
      throw Exception('Login response does not include access_token');
    }

    await _tokenStore.saveToken(token);
  }

  Future<void> logout() async {
    await _tokenStore.deleteToken();
  }

  Future<bool> hasValidSession() async {
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) return false;

    try {
      await _dio.get('/users/me');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await _tokenStore.deleteToken();
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
