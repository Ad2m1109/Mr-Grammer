import 'dart:convert';

class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final List<Map<String, dynamic>> messages;
  final String language;

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.lastMessageAt,
    required this.messages,
    required this.language,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastMessageAt': lastMessageAt.millisecondsSinceEpoch,
      'messages': messages,
      'language': language,
    };
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      title: json['title'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(json['lastMessageAt']),
      messages: List<Map<String, dynamic>>.from(json['messages']),
      language: json['language'] ?? 'en-US',
    );
  }

  Conversation copyWith({
    String? title,
    DateTime? lastMessageAt,
    List<Map<String, dynamic>>? messages,
    String? language,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      messages: messages ?? this.messages,
      language: language ?? this.language,
    );
  }
}

class ConversationService {
  // In-memory storage - data persists during app session only
  static final Map<String, Conversation> _conversations = {};
  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;

    // You can add some default conversations here if needed
    _initialized = true;
  }

  static Future<List<Conversation>> getAllConversations() async {
    await _init();

    final conversations = _conversations.values.toList();
    conversations.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return conversations;
  }

  static Future<Conversation?> getConversation(String id) async {
    await _init();
    return _conversations[id];
  }

  static Future<void> saveConversation(Conversation conversation) async {
    await _init();
    _conversations[conversation.id] = conversation;
  }

  static Future<void> deleteConversation(String id) async {
    await _init();
    _conversations.remove(id);
  }

  static Future<Conversation> createNewConversation({
    required String language,
    String? customTitle,
  }) async {
    await _init();

    final String id = DateTime.now().millisecondsSinceEpoch.toString();
    final String title = customTitle ?? _generateTitle(language);

    final conversation = Conversation(
      id: id,
      title: title,
      createdAt: DateTime.now(),
      lastMessageAt: DateTime.now(),
      messages: [],
      language: language,
    );

    await saveConversation(conversation);
    return conversation;
  }

  static String _generateTitle(String language) {
    final Map<String, String> titles = {
      'en-US': 'New Conversation',
      'fr-FR': 'Nouvelle Conversation',
      'ar': 'محادثة جديدة',
      'de-DE': 'Neues Gespräch',
      'es-ES': 'Nueva Conversación',
    };

    return titles[language] ?? 'New Conversation';
  }

  static Future<void> addMessageToConversation(
      String conversationId,
      Map<String, dynamic> message,
      ) async {
    final conversation = await getConversation(conversationId);
    if (conversation == null) return;

    final updatedMessages = [...conversation.messages, message];
    final updatedConversation = conversation.copyWith(
      messages: updatedMessages,
      lastMessageAt: DateTime.now(),
    );

    await saveConversation(updatedConversation);
  }

  static Future<void> updateConversationTitle(String id, String newTitle) async {
    final conversation = await getConversation(id);
    if (conversation == null) return;

    final updatedConversation = conversation.copyWith(title: newTitle);
    await saveConversation(updatedConversation);
  }

  // Additional helper methods for debugging
  static Future<void> clearAllConversations() async {
    await _init();
    _conversations.clear();
  }

  static Future<int> getConversationCount() async {
    await _init();
    return _conversations.length;
  }

  // Export/Import functionality (for future use if you want to save/load data)
  static Future<String> exportConversationsAsJson() async {
    final conversations = await getAllConversations();
    return jsonEncode(conversations.map((c) => c.toJson()).toList());
  }

  static Future<void> importConversationsFromJson(String jsonString) async {
    await _init();

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final conversations = jsonList.map((json) => Conversation.fromJson(json)).toList();

      for (final conversation in conversations) {
        _conversations[conversation.id] = conversation;
      }
    } catch (e) {
      print('Error importing conversations: $e');
    }
  }
}