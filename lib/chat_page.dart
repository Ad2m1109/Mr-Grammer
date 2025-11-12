import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_tts/flutter_tts.dart';
import 'conversation_service.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;

  const ChatPage({super.key, required this.conversationId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();

  // Note: In production, store API keys securely
  final String _geminiApiKey = 'AIzaSyDE273zP168oTYwfdj4Zhvp7BAlzeWlvtQ';

  bool _isLoading = false;
  String _selectedLanguage = 'en-US';
  String _selectedLanguageName = 'English';

  final Map<String, Map<String, String>> _languages = {
    'en-US': {'name': 'English', 'flag': '🇺🇸', 'code': 'en'},
  };



  late AnimationController _fadeController;
  late AnimationController _rotateController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotateAnimation;

  // Text-to-Speech functionality
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  String _currentSpeakingMessage = '';
  int _currentSpeakingIndex = -1;

  // Conversation management
  Conversation? _currentConversation;

  @override
  void initState() {
    super.initState();
    // Load conversation and initialize
    _loadConversation();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _rotateController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _rotateAnimation = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(_rotateController);

    _fadeController.forward();
    _rotateController.repeat();

    // Initialize Text-to-Speech
    _initializeTts();
  }

  Future<void> _loadConversation() async {
    final conversation = await ConversationService.getConversation(widget.conversationId);
    if (conversation != null && mounted) {
      setState(() {
        _currentConversation = conversation;
        _messages.clear();
        _messages.addAll(conversation.messages);
        _selectedLanguage = 'en-US';
        _selectedLanguageName = 'English';
      });
    }
  }

  void _initializeTts() async {
    _flutterTts = FlutterTts();

    // Set up TTS handlers
    _flutterTts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
      });
    });

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
        _currentSpeakingMessage = '';
        _currentSpeakingIndex = -1;
      });
    });

    _flutterTts.setCancelHandler(() {
      setState(() {
        _isSpeaking = false;
        _currentSpeakingMessage = '';
        _currentSpeakingIndex = -1;
      });
    });

    _flutterTts.setErrorHandler((msg) {
      setState(() {
        _isSpeaking = false;
        _currentSpeakingMessage = '';
        _currentSpeakingIndex = -1;
      });
    });

    // Configure TTS settings
    await _flutterTts.setSpeechRate(0.6);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    _configureTtsLanguage();
  }

  Future<void> _configureTtsLanguage() async {
    String ttsLanguage = 'en-US';
    try {
      await _flutterTts.setLanguage(ttsLanguage);
    } catch (e) {
      // Fallback to English if language not available
      await _flutterTts.setLanguage('en-US');
    }
  }

  Future<void> _speakMessage(String text, int messageIndex) async {
    if (_isSpeaking && _currentSpeakingIndex == messageIndex) {
      // Stop speaking if currently speaking this message
      await _flutterTts.stop();
      return;
    }

    if (_isSpeaking) {
      // Stop current speech and start new one
      await _flutterTts.stop();
    }

    setState(() {
      _currentSpeakingMessage = text;
      _currentSpeakingIndex = messageIndex;
    });

    await _configureTtsLanguage();
    await _flutterTts.speak(text);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _rotateController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _flutterTts.stop(); // Stop any ongoing speech
    super.dispose();
  }

  String _getHintText() {
    return _isLoading ? 'Please wait...' : 'Type your message...';
  }

  String _getGrammarCorrectionText(List<Map<String, String>> corrections) {
    if (corrections.isEmpty) return '';

    String intro = 'I think you mean:';

    List<String> correctionLines = [];
    for (var correction in corrections) {
      String type = correction['type']!;
      String original = correction['original']!;
      String corrected = correction['corrected']!;
      correctionLines.add('- $type: "$original" -> "$corrected"');
    }

    return '$intro\n' + correctionLines.join('\n');
  }

  String _getSpeakingText() {
    return 'Speaking...';
  }

  String _getTypingText() {
    return 'Mr. Grammar is typing...';
  }

  String _getGeminiPrompt(String userText) {
    String prompt = '''You are a friendly and encouraging language tutor named Mr. Grammar. Talk normally.
The user sent this message: "$userText"

For each incorrect message (grammatically, logically, etc.), correct it and provide the type of the error. Do not correct capitalization problems.
''';
    return prompt;
  }



  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading || _currentConversation == null) return;

    // Create user message
    final userMessage = {
      'text': text,
      'sender': 'user',
      'timestamp': DateTime.now().millisecondsSinceEpoch
    };

    // Add user message immediately
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      _controller.clear();
    });

    // Save user message to conversation
    await ConversationService.addMessageToConversation(
        widget.conversationId,
        userMessage
    );

    _scrollToBottom();

    try {
      // Update conversation title if it's the first message
      if (_messages.length == 1) {
        final newTitle = text.length > 30 ? '${text.substring(0, 30)}...' : text;
        await ConversationService.updateConversationTitle(
            widget.conversationId,
            newTitle
        );
      }

      // Only check grammar for messages longer than 3 words
      if (text.split(' ').length > 3) {
        final grammarResult = await _checkGrammar(text);

        if (mounted && grammarResult['hasErrors']) {
          final correctionMessage = {
            'text': _getGrammarCorrectionText(grammarResult['corrections']),
            'sender': 'bot',
            'isCorrection': true,
            'timestamp': DateTime.now().millisecondsSinceEpoch
          };

          setState(() {
            _messages.add(correctionMessage);
          });

          await ConversationService.addMessageToConversation(
              widget.conversationId,
              correctionMessage
          );

          _scrollToBottom();

          // Automatically read grammar corrections aloud
          Future.delayed(const Duration(milliseconds: 300), () {
            _speakMessage(_getGrammarCorrectionText(grammarResult['corrections']), _messages.length - 1);
          });

          // Get response for the corrected text
          await _getGeminiResponse(grammarResult['correctedText']);
        } else {
          // No grammar errors, get response for original text
          await _getGeminiResponse(text);
        }
      } else {
        // Short message, skip grammar check
        await _getGeminiResponse(text);
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = {
          'text': 'Sorry, I encountered an error. Please try again.',
          'sender': 'bot',
          'isError': true,
          'timestamp': DateTime.now().millisecondsSinceEpoch
        };

        setState(() {
          _messages.add(errorMessage);
        });

        await ConversationService.addMessageToConversation(
            widget.conversationId,
            errorMessage
        );

        _scrollToBottom();
      }
    }
    finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _checkGrammar(String text, {int retries = 2}) async {
    List<Map<String, String>> corrections = [];
    String currentText = text;
    int offsetAdjustment = 0;

    for (int i = 0; i <= retries; i++) {
      try {
        final response = await http.post(
          Uri.parse('https://api.languagetool.org/v2/check'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'text': text,
            'language': _selectedLanguage,
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final matches = data['matches'] as List<dynamic>;

          for (var match in matches) {
            final offset = (match['offset'] as int);
            final length = match['length'] as int;
            final replacements = match['replacements'] as List<dynamic>;
            final ruleCategory = match['rule']['category']['name'] as String;

            if (replacements.isNotEmpty) {
              final replacement = replacements[0]['value'] as String;
              final originalSnippet = text.substring(offset, offset + length);

              // Ignore corrections where only case has changed
              if (originalSnippet.toLowerCase() == replacement.toLowerCase() &&
                  originalSnippet != replacement) {
                continue;
              }

              corrections.add({
                'original': originalSnippet,
                'corrected': replacement,
                'type': ruleCategory,
              });

              // Apply correction to currentText for subsequent offset calculations
              currentText = currentText.replaceRange(
                  offset + offsetAdjustment,
                  offset + length + offsetAdjustment,
                  replacement
              );
              offsetAdjustment += replacement.length - length;
            }
          }

          return {'hasErrors': corrections.isNotEmpty, 'corrections': corrections, 'correctedText': currentText};
        } else if (response.statusCode == 429) {
          if (i < retries) {
            await Future.delayed(Duration(seconds: (i + 1) * 2));
            continue;
          }
        }

        throw Exception('LanguageTool API error: ${response.statusCode}');
      } catch (e) {
        if (i == retries) {
          return {'hasErrors': false, 'corrections': [], 'correctedText': text, 'error': e.toString()};
        }

        if (i < retries) {
          await Future.delayed(Duration(seconds: (i + 1)));
        }
      }
    }

    return {'hasErrors': false, 'corrections': [], 'correctedText': text};
  }

  Future<void> _getGeminiResponse(String text) async {
    const int maxRetries = 2;

    for (int i = 0; i <= maxRetries; i++) {
      try {
        final response = await http.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {
                    'text': _getGeminiPrompt(text)
                  }
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.7,
              'maxOutputTokens': 256,
            }
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data['candidates'] != null &&
              data['candidates'].isNotEmpty &&
              data['candidates'][0]['content'] != null &&
              data['candidates'][0]['content']['parts'] != null &&
              data['candidates'][0]['content']['parts'].isNotEmpty) {

            final generatedText = data['candidates'][0]['content']['parts'][0]['text'] as String;

            if (mounted) {
              final botMessage = {
                'text': generatedText.trim(),
                'sender': 'bot',
                'timestamp': DateTime.now().millisecondsSinceEpoch
              };

              setState(() {
                _messages.add(botMessage);
              });

              await ConversationService.addMessageToConversation(
                  widget.conversationId,
                  botMessage
              );

              _scrollToBottom();

              // Automatically read bot messages aloud
              Future.delayed(const Duration(milliseconds: 500), () {
                _speakMessage(generatedText.trim(), _messages.length - 1);
              });
            }
            return; // Success, exit the retry loop
          }
        } else if (response.statusCode == 429) {
          // Rate limit
          if (i < maxRetries) {
            await Future.delayed(Duration(seconds: (i + 1) * 3));
            continue;
          }
        } else if (response.statusCode == 401) {
          throw Exception('Invalid API key');
        }

        throw Exception('Gemini API error: ${response.statusCode}');
      } catch (e) {
        if (i == maxRetries) {
          // All retries failed, add fallback response
          if (mounted) {
            final fallbackMessage = {
              'text': 'I understand your message! Unfortunately, I\'m having trouble connecting to my AI service right now. Please try again in a moment.',
              'sender': 'bot',
              'isFallback': true,
              'timestamp': DateTime.now().millisecondsSinceEpoch
            };

            setState(() {
              _messages.add(fallbackMessage);
            });

            await ConversationService.addMessageToConversation(
                widget.conversationId,
                fallbackMessage
            );

            _scrollToBottom();

            // Read fallback message aloud
            Future.delayed(const Duration(milliseconds: 500), () {
              _speakMessage('I understand your message! Unfortunately, I\'m having trouble connecting to my AI service right now. Please try again in a moment.', _messages.length - 1);
            });
          }
          return;
        }

        if (i < maxRetries) {
          await Future.delayed(Duration(seconds: (i + 1) * 2));
        }
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildFloatingParticle(int index) {
    return AnimatedBuilder(
      animation: _rotateController,
      builder: (context, child) {
        final offset = Offset(
          math.sin(_rotateAnimation.value + index * 0.8) * 120 +
              MediaQuery.of(context).size.width * (0.1 + (index % 3) * 0.3),
          math.cos(_rotateAnimation.value + index * 0.6) * 100 +
              MediaQuery.of(context).size.height * (0.1 + (index % 4) * 0.25),
        );

        return Positioned(
          left: offset.dx,
          top: offset.dy,
          child: Container(
            width: 3 + (index % 3) * 1.5,
            height: 3 + (index % 3) * 1.5,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08 + (index % 3) * 0.05),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessage(Map<String, dynamic> message, int index) {
    final isUser = message['sender'] == 'user';
    final isCorrection = message['isCorrection'] == true;
    final isError = message['isError'] == true;
    final isFallback = message['isFallback'] == true;
    final isSpeakingThisMessage = _isSpeaking && _currentSpeakingIndex == index;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                decoration: BoxDecoration(
                  gradient: _getMessageGradient(isUser, isCorrection, isError, isFallback),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isUser ? 20 : 6),
                    bottomRight: Radius.circular(isUser ? 6 : 20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                      spreadRadius: 0,
                    ),
                    if (isUser)
                      BoxShadow(
                        color: Colors.white.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(-2, -2),
                      ),
                    if (isSpeakingThisMessage)
                      BoxShadow(
                        color: Colors.yellow.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 0),
                        spreadRadius: 2,
                      ),
                  ],
                  border: Border.all(
                    color: isSpeakingThisMessage
                        ? Colors.yellow.withOpacity(0.5)
                        : Colors.white.withOpacity(0.2),
                    width: isSpeakingThisMessage ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildCorrectedText(message['text']!),
                        ),
                        const SizedBox(width: 8),
                        // Voice control button
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(15),
                              onTap: () => _speakMessage(message['text']!, index),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: isSpeakingThisMessage
                                    ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                                    : const Icon(
                                  Icons.volume_up,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isSpeakingThisMessage)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.record_voice_over,
                              size: 12,
                              color: Colors.white.withOpacity(0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getSpeakingText(),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCorrectedText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16.0,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  LinearGradient _getMessageGradient(bool isUser, bool isCorrection, bool isError, bool isFallback) {
    if (isUser) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.blue.shade400,
          Colors.indigo.shade500,
        ],
      );
    } else if (isCorrection) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.orange.withOpacity(0.8),
          Colors.deepOrange.withOpacity(0.6),
        ],
      );
    } else if (isError) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.red.withOpacity(0.8),
          Colors.pink.withOpacity(0.6),
        ],
      );
    } else if (isFallback) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.amber.withOpacity(0.8),
          Colors.orange.withOpacity(0.6),
        ],
      );
    } else {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.purple.withOpacity(0.8),
          Colors.indigo.withOpacity(0.6),
        ],
      );
    }
  }

  Widget _buildLoadingIndicator() {
    if (!_isLoading) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.grey.withOpacity(0.3),
              Colors.grey.withOpacity(0.2),
            ],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _getTypingText(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 60,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Mr. Grammar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'English Assistant',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        leading: Container(
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: IconButton(
            iconSize: 18,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [

        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.indigo.shade900,
              Colors.purple.shade700,
              Colors.pink.shade600,
              Colors.orange.shade500,
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Animated background particles
            ...List.generate(12, (index) => _buildFloatingParticle(index)),

            // Main chat interface
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // Messages list
                  Expanded(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(top: 20, bottom: 20),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return _buildLoadingIndicator();
                          }
                          return _buildMessage(_messages[index], index);
                        },
                      ),
                    ),
                  ),

                  // Input area
                  Container(
                    margin: const EdgeInsets.all(16.0),
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            enabled: !_isLoading,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                            decoration: InputDecoration(
                              hintText: _getHintText(),
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20.0,
                                  vertical: 14.0
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isLoading
                                  ? [Colors.grey.shade400, Colors.grey.shade600]
                                  : [Colors.white, Colors.grey.shade100],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(25),
                              onTap: _isLoading ? null : _sendMessage,
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                ),
                                child: _isLoading
                                    ? const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                )
                                    : const Icon(Icons.send_rounded, color: Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isSpeaking ? Container(
        margin: const EdgeInsets.only(bottom: 100),
        child: FloatingActionButton(
          mini: true,
          backgroundColor: Colors.red.withOpacity(0.9),
          onPressed: () async {
            await _flutterTts.stop();
          },
          child: const Icon(
            Icons.stop,
            color: Colors.white,
            size: 20,
          ),
        ),
      ) : null,
    );
  }
}