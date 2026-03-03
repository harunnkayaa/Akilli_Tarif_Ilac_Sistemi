import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../profile/recipes_api.dart';
import 'recipe_detail_screen.dart';

class _ChatMessage {
  final bool isUser;
  final String text;
  final List<RecipeChatCard>? cards;

  _ChatMessage({required this.isUser, required this.text, this.cards});
}

class RecipeChatScreen extends StatefulWidget {
  final ApiClient client;
  /// 1 = stok durumu olmadan, 2 = stok durumuna göre öneri
  final int initialMode;

  const RecipeChatScreen({
    super.key,
    required this.client,
    required this.initialMode,
  });

  @override
  State<RecipeChatScreen> createState() => _RecipeChatScreenState();
}

class _RecipeChatScreenState extends State<RecipeChatScreen> {
  late final RecipesApi api;

  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  String? _sessionId;
  bool _loading = false;
  /// 1 = stok durumu olmadan, 2 = stok durumuna göre öneri
  late int _mode;

  @override
  void initState() {
    super.initState();
    api = RecipesApi(widget.client);
    _mode = widget.initialMode;
  }

  void _openRecipeDetail(RecipeChatCard card) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          api: api,
          recipeId: card.recipeId,
          initialTitle: card.title,
          initialMode: _mode,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;

    _inputCtrl.clear();
    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: text));
      _loading = true;
    });
    _scrollToEnd();

    try {
      final res = await api.suggestRecipes(
        sessionId: _sessionId,
        message: text,
        mode: _mode,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = res.sessionId;
        _messages.add(_ChatMessage(
          isUser: false,
          text: res.assistantText,
          cards: res.cards.isNotEmpty ? res.cards : null,
        ));
        _loading = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          isUser: false,
          text: 'Bir hata oluştu. Lütfen tekrar deneyin.',
        ));
        _loading = false;
      });
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarif Önerisi'),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/recipe_chat_bg.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Color(0x11FFFFFF),
              BlendMode.srcATop,
            ),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final m = _messages[i];
                  return _MessageBubble(
                    isUser: m.isUser,
                    text: m.text,
                    cards: m.cards,
                    onCardTap: _openRecipeDetail,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Bu uygulama tıbbi tedavi veya tanı yerine geçmez; tarifler yalnızca genel beslenme amaçlıdır.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Örn: Sebzeli akşam yemeği öner',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      maxLines: 1,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isUser;
  final String text;
  final List<RecipeChatCard>? cards;
  final void Function(RecipeChatCard) onCardTap;

  const _MessageBubble({
    required this.isUser,
    required this.text,
    this.cards,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          if (cards != null && cards!.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cards!.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final c = cards![i];
                  return _RecipeCardTile(
                    card: c,
                    onTap: () => onCardTap(c),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecipeCardTile extends StatelessWidget {
  final RecipeChatCard card;
  final VoidCallback onTap;

  const _RecipeCardTile({
    required this.card,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (card.imageUrl != null && card.imageUrl!.isNotEmpty)
                Image.network(
                  card.imageUrl!,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 100,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.restaurant, size: 40),
                  ),
                )
              else
                Container(
                  height: 100,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.restaurant, size: 40),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (card.availableIngredients.isNotEmpty)
                        Text(
                          'Stokta: ${card.availableIngredients.take(2).join(", ")}',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (card.missingIngredients.isNotEmpty)
                        Text(
                          'Eksik: ${card.missingIngredients.take(2).join(", ")}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
