import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/friend.dart';
import 'package:even_up_app/core/user_session.dart';
import 'package:even_up_app/features/friends/add_friend_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<Friend> _friends = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  Future<void> _fetchFriends() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/friends'),
        headers: UserSession.instance.authHeaders,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _friends = data.map((f) => Friend.fromJson(f)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching friends: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeFriend(Friend friend) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remove Friend'),
        content: Text('Are you sure you want to remove ${friend.name}?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/friends/${friend.id}'),
        headers: UserSession.instance.authHeaders,
      );

      if (response.statusCode == 200) {
        _fetchFriends();
      } else {
        final body = jsonDecode(response.body);
        _showError(body['error'] ?? 'Failed to remove friend');
      }
    } catch (e) {
      _showError('Connection error: $e');
    }
  }

  void _showError(String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Cannot Remove'),
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

  Future<void> _navigateToAddFriend() async {
    final result = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(builder: (context) => const AddFriendScreen()),
    );
    if (result == true) {
      _fetchFriends();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String query = ((_searchQuery as dynamic) is String ? _searchQuery : '').toLowerCase();
    final filteredFriends = _friends.where((f) {
      final dynamic rawName = f.name;
      if (rawName is String) {
        return rawName.toLowerCase().contains(query);
      }
      return 'unknown'.contains(query);
    }).toList();

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
              child: CupertinoSearchTextField(
                placeholder: 'Search friends...',
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            CupertinoListSection.insetGrouped(
              header: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Your Friends'),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: _navigateToAddFriend,
                    child: const Icon(CupertinoIcons.person_add, size: 20),
                  ),
                ],
              ),
              children: _isLoading && _friends.isEmpty
                  ? [const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CupertinoActivityIndicator()))]
                  : filteredFriends.isEmpty
                      ? [
                          const CupertinoListTile(
                            leading: Icon(CupertinoIcons.person_2, color: CupertinoColors.secondaryLabel),
                            title: Text('No friends yet...', style: TextStyle(color: CupertinoColors.secondaryLabel)),
                          )
                        ]
                      : filteredFriends.map((friend) => _buildFriendTile(friend)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendTile(Friend friend) {
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
            friend.name.isNotEmpty ? friend.name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: CupertinoColors.secondaryLabel,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
      title: Text(friend.name),
      subtitle: const Text('All settled up'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        child: const Icon(CupertinoIcons.trash, color: CupertinoColors.destructiveRed, size: 20),
        onPressed: () => _removeFriend(friend),
      ),
      onTap: () {
        // TODO: Friend detail
      },
    );
  }
}
