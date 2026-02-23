import 'package:dio/dio.dart';
import '../../core/api_client.dart';


class DrugsApi {
  final Dio _dio;

  DrugsApi(ApiClient client) : _dio = client.dio;

  Future<List<dynamic>> listMyDrugs() async {
    final res = await _dio.get('/drugs');
    return (res.data as List).cast<dynamic>();
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
}