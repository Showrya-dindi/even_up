import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class GenieScreen extends StatefulWidget {
  const GenieScreen({super.key});

  @override
  State<GenieScreen> createState() => _GenieScreenState();
}

class _GenieScreenState extends State<GenieScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [
    {
      'role': 'bot',
      'content': 'Hi! I\'m Genie, your AI finance assistant. How can I help you today?'
    },
    {
      'role': 'bot',
      'content': 'Try asking me things like:\n• "Who owes me most?"\n• "Summarize my spending in Trip to Goa"\n• "Split a ₹500 bill with Showrya"'
    },
  ];

  void _handleSend() {
    if (_controller.text.trim().isEmpty) return;

    setState(() {
      _messages.add({
        'role': 'user',
        'content': _controller.text.trim(),
      });
      _controller.clear();
      
      // Simulate bot typing
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _messages.add({
              'role': 'bot',
              'content': 'That sounds like a great question! I\'m still learning how to access your group data, but soon I\'ll be able to calculate that for you instantly. ✨',
            });
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Genie AI'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isBot = msg['role'] == 'bot';
                  return Align(
                    alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: isBot ? CupertinoColors.white : CupertinoColors.systemPurple,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isBot ? 4 : 16),
                          bottomRight: Radius.circular(isBot ? 16 : 4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        msg['content']!,
                        style: TextStyle(
                          color: isBot ? CupertinoColors.label : CupertinoColors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        border: Border(top: BorderSide(color: CupertinoColors.separator.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: _controller,
              placeholder: 'Ask Genie...',
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _handleSend,
            child: const Icon(CupertinoIcons.arrow_up_circle_fill, size: 32, color: CupertinoColors.systemPurple),
          ),
        ],
      ),
    );
  }
}
