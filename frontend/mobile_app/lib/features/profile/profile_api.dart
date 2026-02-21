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

// Allergies

    // Allergies
    Future<List<dynamic>> listAllergies() async {
      final res = await _dio.get('/profile/allergies');
      return (res.data as List).toList();
    }

  Future<void> addAllergyRawText({
    required String rawText,
    String? reaction,
    String? notes,
  }) async {
    await _dio.post('/profile/allergies', data: {
      'raw_text': rawText,
      'reaction': reaction,
      'notes': notes,
    });
  }

    Future<void> deleteAllergy(int allergyId) async {
      await _dio.delete('/profile/allergies/$allergyId');
    }
  // ---------------- Disliked Ingredients ----------------

  Future<List<dynamic>> listDisliked() async {
    final res = await _dio.get('/profile/disliked-ingredients');
    return (res.data as List).toList();
  }

  Future<void> addDislikedRawText({
    required String rawText,
    String? reason,
  }) async {
    await _dio.post('/profile/disliked-ingredients', data: {
      'raw_text': rawText,
      'reason': reason,
    });
  }

  Future<void> deleteDisliked(int dislikedId) async {
    await _dio.delete('/profile/disliked-ingredients/$dislikedId');
  }
}
