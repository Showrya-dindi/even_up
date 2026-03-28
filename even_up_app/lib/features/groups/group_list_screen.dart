import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/group.dart';
import 'package:even_up_app/features/groups/group_detail_screen.dart';
import 'package:even_up_app/core/active_state.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  late Future<List<Group>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _fetchGroups();
    activeGroupState.addListener(_refreshGroups);
  }

  @override
  void dispose() {
    activeGroupState.removeListener(_refreshGroups);
    super.dispose();
  }

  Future<List<Group>> _fetchGroups() async {
    final response = await http.get(Uri.parse('${AppConfig.baseUrl}/groups'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Group.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load groups');
    }
  }

  void _refreshGroups() {
    if (mounted) {
      setState(() {
        _groupsFuture = _fetchGroups();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Groups'),
      ),
      child: SafeArea(
        child: FutureBuilder<List<Group>>(
          future: _groupsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CupertinoActivityIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No groups found', style: TextStyle(color: CupertinoColors.secondaryLabel)));
            }

            final groups = snapshot.data!;
            return ListView(
              children: [
                CupertinoListSection.insetGrouped(
                  header: const Text('Your Groups'),
                  children: groups.map((group) => CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.group,
                      color: CupertinoColors.systemOrange,
                    ),
                    title: Text(group.name),
                    subtitle: Text(group.createdBy == 'local-user-123' ? 'You created this' : 'Added by ${group.createdBy}'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () {
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (context) => GroupDetailScreen(group: group),
                        ),
                      );
                    },
                  )).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
