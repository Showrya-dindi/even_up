import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/group.dart';
import 'package:even_up_app/core/models/group_member.dart';
import 'package:even_up_app/core/active_state.dart';
import 'package:flutter/material.dart'
    show showModalBottomSheet, RoundedRectangleBorder, Radius;

import 'package:even_up_app/core/models/expense.dart';

class AddExpenseScreen extends StatefulWidget {
  final String? groupId;
  final CupertinoTabController? tabController;
  final Expense? expense;
  const AddExpenseScreen({super.key, this.groupId, this.tabController, this.expense});

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

  Set<String> _selectedMemberIds = {};
  final Map<String, TextEditingController> _exactAmountControllers = {};

  String _paidByUserId = 'local-user-123';
  bool _isRecalculating = false;
  List<String> _memberOrder = [];
  String? _selectedCurrencyVal;
  String get _selectedCurrency => _selectedCurrencyVal ?? '₹';

  @override
  void initState() {
    super.initState();
    _paidByUserId = widget.expense?.paidBy ?? 'local-user-123';
    _availableGroups = [];
    _selectedGroupId = widget.expense?.groupId ?? widget.groupId ?? activeGroupState.currentGroupId;
    _groupScrollController = ScrollController();
    
    if (widget.expense != null) {
      _descriptionController.text = widget.expense!.description;
      _amountController.text = widget.expense!.amount.toStringAsFixed(2);
      _splitType = widget.expense!.splitType;
      
      // Initialize split amounts if they exist
      for (var split in widget.expense!.splitWith) {
        final id = split['userId']?.toString();
        if (id != null) {
          final amt = (split['amount'] as num?)?.toDouble() ?? 0.0;
          _exactAmountControllers[id] = TextEditingController(text: amt.toStringAsFixed(2))
            ..addListener(_recalculateSplits);
        }
      }
      _selectedMemberIds = widget.expense!.splitWith
          .map((s) => s['userId']?.toString())
          .whereType<String>()
          .toSet();
    }

    // Listen for changes in active group (e.g. when switching tabs)
    activeGroupState.addListener(_onActiveGroupChanged);

    // Always fetch groups to populate the list
    _fetchGroups();

    _amountController.addListener(_recalculateSplits);
    widget.tabController?.addListener(_onTabChanged);

    // Initial reset to ensure clean state - ONLY if not editing
    if (widget.expense == null) {
      _resetState();
    }
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
        final List<String> newIds = (group.members!.toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())))
          .map((m) => m.id).toList();

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
             // Only reset payer to first if the old payer is NOT in this new group at all
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
          'The sum of split amounts ($_selectedCurrency${currentSum.toStringAsFixed(2)}) must equal the total amount ($_selectedCurrency${totalAmount.toStringAsFixed(2)})',
        );
      }

      final expenseData = {
        if (widget.expense != null) 'id': widget.expense!.id,
        'description': _descriptionController.text,
        'amount': totalAmount,
        'groupId': targetGroupId,
        'paidBy': _paidByUserId,
        'splitType': _splitType,
        'splitWith': splitWithData,
        if (widget.expense != null) 'createdAt': widget.expense!.createdAt.toIso8601String(),
      };

      debugPrint('AddExpenseScreen: Saving expense with data: $expenseData');

      final url = Uri.parse('${AppConfig.baseUrl}/expenses');
      final response = await (widget.expense == null
          ? http.post(url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(expenseData))
          : http.put(url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(expenseData)));

      debugPrint('AddExpenseScreen: Save response status: ${response.statusCode}');
      if (response.statusCode == 201 || response.statusCode == 200) {
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

  String _getEmojiForDescription(String description) {
    final lower = description.toLowerCase();
    if (lower.contains('coffee') || lower.contains('cafe') || lower.contains('tea')) return '☕️';
    if (lower.contains('food') || lower.contains('lunch') || lower.contains('dinner') || lower.contains('breakfast') || lower.contains('meal') || lower.contains('pizza') || lower.contains('burger') || lower.contains('restaurant')) return '🍔';
    if (lower.contains('grocery') || lower.contains('groceries') || lower.contains('market') || lower.contains('supermarket')) return '🛒';
    if (lower.contains('movie') || lower.contains('cinema') || lower.contains('ticket') || lower.contains('show')) return '🍿';
    if (lower.contains('flight') || lower.contains('airport') || lower.contains('plane')) return '✈️';
    if (lower.contains('taxi') || lower.contains('uber') || lower.contains('lyft') || lower.contains('cab')) return '🚕';
    if (lower.contains('hotel') || lower.contains('airbnb') || lower.contains('stay')) return '🏨';
    if (lower.contains('gas') || lower.contains('petrol') || lower.contains('fuel')) return '⛽️';
    if (lower.contains('drink') || lower.contains('bar') || lower.contains('beer') || lower.contains('alcohol') || lower.contains('pub') || lower.contains('wine')) return '🍻';
    if (lower.contains('party') || lower.contains('club') || lower.contains('fun')) return '🎉';
    if (lower.contains('rent') || lower.contains('house') || lower.contains('apartment')) return '🏠';
    if (lower.contains('utility') || lower.contains('bill') || lower.contains('electricity') || lower.contains('water') || lower.contains('internet')) return '💡';
    if (lower.contains('game') || lower.contains('sport') || lower.contains('play')) return '🎮';
    if (lower.contains('gift') || lower.contains('present') || lower.contains('birthday')) return '🎁';
    if (lower.contains('med') || lower.contains('doctor') || lower.contains('pharmacy') || lower.contains('health')) return '💊';
    if (lower.contains('trip') || lower.contains('travel') || lower.contains('vacation') || lower.contains('bus') || lower.contains('train')) return '🚌';
    return '📝';
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: _availableGroups.isEmpty && _isFetchingGroups
            ? const CupertinoActivityIndicator()
            : _buildGroupSelector(),
        trailing: _isLoading
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _saveExpense,
                child: const Text('Save'),
              ),
      ),
      child: SafeArea(
        child: Column(
          children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 24.0,
                  horizontal: 16.0,
                ),
                child: Column(
                  children: [
                    Center(
                      child: AnimatedBuilder(
                        animation: _amountController,
                        builder: (context, child) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _showCurrencySelector,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 4.0),
                                  child: Text(
                                    _selectedCurrency,
                                    style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w500,
                                      color: _amountController.text.isEmpty
                                          ? CupertinoColors.systemGrey3
                                          : CupertinoColors.label,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IntrinsicWidth(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Opacity(
                                      opacity: 0.0,
                                      child: Container(
                                        constraints: const BoxConstraints(minWidth: 40),
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Text(
                                          _amountController.text.isEmpty
                                              ? '0'
                                              : _amountController.text,
                                          style: const TextStyle(
                                            fontSize: 64,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: -2,
                                            color: CupertinoColors.label,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: CupertinoTextField(
                                        padding: EdgeInsets.zero,
                                        controller: _amountController,
                                        placeholder: '0',
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                          TextInputFormatter.withFunction((oldValue, newValue) {
                                            if (newValue.text.isEmpty) return newValue;
                                            final value = double.tryParse(newValue.text);
                                            if (value == null) return oldValue;
                                            if (value > 10000000000) return oldValue;
                                            return newValue;
                                          }),
                                        ],
                                        style: const TextStyle(
                                          fontSize: 64,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -2,
                                          color: CupertinoColors.label,
                                        ),
                                        placeholderStyle: const TextStyle(
                                          fontSize: 64,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -2,
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
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: CupertinoTextField(
                        controller: _descriptionController,
                        placeholder: 'What is this for?',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.label,
                        ),
                        placeholderStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.secondaryLabel,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey6.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        prefix: AnimatedBuilder(
                          animation: _descriptionController,
                          builder: (context, child) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 12.0, right: 8.0),
                                  child: Text(
                                    _getEmojiForDescription(_descriptionController.text),
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),
                                Container(
                                  height: 16,
                                  width: 1,
                                  color: CupertinoColors.systemGrey4,
                                ),
                              ],
                            );
                          },
                        ),
                        suffix: const SizedBox(width: 39),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              _buildSplitSummary(),
            ],
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
      padding: const EdgeInsets.only(top: 12.0),
      child: GestureDetector(
        onTap: widget.groupId == null ? () => _showGroupSelectionModal() : null,
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(16),
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
                if (widget.groupId == null) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    CupertinoIcons.chevron_down,
                    size: 14,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ],
              ],
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

  void _showCurrencySelector() {
    final currencies = ['₹', '\$', '€', '£', '¥'];
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Select Currency'),
        actions: currencies.map((c) {
          return CupertinoActionSheetAction(
            onPressed: () {
              setState(() {
                _selectedCurrencyVal = c;
              });
              Navigator.pop(context);
            },
            child: Text(c, style: const TextStyle(fontSize: 20)),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
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

    final visibleIds = _memberOrder.toList();
    // Sort: Payer first, then others by original order
    visibleIds.sort((a, b) {
      if (a == _paidByUserId) return -1;
      if (b == _paidByUserId) return 1;

      final bool aSelected = _selectedMemberIds.contains(a);
      final bool bSelected = _selectedMemberIds.contains(b);

      if (aSelected && !bSelected) return -1;
      if (!aSelected && bSelected) return 1;

      final memberA = currentGroup.members?.firstWhere(
        (m) => m.id == a,
        orElse: () => GroupMember(id: a, name: 'Unknown', joinedAt: DateTime.now()),
      );
      final memberB = currentGroup.members?.firstWhere(
        (m) => m.id == b,
        orElse: () => GroupMember(id: b, name: 'Unknown', joinedAt: DateTime.now()),
      );

      return (memberA?.name.toLowerCase() ?? '').compareTo(memberB?.name.toLowerCase() ?? '');
    });

    return Expanded(
      child: Padding(
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
              if (_splitType != 'Exact')
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  child: Text(
                    _selectedMemberIds.length == visibleIds.length 
                        ? 'Deselect All' 
                        : 'Select All',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.activeBlue,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    if (_selectedMemberIds.length == visibleIds.length) {
                      _selectedMemberIds = {_paidByUserId};
                    } else {
                      _selectedMemberIds = visibleIds.toSet();
                    }
                    _syncExactAmountControllers();
                    _recalculateSplits();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _splitType,
              children: const {
                'Equally': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Equally', style: TextStyle(fontSize: 13)),
                ),
                'Exact': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Exact Amount', style: TextStyle(fontSize: 13)),
                ),
              },
              onValueChanged: (value) {
                if (value != null) {
                  setState(() {
                    final bool isSwitchingToExact = value == 'Exact' && _splitType != 'Exact';
                    _splitType = value; // Update type FIRST before clearing controllers
                    
                    if (isSwitchingToExact) {
                      _selectedMemberIds = _memberOrder.toSet();
                      _syncExactAmountControllers();
                      for (var controller in _exactAmountControllers.values) {
                        controller.clear();
                      }
                    }
                    _recalculateSplits();
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          if (_splitType == 'Exact') ...[
            Builder(
              builder: (context) {
                final double totalAmount = double.tryParse(_amountController.text) ?? 0.0;
                double exactSum = 0;
                for (final id in _selectedMemberIds) {
                  final val = double.tryParse(_exactAmountControllers[id]?.text ?? '') ?? 0.0;
                  exactSum += val;
                }
                final double amountLeft = totalAmount - exactSum;
                final bool isPerfect = amountLeft.abs() < 0.01;
                
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_selectedCurrency${exactSum.toStringAsFixed(2)} of $_selectedCurrency${totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isPerfect 
                            ? CupertinoColors.systemGreen.withOpacity(0.15) 
                            : CupertinoColors.systemRed.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        isPerfect 
                            ? 'Fully split' 
                            : (amountLeft > 0 
                                ? '$_selectedCurrency${amountLeft.toStringAsFixed(2)} left' 
                                : 'Over by $_selectedCurrency${amountLeft.abs().toStringAsFixed(2)}'),
                        style: TextStyle(
                          color: isPerfect ? CupertinoColors.systemGreen : CupertinoColors.systemRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
          ] else ...[
            const SizedBox(height: 12),
          ],
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24.0, top: 4.0),
              child: Container(
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
            child: SizedBox(
              height: visibleIds.length * 64.0,
              child: Stack(
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

                return AnimatedPositioned(
                  key: ValueKey(id),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  top: index * 64.0,
                  left: 0,
                  right: 0,
                  height: 64.0,
                  child: Column(
                    children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () {
                        setState(() {
                          _paidByUserId = id;
                          _selectedMemberIds.add(id);
                          _recalculateSplits();
                        });
                      },
                      onTap: () {
                        setState(() {
                          if (_splitType == 'Exact') return;
                          
                          if (_selectedMemberIds.contains(id)) {
                            if (_selectedMemberIds.length > 1) {
                              _selectedMemberIds.remove(id);
                            }
                          } else {
                            _selectedMemberIds.add(id);
                          }
                          _recalculateSplits();
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: Opacity(
                          opacity: _splitType == 'Exact' || _selectedMemberIds.contains(id) ? 1.0 : 0.4,
                          child: Row(
                            children: [
                              if (_splitType != 'Exact') ...[
                                Icon(
                                  _selectedMemberIds.contains(id)
                                      ? CupertinoIcons.check_mark_circled_solid
                                      : CupertinoIcons.circle,
                                  color: _selectedMemberIds.contains(id)
                                      ? CupertinoColors.activeBlue
                                      : CupertinoColors.systemGrey3,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                              ],
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                          _splitType == 'Exact' && _selectedMemberIds.contains(id)
                              ? SizedBox(
                                  width: 90,
                                  height: 32,
                                  child: CupertinoTextField(
                                    controller: _exactAmountControllers[id],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.right,
                                    padding: const EdgeInsets.only(right: 8.0, top: 6, bottom: 6),
                                    prefix: Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: Text(
                                        _selectedCurrency,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: CupertinoColors.secondaryLabel,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: CupertinoColors.label,
                                    ),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemBackground,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: CupertinoColors.systemGrey4),
                                    ),
                                    onChanged: (value) {
                                      setState(() {});
                                    },
                                  ),
                                )
                              : Text(
                                  '$_selectedCurrency$share',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: CupertinoColors.label,
                                  ),
                                ),
                        ],
                      ),
                     ),
                    ),
                    ),
                  ],
                ),
               );
              }).toList(),
            ),
          ),
          ),
              ),
          ),
        ],
      ),
      ),
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
        return CupertinoIcons.person_2_fill;
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
