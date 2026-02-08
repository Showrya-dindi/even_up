import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/group.dart';
import 'package:even_up_app/core/models/group_member.dart';
import 'package:even_up_app/core/active_state.dart';
import 'package:flutter/material.dart'
    show showModalBottomSheet, RoundedRectangleBorder, Radius;

class AddExpenseScreen extends StatefulWidget {
  final String? groupId;
  final CupertinoTabController? tabController;
  const AddExpenseScreen({super.key, this.groupId, this.tabController});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  ScrollController? _groupScrollController;
  String _splitType = 'Equally';
  bool _isLoading = false;

  List<Group> _availableGroups = [];
  String? _selectedGroupId;
  bool _isFetchingGroups = false;
  String _memberSearchQuery = '';
  Set<String> _selectedMemberIds = {};
  final Map<String, TextEditingController> _exactAmountControllers = {};

  String _paidByUserId = 'local-user-123';
  bool _isRecalculating = false;
  List<String> _memberOrder = [];

  @override
  void initState() {
    super.initState();
    _paidByUserId = 'local-user-123';
    _availableGroups = [];
    _selectedGroupId = widget.groupId ?? activeGroupState.currentGroupId;
    _groupScrollController = ScrollController();

    // Listen for changes in active group (e.g. when switching tabs)
    activeGroupState.addListener(_onActiveGroupChanged);

    // Always fetch groups to populate the list
    _fetchGroups();

    _amountController.addListener(_recalculateSplits);
    widget.tabController?.addListener(_onTabChanged);

    // Initial reset to ensure clean state
    _resetState();
  }

  @override
  void dispose() {
    activeGroupState.removeListener(_onActiveGroupChanged);
    widget.tabController?.removeListener(_onTabChanged);
    _descriptionController.dispose();
    _amountController.dispose();
    _groupScrollController?.dispose();
    for (var controller in _exactAmountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onActiveGroupChanged() {
    if (mounted) {
      // Re-fetch groups because the list might have changed (e.g. new group created)
      _fetchGroups();

      if (widget.groupId == null) {
        _updateSelection();
      }
    }
  }

  void _updateSelection() {
    final activeId = activeGroupState.currentGroupId;
    setState(() {
      if (activeId != null) {
        _selectedGroupId = activeId;
      } else if (_selectedGroupId == null && _availableGroups.isNotEmpty) {
        _selectedGroupId = _availableGroups.first.id;
      }
      _reorderGroups();
      _updateSelectedMembers();
    });
  }

  void _syncExactAmountControllers() {
    // Add missing controllers
    for (var id in _selectedMemberIds) {
      if (!_exactAmountControllers.containsKey(id)) {
        final controller = TextEditingController(text: '0.00');
        controller.addListener(_recalculateSplits);
        _exactAmountControllers[id] = controller;
      }
    }
    // Note: We don't necessarily remove them to avoid losing data if user deselects and reselects
  }

  void _recalculateSplits() {
    if (_isRecalculating || _selectedMemberIds.isEmpty || !mounted) return;

    final totalText = _amountController.text;
    if (totalText.isEmpty) {
      // Clear amounts if total is empty
      for (var id in _selectedMemberIds) {
        _exactAmountControllers[id]?.text = '0.00';
      }
      return;
    }

    final Group? currentGroup = _availableGroups.cast<Group?>().firstWhere(
      (g) => g != null && g.id == _selectedGroupId,
      orElse: () => _availableGroups.isNotEmpty ? _availableGroups.first : null,
    );
    if (currentGroup == null || currentGroup.members == null) return;

    final List<String> currentOrder = _memberOrder;
    if (currentOrder == null) return;

    // Use the actual group member order to determine who is "last" for exact splits
    final List<String> sortedSelectedIds = currentGroup.members!
        .map((m) => m.id)
        .where(
          (id) => currentOrder.contains(id) && _selectedMemberIds.contains(id),
        )
        .toList();

    if (sortedSelectedIds.isEmpty) return;

    _isRecalculating = true;
    try {
      final totalAmount = double.tryParse(totalText) ?? 0.0;

      if (_splitType == 'Equally') {
        final share = (totalAmount / sortedSelectedIds.length);
        // Truncate to 2 decimals for all but the last
        final shareStr = share.toStringAsFixed(2);
        double distributedSum = 0;

        for (int i = 0; i < sortedSelectedIds.length - 1; i++) {
          final id = sortedSelectedIds[i];
          final controller = _exactAmountControllers[id];
          if (controller != null) {
            controller.text = shareStr;
            distributedSum += double.parse(shareStr);
          }
        }

        // Give the remainder to the last person
        final lastId = sortedSelectedIds.last;
        final remainder = totalAmount - distributedSum;
        final lastController = _exactAmountControllers[lastId];
        if (lastController != null) {
          lastController.text = remainder.toStringAsFixed(2);
        }
      } else {
        // Exact split logic
        double otherSum = 0.0;
        for (int i = 0; i < sortedSelectedIds.length - 1; i++) {
          final id = sortedSelectedIds[i];
          final controller = _exactAmountControllers[id];
          if (controller != null) {
            final val = double.tryParse(controller.text) ?? 0.0;
            otherSum += val;
          }
        }

        final lastId = sortedSelectedIds.last;
        final remaining = (totalAmount - otherSum).clamp(0.0, double.infinity);

        final lastController = _exactAmountControllers[lastId];
        if (lastController != null) {
          final currentLastValStr = lastController.text;
          final newLastValStr = remaining.toStringAsFixed(2);

          if (currentLastValStr != newLastValStr) {
            lastController.text = newLastValStr;
          }
        }
      }
    } catch (e) {
      debugPrint('Error recalculating splits: $e');
    } finally {
      _isRecalculating = false;
      if (mounted) setState(() {});
    }
  }

  void _updateSelectedMembers() {
    final String? groupId = _selectedGroupId;
    final List<Group> groups = _availableGroups;

    if (groupId == null || groups == null || groups.isEmpty) {
      _selectedMemberIds = {};
      return;
    }

    try {
      final group = groups.firstWhere(
        (g) => g != null && g.id == groupId,
        orElse: () => groups.first,
      );

      if (group != null && group.members != null) {
        final List<String> newIds = group.members!.map((m) => m.id).toList();

        // Use a local reference for _memberOrder to help DDC
        List<String> currentOrder = _memberOrder;
        if (currentOrder == null) currentOrder = [];

        final bool isSame =
            (currentOrder.length == newIds.length) &&
            (currentOrder.every((id) => newIds.contains(id)));

        if (!isSame) {
          _memberOrder = List.from(newIds);
          currentOrder = _memberOrder;

          // Ensure paidBy is at the start if it exists in this group
          if (currentOrder.contains(_paidByUserId)) {
            currentOrder.remove(_paidByUserId);
            currentOrder.insert(0, _paidByUserId);
          } else if (currentOrder.isNotEmpty) {
            _paidByUserId = currentOrder.first;
          }
        }

        _selectedMemberIds = currentOrder.toSet();
        _syncExactAmountControllers();
        _recalculateSplits();
      } else {
        _selectedMemberIds = {};
        _memberOrder = [];
      }
    } catch (e) {
      debugPrint('AddExpenseScreen: Error updating selected members: $e');
      _selectedMemberIds = {};
      _memberOrder = [];
    }
  }

  void _reorderGroups() {
    if (_selectedGroupId == null || _availableGroups.isEmpty) return;

    final selectedIndex = _availableGroups.indexWhere(
      (g) => g.id == _selectedGroupId,
    );
    if (selectedIndex > 0) {
      final selectedGroup = _availableGroups.removeAt(selectedIndex);
      _availableGroups.insert(0, selectedGroup);

      // Scroll back to start to show the newly moved item
      if (_groupScrollController != null &&
          _groupScrollController!.hasClients) {
        _groupScrollController!.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> _fetchGroups() async {
    if (!mounted) return;
    setState(() => _isFetchingGroups = true);
    try {
      final response = await http.get(Uri.parse('${AppConfig.baseUrl}/groups'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _availableGroups = data
                .map((json) => Group.fromJson(json))
                .toList();
          });
          _updateSelection();
        }
      }
    } catch (e) {
      debugPrint('Error fetching groups: $e');
    } finally {
      if (mounted) setState(() => _isFetchingGroups = false);
    }
  }

  Future<void> _saveExpense() async {
    if (_descriptionController.text.isEmpty || _amountController.text.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final targetGroupId = _selectedGroupId ?? widget.groupId;
      if (targetGroupId == null) {
        throw Exception('Please select a group');
      }

      final List<Map<String, dynamic>> splitWithData = [];
      double currentSum = 0;
      final totalAmount = double.tryParse(_amountController.text) ?? 0.0;

      for (var id in _selectedMemberIds) {
        final val =
            double.tryParse(_exactAmountControllers[id]?.text ?? '0') ?? 0.0;
        currentSum += val;
        splitWithData.add({'userId': id, 'amount': val});
      }

      if (_splitType == 'Exact' && (currentSum - totalAmount).abs() > 0.01) {
        throw Exception(
          'The sum of split amounts (₹${currentSum.toStringAsFixed(2)}) must equal the total amount (₹${totalAmount.toStringAsFixed(2)})',
        );
      }

      final expenseData = {
        'description': _descriptionController.text,
        'amount': double.parse(_amountController.text),
        'groupId': targetGroupId,
        'paidBy': _paidByUserId,
        'splitType': _splitType,
        'splitWith': splitWithData,
      };

      debugPrint('AddExpenseScreen: Saving expense with data: $expenseData');

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/expenses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(expenseData),
      );

      if (response.statusCode == 201) {
        if (!mounted) return;

        if (widget.groupId != null) {
          // If we have a groupId, we were likely pushed from a detail screen
          Navigator.of(context).pop(true);
        } else {
          // If no groupId, we are likely in the "Add" tab.
          // Reset form and switch to first tab after this build frame.
          _resetState();
          if (widget.tabController != null) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                widget.tabController!.index = 0; // Switch back to 'Groups'
              }
            });
          }
        }
      } else {
        throw Exception('Failed to save expense: ${response.statusCode}');
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

  void _onTabChanged() {
    if (widget.tabController?.index == 2) {
      _resetState();
    }
  }

  void _resetState() {
    setState(() {
      _descriptionController.clear();
      _amountController.clear();
      _splitType = 'Equally';
      _selectedMemberIds = {};
      _exactAmountControllers.clear();
      _paidByUserId = 'local-user-123';
      _updateSelectedMembers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Add Expense'),
        trailing: _isLoading
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _saveExpense,
                child: const Text('Save'),
              ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (widget.groupId == null)
                _availableGroups.isEmpty && _isFetchingGroups
                    ? const SizedBox(
                        height: 100,
                        child: Center(child: CupertinoActivityIndicator()),
                      )
                    : _buildGroupSelector(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 24.0,
                  horizontal: 16.0,
                ),
                child: Column(
                  children: [
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '₹',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.label.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IntrinsicWidth(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 60),
                              child: CupertinoTextField(
                                controller: _amountController,
                                placeholder: '0',
                                style: const TextStyle(
                                  fontSize: 64,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -1,
                                  color: CupertinoColors.label,
                                ),
                                placeholderStyle: TextStyle(
                                  fontSize: 64,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -1,
                                  color: CupertinoColors.systemGrey3,
                                ),
                                decoration: null,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textAlign: TextAlign.center,
                                cursorColor: CupertinoColors.activeBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: CupertinoTextField(
                        controller: _descriptionController,
                        placeholder: 'What is this for?',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: CupertinoColors.label,
                        ),
                        placeholderStyle: const TextStyle(
                          fontSize: 16,
                          color: CupertinoColors.secondaryLabel,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey6,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        prefix: const Padding(
                          padding: EdgeInsets.only(left: 12.0),
                          child: Icon(
                            CupertinoIcons.pencil,
                            size: 16,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildSplitSummary(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupSelector() {
    final Group? currentGroup = _availableGroups.cast<Group?>().firstWhere(
      (g) => g?.id == _selectedGroupId,
      orElse: () => _availableGroups.isNotEmpty ? _availableGroups.first : null,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 0.0),
      child: Center(
        child: GestureDetector(
          onTap: () => _showGroupSelectionModal(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey5.withOpacity(0.5),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentGroup != null) ...[
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _getGroupIconColor(currentGroup.icon),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getGroupIcon(currentGroup.icon),
                      color: CupertinoColors.white,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      currentGroup.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: CupertinoColors.label,
                      ),
                    ),
                  ),
                ] else
                  const Text(
                    'Select Group',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: CupertinoColors.label,
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(
                  CupertinoIcons.chevron_down,
                  size: 14,
                  color: CupertinoColors.secondaryLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showGroupSelectionModal() {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Select Group'),
        actions: _availableGroups.map((group) {
          return CupertinoActionSheetAction(
            onPressed: () {
              setState(() {
                _selectedGroupId = group.id;
                _updateSelectedMembers();
              });
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getGroupIcon(group.icon),
                  color: _getGroupIconColor(group.icon),
                ),
                const SizedBox(width: 10),
                Text(group.name),
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _buildSplitSummary() {
    final Group? currentGroup = _availableGroups.cast<Group?>().firstWhere(
      (g) => g?.id == _selectedGroupId,
      orElse: () => _availableGroups.isNotEmpty ? _availableGroups.first : null,
    );

    if (currentGroup == null) return const SizedBox.shrink();

    final visibleIds = _selectedMemberIds.toList();
    // Ensure payer is in the list for display if not selected (though logic usually keeps them)
    if (!visibleIds.contains(_paidByUserId)) {
      visibleIds.insert(0, _paidByUserId);
    }

    // Sort: Payer first, then others by original order
    visibleIds.sort((a, b) {
      if (a == _paidByUserId) return -1;
      if (b == _paidByUserId) return 1;
      return _memberOrder.indexOf(a).compareTo(_memberOrder.indexOf(b));
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SPLIT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.secondaryLabel,
                  letterSpacing: 0.5,
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                child: const Text(
                  'Edit',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.activeBlue,
                  ),
                ),
                onPressed: _openSplitEditor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.systemGrey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: visibleIds.asMap().entries.map((entry) {
                final index = entry.key;
                final id = entry.value;
                final isLast = index == visibleIds.length - 1;

                final member = currentGroup.members?.firstWhere(
                  (m) => m.id == id,
                  orElse: () => GroupMember(
                    id: id,
                    name: 'Unknown',
                    joinedAt: DateTime.now(),
                  ),
                );
                final isPayer = id == _paidByUserId;
                final share = _selectedMemberIds.contains(id)
                    ? (_exactAmountControllers[id]?.text ?? '0.00')
                    : '0.00';

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isPayer
                                  ? CupertinoColors.systemOrange.withOpacity(
                                      0.15,
                                    )
                                  : CupertinoColors.systemGrey6,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                member?.name.isNotEmpty == true
                                    ? member!.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: isPayer
                                      ? CupertinoColors.systemOrange
                                      : CupertinoColors.label,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member?.name ?? 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: CupertinoColors.label,
                                  ),
                                ),
                                if (isPayer)
                                  const Text(
                                    'Paid bill',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: CupertinoColors.systemOrange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '₹$share',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: CupertinoColors.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Padding(
                        padding: const EdgeInsets.only(left: 66.0),
                        child: Container(
                          height: 1,
                          color: CupertinoColors.systemGrey6,
                        ),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _openSplitEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: CupertinoColors.systemBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, sheetSetState) {
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Edit Split',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Text(
                          'Done',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: CupertinoColors.separator),
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildSplitEditorContent(sheetSetState),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSplitEditorContent(StateSetter sheetSetState) {
    final Group? currentGroup = _availableGroups.cast<Group?>().firstWhere(
      (g) => g?.id == _selectedGroupId,
      orElse: () => _availableGroups.isNotEmpty ? _availableGroups.first : null,
    );

    if (currentGroup == null || _memberOrder == null || _memberOrder.isEmpty)
      return const SizedBox.shrink();

    final visibleEntries = _memberOrder.asMap().entries.where((entry) {
      final String id = entry.value;
      final member = currentGroup.members!.firstWhere((m) => m.id == id);
      final query = _memberSearchQuery.toLowerCase();
      return query.isEmpty || member.name.toLowerCase().contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 16.0,
            bottom: 8.0,
          ),
          child: Row(
            children: [
              SizedBox(
                height: 32,
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: _splitType,
                  children: const {
                    'Equally': Text('Equal', style: TextStyle(fontSize: 12)),
                    'Exact': Text('Exact', style: TextStyle(fontSize: 12)),
                  },
                  onValueChanged: (value) {
                    if (value != null) {
                      sheetSetState(() {});
                      setState(() {
                        _splitType = value;
                        _recalculateSplits();
                      });
                    }
                  },
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Text(
                    'Select All',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.label,
                    ),
                  ),
                  CupertinoCheckbox(
                    value: _selectedMemberIds.length == _memberOrder.length,
                    onChanged: (bool? value) {
                      sheetSetState(() {});
                      setState(() {
                        if (value == true) {
                          _selectedMemberIds = _memberOrder.toSet();
                        } else {
                          if (_memberOrder.isNotEmpty) {
                            _selectedMemberIds = {_memberOrder.first};
                          }
                        }
                        _syncExactAmountControllers();
                        _recalculateSplits();
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: CupertinoSearchTextField(
            placeholder: 'Find friends...',
            onChanged: (value) {
              sheetSetState(() {});
              setState(() => _memberSearchQuery = value);
            },
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const itemWidth = 80.0;
            const itemHeight = 135.0;
            const spacing = 12.0;
            const runSpacing = 10.0;

            final double availableWidth = constraints.maxWidth - 32.0;
            int columns = (availableWidth + spacing) ~/ (itemWidth + spacing);
            if (columns < 1) columns = 1;

            final int rows = (visibleEntries.length / columns).ceil();
            final double totalHeight =
                rows * itemHeight + (rows > 0 ? (rows - 1) * runSpacing : 0);

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: SizedBox(
                height: totalHeight,
                child: Stack(
                  children: visibleEntries.asMap().entries.map((listEntry) {
                    final int visualIndex = listEntry.key;
                    final MapEntry<int, String> realEntry = listEntry.value;
                    final int realIndex = realEntry.key;
                    final String id = realEntry.value;

                    final member = currentGroup.members!.firstWhere(
                      (m) => m.id == id,
                    );
                    final isSelected = _selectedMemberIds.contains(id);
                    // final isPayer = id == _paidByUserId; // Unused
                    // Actually, realIndex == 0 logic for Payer relied on _memberOrder sorted.
                    // Yes, _memberOrder[0] is payer. so realIndex == 0.
                    final isFirstInOrder = realIndex == 0;

                    final int row = visualIndex ~/ columns;
                    final int col = visualIndex % columns;

                    final double left = col * (itemWidth + spacing);
                    final double top = row * (itemHeight + runSpacing);

                    return AnimatedPositioned(
                      key: ValueKey(id),
                      left: left,
                      top: top,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOutCubic,
                      child: SizedBox(
                        width: itemWidth,
                        height: itemHeight,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              children: [
                                GestureDetector(
                                  onLongPress: () {
                                    sheetSetState(() {});
                                    setState(() {
                                      final String movedId = _memberOrder
                                          .removeAt(realIndex);
                                      _memberOrder.insert(0, movedId);
                                      _paidByUserId = _memberOrder.first;
                                      _recalculateSplits();
                                    });
                                  },
                                  onTap: () {
                                    sheetSetState(() {});
                                    setState(() {
                                      if (isSelected) {
                                        if (_selectedMemberIds.length > 1) {
                                          _selectedMemberIds.remove(id);
                                          if (id != _memberOrder.first) {
                                            _memberOrder.remove(id);
                                            _memberOrder.add(id);
                                          }
                                        }
                                      } else {
                                        _selectedMemberIds.add(id);
                                        _syncExactAmountControllers();
                                      }
                                      _recalculateSplits();
                                    });
                                  },
                                  child: AnimatedScale(
                                    scale: isSelected ? 1.0 : 0.95,
                                    duration: const Duration(milliseconds: 200),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? CupertinoColors.activeBlue
                                            : CupertinoColors.systemGrey5,
                                        shape: BoxShape.circle,
                                        border: isFirstInOrder
                                            ? Border.all(
                                                color: CupertinoColors
                                                    .systemOrange,
                                                width: 3,
                                              )
                                            : (isSelected
                                                  ? Border.all(
                                                      color: CupertinoColors
                                                          .activeBlue,
                                                      width: 2,
                                                    )
                                                  : Border.all(
                                                      color: CupertinoColors
                                                          .transparent,
                                                      width: 0,
                                                    )),
                                      ),
                                      child: Center(
                                        child: Text(
                                          member.name.isNotEmpty
                                              ? member.name[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            color: isSelected
                                                ? CupertinoColors.white
                                                : CupertinoColors
                                                      .secondaryLabel,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (isFirstInOrder)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: CupertinoColors.systemOrange,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Text(
                                        '₹',
                                        style: TextStyle(
                                          color: CupertinoColors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 30,
                              child: Center(
                                child: Text(
                                  isFirstInOrder
                                      ? 'Paid by ${member.name}'
                                      : member.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isFirstInOrder || isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isFirstInOrder
                                        ? CupertinoColors.systemOrange
                                        : (isSelected
                                              ? CupertinoColors.label
                                              : CupertinoColors.secondaryLabel),
                                  ),
                                ),
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 24,
                                child: CupertinoTextField(
                                  controller: _exactAmountControllers[id],
                                  placeholder: '0.00',
                                  readOnly: _splitType == 'Equally',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  textAlign: TextAlign.center,
                                  padding: EdgeInsets.zero,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _splitType == 'Equally'
                                        ? CupertinoColors.secondaryLabel
                                        : CupertinoColors.label,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _splitType == 'Equally'
                                        ? CupertinoColors.systemGrey5
                                        : CupertinoColors.systemGrey6,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  onChanged: (_) {
                                    // Trigger parent update for validation/display, and sheet update?
                                    // Recalculate splits handled elsewhere?
                                    // Usually validation happens on Save.
                                    // If 'Exact', user types here.
                                    // We should call recalculateSplits if we want to validate sum?
                                    // _recalculateSplits handles 'Exact' sum check only on Save?
                                    // No, lines 316 checks on Save.
                                    // But lines 163-187 in _recalculateSplits handles Exact logic distribution? No, that IS the logic.
                                    // But for Exact, user enters value manually. We don't need to recalculate distribution.
                                    // But we should update state.
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  IconData _getGroupIcon(String? icon) {
    final String iconName = (icon ?? '').toString();
    switch (iconName) {
      case 'home':
        return CupertinoIcons.house_fill;
      case 'trip':
        return CupertinoIcons.airplane;
      case 'coffee':
        return CupertinoIcons.cart_fill;
      default:
        return CupertinoIcons.person_3_fill;
    }
  }

  Color _getGroupIconColor(String? icon) {
    final String iconName = (icon ?? '').toString();
    switch (iconName) {
      case 'home':
        return CupertinoColors.systemGreen;
      case 'trip':
        return CupertinoColors.systemBlue;
      case 'coffee':
        return CupertinoColors.systemBrown;
      default:
        return CupertinoColors.systemOrange;
    }
  }
}
