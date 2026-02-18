import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class ProfileApi {
  final Dio _dio;
  ProfileApi(ApiClient client) : _dio = client.dio;

  Future<Map<String, dynamic>> me() async {
    final res = await _dio.get('/users/me');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getProfile() async {
    final res = await _dio.get('/profile');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> payload) async {
    final res = await _dio.put('/profile', data: payload);
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ---------------- Diseases ----------------

  Future<List<dynamic>> listDiseases() async {
    final res = await _dio.get('/profile/diseases');
    return (res.data as List).toList();
  }

  /// Autocomplete kaynağı: dataset'te tanımlı hastalıklar
  Future<List<String>> searchKnownDiseases(String query) async {
    final res = await _dio.get(
      '/health/diseases',
      queryParameters: {'query': query},
    );
    return (res.data as List).map((e) => e.toString()).toList();
  }

  Future<void> addDisease({
    required String diseaseName,
    String? diagnosedAt, // yyyy-mm-dd
    String? notes,
  }) async {
    await _dio.post('/profile/diseases', data: {
      'disease_name': diseaseName,
      'diagnosed_at': diagnosedAt,
      'notes': notes,
    });
  }

  Future<void> deleteDisease(String diseaseName) async {
    final safe = Uri.encodeComponent(diseaseName);
    await _dio.delete('/profile/diseases/$safe');
  }

  // ---------------- Allergies ----------------

  Future<List<dynamic>> listAllergies() async {
    final res = await _dio.get('/profile/allergies');
    return (res.data as List).toList();
  }

  Future<void> addAllergy({
    required String ingredientId,
    String? reaction,
    String? notes,
  }) async {
    await _dio.post('/profile/allergies', data: {
      'ingredient_id': ingredientId,
      'reaction': reaction,
      'notes': notes,
    });
  }

  Future<void> deleteAllergy(String ingredientId) async {
    final safe = Uri.encodeComponent(ingredientId);
    await _dio.delete('/profile/allergies/$safe');
  }

  // ---------------- Disliked Ingredients ----------------

  Future<List<dynamic>> listDisliked() async {
    final res = await _dio.get('/profile/disliked-ingredients');
    return (res.data as List).toList();
  }

  Future<void> addDisliked({
    required String ingredientId,
    String? reason,
  }) async {
    await _dio.post('/profile/disliked-ingredients', data: {
      'ingredient_id': ingredientId,
      'reason': reason,
    });
  }

  Future<void> deleteDisliked(String ingredientId) async {
    final safe = Uri.encodeComponent(ingredientId);
    await _dio.delete('/profile/disliked-ingredients/$safe');
  }
}
