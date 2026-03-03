import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class RecipeChatCard {
  final String recipeId;
  final String title;
  final String? imageUrl;
  final String reason;
  final List<String> warnings;
  final List<String> badges;
  final List<String> missingIngredients;
  final List<String> availableIngredients;

  RecipeChatCard({
    required this.recipeId,
    required this.title,
    this.imageUrl,
    required this.reason,
    required this.warnings,
    required this.badges,
    required this.missingIngredients,
    required this.availableIngredients,
  });

  factory RecipeChatCard.fromJson(Map<String, dynamic> json) {
    return RecipeChatCard(
      recipeId: json['recipe_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      reason: json['reason'] as String? ?? '',
      warnings: (json['warnings'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      badges: (json['badges'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      missingIngredients: (json['missing_ingredients'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      availableIngredients: (json['available_ingredients'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class RecipeIngredient {
  final String name;
  final String? unit;
  final double? amount;
  final String? displayAmount;

  RecipeIngredient({
    required this.name,
    this.unit,
    this.amount,
    this.displayAmount,
  });

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      name: json['name'] as String? ?? '',
      unit: json['unit'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      displayAmount: json['display_amount'] as String?,
    );
  }
}

class RecipeDetail {
  final String recipeId;
  final String title;
  final String? category;
  final int? servings;
  final double? totalCaloriesKcal;
  final double? caloriesPerServingKcal;
  final String? sourceUrl;
  final String? imageUrl;
  final String? steps;
  final List<RecipeIngredient> ingredients;

  RecipeDetail({
    required this.recipeId,
    required this.title,
    this.category,
    this.servings,
    this.totalCaloriesKcal,
    this.caloriesPerServingKcal,
    this.sourceUrl,
    this.imageUrl,
    this.steps,
    required this.ingredients,
  });

  factory RecipeDetail.fromJson(Map<String, dynamic> json) {
    final ings = (json['ingredients'] as List<dynamic>? ?? [])
        .map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
        .toList();

    return RecipeDetail(
      recipeId: json['recipe_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String?,
      servings: (json['servings'] as num?)?.toInt(),
      totalCaloriesKcal: (json['total_calories_kcal'] as num?)?.toDouble(),
      caloriesPerServingKcal: (json['calories_per_serving_kcal'] as num?)?.toDouble(),
      sourceUrl: json['source_url'] as String?,
      imageUrl: json['image_url'] as String?,
      steps: json['steps'] as String?,
      ingredients: ings,
    );
  }
}

class CookRecipeResult {
  final bool success;
  final String? error;
  final List<String>? missing;
  final Map<String, dynamic>? dailyNutrientTotals;

  CookRecipeResult({
    required this.success,
    this.error,
    this.missing,
    this.dailyNutrientTotals,
  });

  factory CookRecipeResult.fromJson(Map<String, dynamic> json) {
    return CookRecipeResult(
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
      missing: (json['missing'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      dailyNutrientTotals:
          json['daily_nutrient_totals'] as Map<String, dynamic>?,
    );
  }
}

class RecipeChatSuggestResponse {
  final String sessionId;
  final String assistantText;
  final List<RecipeChatCard> cards;

  RecipeChatSuggestResponse({
    required this.sessionId,
    required this.assistantText,
    required this.cards,
  });

  factory RecipeChatSuggestResponse.fromJson(Map<String, dynamic> json) {
    final cardsList = json['cards'] as List<dynamic>? ?? [];
    return RecipeChatSuggestResponse(
      sessionId: json['session_id'] as String? ?? '',
      assistantText: json['assistant_text'] as String? ?? '',
      cards: cardsList.map((e) => RecipeChatCard.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class RecipesApi {
  final Dio _dio;
  RecipesApi(ApiClient client) : _dio = client.dio;

  /// Bugünkü günlük besin toplamları (Home özet ekranı için, sadece okuma).
  Future<Map<String, dynamic>> getDailyTotals() async {
    final res = await _dio.get('/recipes/daily-totals');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Son yapılan tarifler (meal_log), en fazla [limit] adet, tarif adı ile.
  Future<List<Map<String, dynamic>>> getRecentMeals({int limit = 5}) async {
    final res = await _dio.get('/recipes/recent-meals', queryParameters: {'limit': limit});
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Malzeme önerisi: sadece recipes.malzemeler_json içindeki Malzeme_Adi (tariflerdeki malzemeler).
  Future<List<String>> searchRecipeIngredients(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    final res = await _dio.get('/recipes/ingredients', queryParameters: {
      'query': q,
      'limit': 30,
    });
    final data = res.data;
    if (data is List) return (data).map((e) => e.toString()).toList();
    return [];
  }

  /// [mode] 1 = stok durumu olmadan öneri, 2 = stok durumuna göre öneri
  Future<RecipeChatSuggestResponse> suggestRecipes({
    String? sessionId,
    required String message,
    int mode = 1,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'mode': mode,
    };
    if (sessionId != null && sessionId.isNotEmpty) {
      body['session_id'] = sessionId;
    }
    // Tarif sohbeti RAG + LLM (intent, rerank, polish) nedeniyle uzun sürebilir.
    // Bu endpoint için isteğe özel daha uzun timeout kullan.
    const chatTimeout = Duration(seconds: 60);
    final res = await _dio.post(
      '/recipes/chat/suggest',
      data: body,
      options: Options(
        connectTimeout: chatTimeout,
        receiveTimeout: chatTimeout,
      ),
    );
    return RecipeChatSuggestResponse.fromJson(res.data as Map<String, dynamic>);
  }

  Future<RecipeDetail> getRecipeDetail(String recipeId) async {
    final res = await _dio.get('/recipes/$recipeId');
    return RecipeDetail.fromJson(res.data as Map<String, dynamic>);
  }

  /// [allowPartialStock] true = stok olmadan mod: sadece stokta olan düşülür, meal_log ve besin toplamları tüm tarif için yazılır.
  /// [addPantry] eksik malzemeleri stoka ekleyip pişirmek için: her biri ingredient_id (malzeme adı) + quantity (gram).
  Future<CookRecipeResult> cookRecipe({
    required String recipeId,
    double servingsConsumed = 1.0,
    String? notes,
    bool allowPartialStock = false,
    List<Map<String, dynamic>>? addPantry,
  }) async {
    final qp = <String, dynamic>{
      'servings_consumed': servingsConsumed,
      'allow_partial_stock': allowPartialStock,
    };
    if (notes != null && notes.isNotEmpty) {
      qp['notes'] = notes;
    }
    final body = addPantry != null && addPantry.isNotEmpty
        ? <String, dynamic>{
            'add_pantry': addPantry
                .map((e) {
                  final m = <String, dynamic>{
                    'ingredient_id': e['ingredient_id'],
                    'quantity': (e['quantity'] as num).toDouble(),
                  };
                  if (e['low_threshold'] != null) {
                    m['low_threshold'] = (e['low_threshold'] as num).toDouble();
                  }
                  return m;
                })
                .toList(),
          }
        : null;
    final res = await _dio.post(
      '/recipes/$recipeId/cook',
      queryParameters: qp,
      data: body,
    );
    return CookRecipeResult.fromJson(
      res.data as Map<String, dynamic>,
    );
  }
}