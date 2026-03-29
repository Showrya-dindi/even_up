import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/user_session.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  List<dynamic> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/friend-requests'),
        headers: UserSession.instance.authHeaders,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _requests = data;
            _isLoading = false;
          });
          UserSession.instance.setPendingRequestCount(data.length);
        }
      }
    } catch (e) {
      debugPrint('Error fetching friend requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _respondToRequest(String fromUserId, String action) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/friend-requests/respond'),
        headers: UserSession.instance.authHeaders,
        body: jsonEncode({'fromUserId': fromUserId, 'action': action}),
      );
      if (response.statusCode == 200) {
        _fetchRequests();
      } else {
        final body = jsonDecode(response.body);
        _showError(body['error'] ?? 'Action failed');
      }
    } catch (e) {
      _showError('Connection error: $e');
    }
  }

  void _showError(String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Friend Requests'),
      ),
      child: SafeArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : _requests.isEmpty
                ? const Center(child: Text('No pending requests', style: TextStyle(color: CupertinoColors.secondaryLabel)))
                : ListView.builder(
                    itemCount: _requests.length,
                    itemBuilder: (context, index) {
                      final req = _requests[index];
                      return CupertinoListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: CupertinoColors.systemGrey5,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              req['fromUserName']?[0]?.toUpperCase() ?? '?',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        title: Text(req['fromUserName'] ?? 'Unknown User'),
                        subtitle: Text(req['fromUserEmail'] ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => _respondToRequest(req['fromUserId'], 'ACCEPT'),
                              child: const Icon(CupertinoIcons.checkmark_circle_fill, color: CupertinoColors.activeGreen),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => _respondToRequest(req['fromUserId'], 'REJECT'),
                              child: const Icon(CupertinoIcons.xmark_circle_fill, color: CupertinoColors.destructiveRed),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
