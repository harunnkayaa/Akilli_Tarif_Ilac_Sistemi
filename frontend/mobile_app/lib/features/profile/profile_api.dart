import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class ProfileApi {
  final Dio _dio;
  ProfileApi(ApiClient client) : _dio = client.dio;

  Future<Map<String, dynamic>> me() async {
    final res = await _dio.get('/users/me');
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('Unexpected /users/me response');
  }
}
