import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/friend.dart';
import 'package:even_up_app/core/user_session.dart';
import 'package:even_up_app/core/active_state.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _category = 'Other';
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
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/friends'),
        headers: UserSession.instance.authHeaders,
      );
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

  Future<void> _saveGroup() async {
    if (_nameController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final members = [UserSession.instance.userId, ..._selectedMemberIds];
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/groups'),
        headers: UserSession.instance.authHeaders,
        body: jsonEncode({
          'name': _nameController.text,
          'members': members,
        }),
      );

      if (response.statusCode == 201) {
        if (!mounted) return;
        activeGroupState.notifyGroupsChanged();
        Navigator.pop(context, true);
      } else {
        throw Exception('Failed to create group');
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
        middle: const Text('Create Group'),
        trailing: _isLoading 
          ? const CupertinoActivityIndicator()
          : CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _saveGroup,
              child: const Text('Done'),
            ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('Group Details'),
              children: [
                CupertinoTextFormFieldRow(
                  controller: _nameController,
                  placeholder: 'Group Name',
                  prefix: const Icon(CupertinoIcons.group, size: 20),
                ),
              ],
            ),
            
            // Member Selection (Mirroring AddExpenseScreen)
            const Padding(
              padding: EdgeInsets.only(left: 20.0, top: 16.0, bottom: 8.0),
              child: Text(
                'MEMBERS',
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
                  final filteredFriends = _availableFriends.where((f) {
                    final dynamic rawName = f.name;
                    if (rawName is String) {
                      return rawName.toLowerCase().contains(query);
                    }
                    return 'unknown'.contains(query);
                  }).toList();

                  if (filteredFriends.isEmpty && _availableFriends.isNotEmpty) {
                    return const Center(
                      child: Text('No friends found', style: TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 13)),
                    );
                  }

                  if (_availableFriends.isEmpty) {
                    return const Center(child: CupertinoActivityIndicator());
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

            CupertinoListSection.insetGrouped(
              header: const Text('Category'),
              children: [
                _buildCategoryTile('Trip', CupertinoIcons.airplane),
                _buildCategoryTile('Home', CupertinoIcons.house),
                _buildCategoryTile('Couple', CupertinoIcons.heart),
                _buildCategoryTile('Other', CupertinoIcons.ellipsis),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(String title, IconData icon) {
    return CupertinoListTile(
      leading: Icon(icon, size: 20),
      title: Text(title),
      trailing: _category == title 
        ? const Icon(CupertinoIcons.checkmark, color: CupertinoColors.activeBlue) 
        : null,
      onTap: () => setState(() => _category = title),
    );
  }
}
