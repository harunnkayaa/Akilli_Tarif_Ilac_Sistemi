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

  Future<List<String>> searchRecipeIngredients(String query) async {
    final res = await _dio.get('/recipes/ingredients', queryParameters: {
      'query': query,
      'limit': 30,
    });
    return (res.data as List).map((e) => e.toString()).toList();
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
}