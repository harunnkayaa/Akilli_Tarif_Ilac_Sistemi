// lib/features/kitchen/kitchen_api.dart
import 'package:dio/dio.dart';

class KitchenApi {
  final Dio _dio;
  KitchenApi(this._dio);

  Future<List<dynamic>> getPantry() async {
    final r = await _dio.get('/kitchen/pantry');
    return (r.data as List);
  }

  Future<List<dynamic>> getPantryAlerts() async {
    final r = await _dio.get('/kitchen/pantry/alerts');
    return (r.data as List);
  }

  /// mode:
  /// - "add": aynı ürün varsa quantity üzerine ekler
  /// - "set": quantity’i direkt set eder
  Future<void> upsertPantry({
    required String ingredientId,
    required double quantity,
    required String unit, // g | ml
    String? expiresAt, // yyyy-MM-dd
    double? lowThreshold,
    String mode = 'add', // add | set
  }) async {
    await _dio.post('/kitchen/pantry', data: {
      'ingredient_id': ingredientId,
      'quantity': quantity,
      'unit': unit,
      'expires_at': expiresAt,
      'low_threshold': lowThreshold,
      'mode': mode,
    });
  }

  /// Malzeme önerisi: sadece recipes.malzemeler_json içindeki Malzeme_Adi (tariflerdeki malzemeler).
  Future<List<String>> searchRecipeIngredients(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    final r = await _dio.get(
      '/recipes/ingredients',
      queryParameters: {'query': q, 'limit': 30},
    );
    final data = r.data;
    if (data is List) return data.map((e) => e.toString()).toList();
    return [];
  }

  Future<void> deletePantry(String ingredientId) async {
    final safe = Uri.encodeComponent(ingredientId);
    await _dio.delete('/kitchen/pantry/$safe');
  }

  Future<List<dynamic>> getShoppingList() async {
    final r = await _dio.get('/kitchen/shopping-list');
    return (r.data as List);
  }

  Future<void> refreshShoppingFromPantry() async {
    await _dio.post('/kitchen/shopping-list/refresh');
  }

  Future<void> addManualShoppingItem({
    required String itemText,
    double? targetQty,
    String? unit,
  }) async {
    await _dio.post('/kitchen/shopping-list/manual', data: {
      'item_text': itemText,
      'target_qty': targetQty,
      'unit': unit,
    });
  }

  Future<void> setShoppingChecked(String itemId, bool isChecked) async {
    await _dio.put('/kitchen/shopping-list/$itemId', data: {'is_checked': isChecked});
  }

  Future<void> deleteShoppingItem(String itemId) async {
    await _dio.delete('/kitchen/shopping-list/$itemId');
  }
}