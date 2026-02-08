import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/expense.dart';
import 'package:even_up_app/core/models/group.dart';
import 'package:even_up_app/core/models/group_member.dart';

class ExpenseDetailScreen extends StatefulWidget {
  final Expense expense;
  final List<GroupMember>? groupMembers;

  const ExpenseDetailScreen({
    super.key, 
    required this.expense,
    this.groupMembers,
  });

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  List<GroupMember>? _members;

  @override
  void initState() {
    super.initState();
    debugPrint('ExpenseDetailScreen: SplitWith indices: ${widget.expense.splitWith}');
    _members = widget.groupMembers;
    if (_members == null && widget.expense.groupId != null) {
      _fetchGroupMembers();
    }
  }

  @override
  void didUpdateWidget(ExpenseDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.groupMembers != _members && widget.groupMembers != null) {
      debugPrint('ExpenseDetailScreen: Updated members from widget: ${widget.groupMembers?.length}');
      setState(() {
        _members = widget.groupMembers;
      });
    }
  }

  Future<void> _fetchGroupMembers() async {
    if (widget.expense.groupId == null) {
      debugPrint('ExpenseDetailScreen: Cannot fetch members - groupId is null');
      return;
    }
    
    try {
      final url = '${AppConfig.baseUrl}/groups/${widget.expense.groupId}';
      debugPrint('ExpenseDetailScreen: Fetching members from $url');
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final group = Group.fromJson(jsonDecode(response.body));
        debugPrint('ExpenseDetailScreen: Fetched ${group.members?.length} members for group ${group.id}');
        if (mounted) {
          setState(() {
            _members = group.members;
          });
        }
      } else {
        debugPrint('ExpenseDetailScreen: Failed to fetch group: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ExpenseDetailScreen: Error fetching group members: $e');
    }
  }

  String _getMemberName(String id) {
    if (_members == null || _members!.isEmpty) {
      debugPrint('ExpenseDetailScreen: Members list empty/null when looking up $id');
      return id;
    }
    final member = _members!.where((m) => m.id == id).firstOrNull;
    if (member == null) {
      debugPrint('ExpenseDetailScreen: Member $id not found in current members list');
    }
    return member?.name ?? id;
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat formatter = DateFormat('MMMM d, yyyy');
    
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Expense Info'),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 24),
            _buildHeader(),
            const SizedBox(height: 32),
            _buildDetailsSection(formatter),
            const SizedBox(height: 32),
            _buildSplitSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: CupertinoColors.activeBlue.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            CupertinoIcons.doc_text_fill,
            size: 40,
            color: CupertinoColors.activeBlue,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.expense.description,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '\$${widget.expense.amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.label,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsSection(DateFormat formatter) {
    return CupertinoListSection.insetGrouped(
      header: const Text('Details'),
      children: [
        CupertinoListTile(
          title: const Text('Paid by'),
          subtitle: Text(_getMemberName(widget.expense.paidBy)),
          leading: const Icon(CupertinoIcons.person_fill, color: CupertinoColors.systemGrey),
        ),
        CupertinoListTile(
          title: const Text('Date'),
          subtitle: Text(formatter.format(widget.expense.createdAt)),
          leading: const Icon(CupertinoIcons.calendar, color: CupertinoColors.systemGrey),
        ),
      ],
    );
  }

  Widget _buildSplitSection() {
    final List<Map<String, dynamic>> splitWithRaw = widget.expense.splitWith;
    
    // If it's empty and 'Equally', we might want to show everyone, 
    // but usually splitWith should be populated by the API.
    
    final bool isEqually = widget.expense.splitType == 'Equally';

    return CupertinoListSection.insetGrouped(
      header: const Text('Split Summary'),
      children: [
        CupertinoListTile(
          title: const Text('Split Type'),
          subtitle: Text(widget.expense.splitType.toUpperCase()),
          leading: const Icon(CupertinoIcons.square_grid_2x2, color: CupertinoColors.systemGrey),
        ),
        if (splitWithRaw.isNotEmpty) ...[
          const CupertinoListTile(
            title: Text('Participants'),
            leading: Icon(CupertinoIcons.person_3_fill, color: CupertinoColors.systemGrey),
          ),
          ...splitWithRaw.map((data) {
            final String id = data['userId']?.toString() ?? 'unknown';
            final double share = isEqually 
                ? widget.expense.amount / splitWithRaw.length
                : (data['amount'] as num?)?.toDouble() ?? 0.0;
                
            return CupertinoListTile(
              title: Text(_getMemberName(id)),
              trailing: Text('\$${share.toStringAsFixed(2)}'),
              leading: const Padding(
                padding: EdgeInsets.only(left: 16.0),
                child: Icon(CupertinoIcons.person, size: 16, color: CupertinoColors.secondaryLabel),
              ),
            );
          }),
        ],
        const CupertinoListTile(
          title: Text('Status'),
          subtitle: Text('Pending Settlement'),
          leading: Icon(CupertinoIcons.info_circle, color: CupertinoColors.systemOrange),
        ),
      ],
    );
  }
}
