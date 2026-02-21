import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class RecipesApi {
  final Dio _dio;
  RecipesApi(ApiClient client) : _dio = client.dio;

  Future<List<String>> searchRecipeIngredients(String query) async {
    final res = await _dio.get('/recipes/ingredients', queryParameters: {
      'query': query,
      'limit': 30,
    });
    return (res.data as List).map((e) => e.toString()).toList();
  }
}