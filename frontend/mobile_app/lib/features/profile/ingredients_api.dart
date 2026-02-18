import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class IngredientsApi {
  final Dio _dio;
  IngredientsApi(ApiClient client) : _dio = client.dio;

  Future<List<Map<String, dynamic>>> search(String q) async {
    final res = await _dio.get('/ingredients/search', queryParameters: {'q': q});
    final list = (res.data as List).cast<dynamic>();
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
