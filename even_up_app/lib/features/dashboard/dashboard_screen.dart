import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/group.dart';
import 'package:even_up_app/core/user_session.dart';
import 'package:even_up_app/features/groups/create_group_screen.dart';
import 'package:even_up_app/features/groups/group_detail_screen.dart';
import 'package:even_up_app/core/active_state.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<Group>> _groupsFuture;
  String _searchQuery = ''; // Defensive initialization

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
    final response = await http.get(
      Uri.parse('${AppConfig.baseUrl}/groups'),
      headers: UserSession.instance.authHeaders,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Group.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load groups');
    }
  }

  void _refreshGroups() {
    setState(() {
      _groupsFuture = _fetchGroups();
    });
  }

  Future<void> _navigateToCreateGroup() async {
    final result = await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => const CreateGroupScreen(),
      ),
    );
    if (result == true) {
      _refreshGroups();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(

      child: SafeArea(
        child: FutureBuilder<List<Group>>(
          future: _groupsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CupertinoActivityIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData) {
              return const Center(child: Text('No groups found'));
            }

            final List<Group> groups = snapshot.data ?? [];
            List<Group> filteredGroups = groups;
            
            try {
              final String query = ((_searchQuery as dynamic) is String ? _searchQuery : '').toLowerCase();
              if (query.isNotEmpty) {
                filteredGroups = groups.where((g) {
                  if ((g as dynamic) == null) return false;
                  // Total lockdown: avoid .toString() if property might be undefined
                  final dynamic rawName = g.name;
                  if (rawName is String) {
                    return rawName.toLowerCase().contains(query);
                  }
                  return 'unnamed'.contains(query);
                }).toList();
              }
            } catch (e) {
              debugPrint('Error filtering groups (Dashboard): $e');
              filteredGroups = groups;
            }

            return ListView(
              children: [
                _buildHeader(groups),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: CupertinoSearchTextField(
                    placeholder: 'Search groups...',
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                CupertinoListSection.insetGrouped(
                  header: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Your Groups'),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 0,
                        child: const Icon(CupertinoIcons.add_circled, size: 20),
                        onPressed: _navigateToCreateGroup,
                      ),
                    ],
                  ),
                  children: groups.isEmpty 
                    ? [
                        CupertinoListTile(
                          leading: const Icon(CupertinoIcons.group, color: CupertinoColors.secondaryLabel),
                          title: const Text('No groups yet...', style: TextStyle(color: CupertinoColors.secondaryLabel)),
                        )
                      ]
                    : filteredGroups.isEmpty
                      ? [const Padding(padding: EdgeInsets.all(16.0), child: Text('No matching groups found', textAlign: TextAlign.center, style: TextStyle(color: CupertinoColors.secondaryLabel)))]
                      : filteredGroups.map((group) {
                          try {
                            return CupertinoListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _getGroupIconColor(group.icon),
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    _getGroupIcon(group.icon),
                                    color: _getGroupIconColor(group.icon),
                                    size: 20,
                                  ),
                                ),
                              ),
                              title: Text((group.name as dynamic) is String ? group.name : 'Unnamed'),
                              subtitle: _buildGroupSummary(group),
                              trailing: const CupertinoListTileChevron(),
                              onTap: () {
                                Navigator.of(context).push(
                                  CupertinoPageRoute(
                                    builder: (context) => GroupDetailScreen(
                                      key: UniqueKey(),
                                      group: group,
                                    ),
                                  ),
                                );
                              },
                            );
                          } catch (e) {
                            return const SizedBox.shrink();
                          }
                        }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(List<Group> groups) {
    double totalOwedToMe = 0;
    double totalIOwe = 0;

    for (var group in groups) {
      if (group.memberBalances != null) {
        group.memberBalances!.forEach((_, amount) {
          if (amount > 0) totalOwedToMe += amount;
          if (amount < 0) totalIOwe += amount.abs();
        });
      }
    }

    final double overallBalance = totalOwedToMe - totalIOwe;
    
    String subtitleText;
    Color subtitleColor = CupertinoColors.secondaryLabel;
    
    if (overallBalance.abs() < 0.01) {
      subtitleText = 'You are all settled up';
    } else if (overallBalance > 0) {
      subtitleText = 'You are owed ₹${overallBalance.toStringAsFixed(2)} in total';
      subtitleColor = CupertinoColors.systemGreen;
    } else {
      subtitleText = 'You owe ₹${overallBalance.abs().toStringAsFixed(2)} in total';
      subtitleColor = CupertinoColors.systemOrange;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overall Balance',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 8),
          Text(
            subtitleText,
            style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('You are owed', style: TextStyle(fontSize: 12, color: CupertinoColors.systemGreen)),
                      const SizedBox(height: 4),
                      Text('₹${totalOwedToMe.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: CupertinoColors.systemGreen, fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('You owe', style: TextStyle(fontSize: 12, color: CupertinoColors.systemOrange)),
                      const SizedBox(height: 4),
                      Text('₹${totalIOwe.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: CupertinoColors.systemOrange, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildGroupSummary(Group group) {
    if (group.memberBalances == null || group.memberBalances!.isEmpty) {
      return const Text('Settled up', style: TextStyle(color: CupertinoColors.secondaryLabel));
    }

    List<Widget> balances = [];
    group.memberBalances!.forEach((memberId, amount) {
      if (amount.abs() < 0.01) return;

      String memberName = 'Unknown';
      if (group.members != null) {
        for (var member in group.members!) {
          if (member.id == memberId) {
            memberName = member.name;
            break;
          }
        }
      }
      
      if (memberName == 'Unknown' && memberId.startsWith('friend-')) {
          memberName = 'Friend ${memberId.split('-').last}';
      }

      if (amount > 0) {
        balances.add(Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Text(
            '$memberName owes you ₹${amount.toStringAsFixed(2)}',
            style: const TextStyle(color: CupertinoColors.systemGreen, fontSize: 13),
          ),
        ));
      } else {
        balances.add(Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Text(
            'You owe $memberName ₹${amount.abs().toStringAsFixed(2)}',
            style: const TextStyle(color: CupertinoColors.systemOrange, fontSize: 13),
          ),
        ));
      }
    });

    if (balances.isEmpty) {
      return const Text('Settled up', style: TextStyle(color: CupertinoColors.secondaryLabel));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: balances,
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        _buildHeader([]),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 64.0),
            child: Column(
              children: [
                const Icon(CupertinoIcons.group, size: 64, color: CupertinoColors.systemGrey3),
                const SizedBox(height: 16),
                const Text('No groups yet', style: TextStyle(color: CupertinoColors.secondaryLabel)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _getGroupIcon(String? icon) {
    switch (icon) {
      case 'home':
        return CupertinoIcons.house_fill;
      case 'trip':
        return CupertinoIcons.airplane;
      case 'coffee':
        return CupertinoIcons.cart_fill;
      case 'group':
      default:
        return CupertinoIcons.person_3_fill;
    }
  }

  Color _getGroupIconColor(String? icon) {
    switch (icon) {
      case 'home':
        return CupertinoColors.systemGreen;
      case 'trip':
        return CupertinoColors.systemBlue;
      case 'coffee':
        return CupertinoColors.systemBrown;
      case 'group':
      default:
        return CupertinoColors.systemOrange;
    }
  }
}
