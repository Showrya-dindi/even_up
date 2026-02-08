import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/friend.dart';
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
      final response = await http.get(Uri.parse('${AppConfig.baseUrl}/friends'));
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
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Friends'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () async {
            final result = await Navigator.of(context).push<bool>(
              CupertinoPageRoute(builder: (context) => const AddFriendScreen()),
            );
            if (result == true) {
              _fetchFriends();
            }
          },
          child: const Icon(CupertinoIcons.person_add),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: CupertinoSearchTextField(
                placeholder: 'Search friends...',
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('Your Friends'),
              children: _isLoading && _friends.isEmpty
                  ? [const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CupertinoActivityIndicator()))]
                  : filteredFriends.isEmpty
                      ? [const Padding(padding: EdgeInsets.all(16.0), child: Text('No friends found', textAlign: TextAlign.center, style: TextStyle(color: CupertinoColors.secondaryLabel)))]
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
      subtitle: const Text('All settled up'), // In a real app, this would be computed
      trailing: const CupertinoListTileChevron(),
      onTap: () {
        // TODO: Friend detail
      },
    );
  }
}
