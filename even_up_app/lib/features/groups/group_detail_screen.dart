import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/group.dart';
import 'package:even_up_app/core/models/expense.dart';
import 'package:even_up_app/features/expenses/expense_detail_screen.dart';
import 'package:even_up_app/features/groups/add_member_screen.dart';
import 'package:even_up_app/features/groups/group_info_screen.dart';
import 'package:even_up_app/core/active_state.dart';

class GroupDetailScreen extends StatefulWidget {
  final Group group;
  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  Future<List<Expense>>? _expensesFetchFuture;
  Future<Group>? _groupDetailsFetchFuture;

  @override
  void initState() {
    super.initState();
    activeGroupState.setActiveGroup(widget.group.id);
    _loadData();
  }

  @override
  void dispose() {
    activeGroupState.clearActiveGroup();
    super.dispose();
  }

  void _loadData() {
    _expensesFetchFuture = _fetchExpenses();
    _groupDetailsFetchFuture = _fetchGroupDetails();
  }

  Future<List<Expense>> _fetchExpenses() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/groups/${widget.group.id}/expenses')
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Expense.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load expenses');
      }
    } catch (e) {
      debugPrint('Error fetching expenses: $e');
      rethrow;
    }
  }

  Future<Group> _fetchGroupDetails() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/groups/${widget.group.id}')
      );

      if (response.statusCode == 200) {
        return Group.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load group details');
      }
    } catch (e) {
      debugPrint('Error fetching group details: $e');
      rethrow;
    }
  }

  void _refreshData() {
    setState(() {
      _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ensure futures are initialized even if initState didn't run (e.g. after hot reload)
    final expensesFuture = _expensesFetchFuture ?? _fetchExpenses();
    final groupFuture = _groupDetailsFetchFuture ?? _fetchGroupDetails();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: FutureBuilder<Group>(
          future: groupFuture,
          builder: (context, snapshot) {
            final name = snapshot.hasData ? snapshot.data!.name : widget.group.name;
            final icon = snapshot.hasData ? snapshot.data!.icon : widget.group.icon;
            return GestureDetector(
              onTap: () {
                if (snapshot.hasData) {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => GroupInfoScreen(group: snapshot.data!),
                    ),
                  );
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getGroupIcon(icon),
                    size: 18,
                    color: _getGroupIconColor(icon),
                  ),
                  const SizedBox(width: 8),
                  Text(name),
                  const Padding(
                    padding: EdgeInsets.only(left: 4.0),
                    child: Icon(CupertinoIcons.chevron_down, size: 14),
                  ),
                ],
              ),
            );
          },
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.person_add),
              onPressed: () async {
                final result = await Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) => AddMemberScreen(group: widget.group),
                  ),
                );
                if (result == true) {
                  _refreshData();
                }
              },
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: FutureBuilder<List<Expense>>(
          future: expensesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CupertinoActivityIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                child: Text('No expenses yet', style: TextStyle(color: CupertinoColors.secondaryLabel)),
              );
            }

            final expenses = snapshot.data!;
            return ListView.builder(
              itemCount: expenses.length,
              itemBuilder: (context, index) {
                final expense = expenses[index];
                const currentUserId = 'local-user-123';
                
                String balanceText = '';
                Color balanceColor = CupertinoColors.label;
                
                if (!expense.isUserInvolved(currentUserId)) {
                  balanceText = 'not involved';
                  balanceColor = CupertinoColors.secondaryLabel;
                } else if (expense.paidBy == currentUserId) {
                  final lentAmount = expense.amount - expense.getShareOf(currentUserId);
                  if (lentAmount > 0) {
                    balanceText = 'you lent \$${lentAmount.toStringAsFixed(2)}';
                    balanceColor = CupertinoColors.systemGreen;
                  } else {
                    balanceText = 'you paid';
                    balanceColor = CupertinoColors.secondaryLabel;
                  }
                } else {
                  final myShare = expense.getShareOf(currentUserId);
                  if (myShare > 0) {
                    balanceText = 'you owe \$${myShare.toStringAsFixed(2)}';
                    balanceColor = CupertinoColors.systemOrange;
                  } else {
                    balanceText = 'not involved';
                    balanceColor = CupertinoColors.secondaryLabel;
                  }
                }

                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (context) => FutureBuilder<Group>(
                          future: groupFuture,
                          builder: (context, groupSnapshot) {
                            return ExpenseDetailScreen(
                              expense: expense,
                              groupMembers: groupSnapshot.data?.members,
                            );
                          },
                        ),
                      ),
                    );
                  },
                  child: CupertinoListTile(
                    leading: const Icon(CupertinoIcons.doc_text, color: CupertinoColors.activeBlue),
                    title: Text(expense.description),
                    subtitle: Text('Paid by ${expense.paidBy == currentUserId ? 'you' : expense.paidBy}'),
                    trailing: Text(
                      balanceText,
                      style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
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
