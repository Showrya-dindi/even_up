import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/friend.dart';
import 'package:even_up_app/core/models/group.dart';
import 'package:even_up_app/core/active_state.dart';

class AddMemberScreen extends StatefulWidget {
  final Group group;
  const AddMemberScreen({super.key, required this.group});

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  bool _isLoading = false;
  List<Friend> _availableFriends = [];
  final Set<String> _selectedMemberIds = {};
  String _memberSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  Future<void> _fetchFriends() async {
    try {
      final response = await http.get(Uri.parse('${AppConfig.baseUrl}/friends'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _availableFriends = data.map((f) => Friend.fromJson(f)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching friends: $e');
    }
  }

  Future<void> _addMembers() async {
    if (_selectedMemberIds.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/groups/members'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'groupId': widget.group.id,
          'members': _selectedMemberIds.toList(),
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        activeGroupState.notifyGroupsChanged();
        Navigator.pop(context, true);
      } else {
        throw Exception('Failed to add members');
      }
    } catch (e) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Error'),
          content: Text(e.toString()),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('Add to ${widget.group.name}'),
        trailing: _isLoading 
          ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _selectedMemberIds.isEmpty ? null : _addMembers,
                child: const Text('Add'),
              ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 20.0, top: 16.0, bottom: 8.0),
              child: Text(
                'SELECT FRIENDS',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: CupertinoSearchTextField(
                placeholder: 'Search friends...',
                onChanged: (value) => setState(() => _memberSearchQuery = value),
              ),
            ),
            SizedBox(
              height: 100,
              child: Builder(
                builder: (context) {
                  final String query = ((_memberSearchQuery as dynamic) is String ? _memberSearchQuery : '').toLowerCase();
                  
                  // Filter out friends who are already in the group
                  final existingMemberIds = (widget.group.members ?? []).map((m) => m.id).toSet();
                  
                  final filteredFriends = _availableFriends.where((f) {
                    final isExisting = existingMemberIds.contains(f.id);
                    final dynamic rawName = f.name;
                    if (rawName is String) {
                      final matchesQuery = rawName.toLowerCase().contains(query);
                      return !isExisting && matchesQuery;
                    }
                    return !isExisting && 'unknown'.contains(query);
                  }).toList();

                  if (_availableFriends.isEmpty) {
                    return const Center(child: CupertinoActivityIndicator());
                  }

                  if (filteredFriends.isEmpty) {
                    return const Center(
                      child: Text(
                        'No eligible friends found', 
                        style: TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 13),
                      ),
                    );
                  }

                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: filteredFriends.length,
                    itemBuilder: (context, index) {
                      final friend = filteredFriends[index];
                      final isSelected = _selectedMemberIds.contains(friend.id);
                      
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedMemberIds.remove(friend.id);
                            } else {
                              _selectedMemberIds.add(friend.id);
                            }
                          });
                        },
                        child: Container(
                          width: 80,
                          margin: const EdgeInsets.only(right: 8.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey5,
                                  shape: BoxShape.circle,
                                  border: isSelected ? Border.all(color: CupertinoColors.activeBlue, width: 2) : null,
                                ),
                                child: Center(
                                  child: Text(
                                    friend.name.isNotEmpty ? friend.name[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: isSelected ? CupertinoColors.white : CupertinoColors.secondaryLabel,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                friend.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  color: isSelected ? CupertinoColors.label : CupertinoColors.secondaryLabel,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            
            if (_selectedMemberIds.isNotEmpty)
              CupertinoListSection.insetGrouped(
                header: const Text('Selected to Add'),
                children: _selectedMemberIds.map((id) {
                  final friend = _availableFriends.firstWhere((f) => f.id == id);
                  return CupertinoListTile(
                    leading: const Icon(CupertinoIcons.person_fill, size: 20),
                    title: Text(friend.name),
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Icon(CupertinoIcons.minus_circle_fill, color: CupertinoColors.destructiveRed, size: 20),
                      onPressed: () => setState(() => _selectedMemberIds.remove(id)),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
