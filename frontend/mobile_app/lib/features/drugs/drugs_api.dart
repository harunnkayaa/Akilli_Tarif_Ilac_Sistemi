import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class DrugsApi {
  final Dio _dio;

  DrugsApi(ApiClient client) : _dio = client.dio;

  Future<List<dynamic>> listMyDrugs() async {
    final res = await _dio.get('/drugs');
    return (res.data as List).cast<dynamic>();
  }

  Future<Map<String, dynamic>> getDrug(String userDrugId) async {
    final res = await _dio.get('/drugs/$userDrugId');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<String>> suggest(String q) async {
    final res = await _dio.get('/drugs/suggest', queryParameters: {'q': q});
    return (res.data as List).map((e) => e.toString()).toList();
  }

  Future<dynamic> createDrug(Map<String, dynamic> payload) async {
    final res = await _dio.post('/drugs', data: payload);
    return res.data;
  }

  Future<dynamic> updateDrug(String userDrugId, Map<String, dynamic> payload) async {
    final res = await _dio.put('/drugs/$userDrugId', data: payload);
    return res.data;
  }

  Future<void> deleteDrug(String userDrugId) async {
    await _dio.delete('/drugs/$userDrugId');
  }

  Future<List<dynamic>> interactions(String userDrugId) async {
    final res = await _dio.get('/drugs/$userDrugId/interactions');
    return (res.data as List).cast<dynamic>();
  }

  Future<Map<String, dynamic>> intake({
    required String userDrugId,
    required String clientEventId,
    required String action, // "TAKEN" | "SNOOZE" | "SKIP"
    String? scheduledAtIso,
    int snoozeMinutes = 5,
  }) async {
    final res = await _dio.post(
      '/intake',
      data: {
        'user_drug_id': userDrugId,
        'client_event_id': clientEventId,
        'action': action,
        'scheduled_at': scheduledAtIso,
        'snooze_minutes': snoozeMinutes,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }
}