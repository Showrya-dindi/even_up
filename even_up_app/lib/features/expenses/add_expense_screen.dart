import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, ReorderableListView, Colors;
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/models/group.dart';
import 'package:even_up_app/core/active_state.dart';

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
      orElse: () => _availableGroups.isNotEmpty ? _availableGroups.first : null
    );
    if (currentGroup == null || currentGroup.members == null) return;

    final List<String> currentOrder = _memberOrder;
    if (currentOrder == null) return;

    // Use the actual group member order to determine who is "last" for exact splits
    final List<String> sortedSelectedIds = currentGroup.members!
        .map((m) => m.id)
        .where((id) => currentOrder.contains(id) && _selectedMemberIds.contains(id))
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

        final bool isSame = (currentOrder.length == newIds.length) && 
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
    
    final selectedIndex = _availableGroups.indexWhere((g) => g.id == _selectedGroupId);
    if (selectedIndex > 0) {
      final selectedGroup = _availableGroups.removeAt(selectedIndex);
      _availableGroups.insert(0, selectedGroup);
      
      // Scroll back to start to show the newly moved item
      if (_groupScrollController != null && _groupScrollController!.hasClients) {
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
            _availableGroups = data.map((json) => Group.fromJson(json)).toList();
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
        final val = double.tryParse(_exactAmountControllers[id]?.text ?? '0') ?? 0.0;
        currentSum += val;
        splitWithData.add({
          'userId': id,
          'amount': val,
        });
      }
      
      if (_splitType == 'Exact' && (currentSum - totalAmount).abs() > 0.01) {
        throw Exception('The sum of split amounts (\$${currentSum.toStringAsFixed(2)}) must equal the total amount (\$${totalAmount.toStringAsFixed(2)})');
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
        child: Column(
          children: [
            if (widget.groupId == null)
              _availableGroups.isEmpty && _isFetchingGroups
                ? const SizedBox(height: 100, child: Center(child: CupertinoActivityIndicator()))
                : _buildGroupSelector(),
            CupertinoListSection.insetGrouped(
              header: const Text('Details'),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                CupertinoTextFormFieldRow(
                  controller: _descriptionController,
                  placeholder: 'Description',
                  prefix: const Icon(CupertinoIcons.pencil, size: 20),
                ),
                CupertinoTextFormFieldRow(
                  controller: _amountController,
                  placeholder: '0.00',
                  prefix: const Icon(CupertinoIcons.money_dollar, size: 20),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
            Expanded(
              child: _buildMemberSelector(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 20.0, top: 16.0, bottom: 8.0),
          child: Text(
            'SELECT GROUP',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 8.0),
        SizedBox(
          height: 100, // Increased height for safety
          child: Builder(
            builder: (context) {
              final List<Group> groups = _availableGroups;

              if (groups.isEmpty) {
                return const Center(
                  child: Text('No groups found', style: TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 13)),
                );
              }

              return SingleChildScrollView(
                controller: _groupScrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: groups.length * 88.0, 
                  height: 100,
                  child: Stack(
                    children: groups.asMap().entries.map((entry) {
                      final index = entry.key;
                      final group = entry.value;
                      final isSelected = _selectedGroupId == group.id;

                      return AnimatedPositioned(
                        key: ValueKey(group.id),
                        left: index * 88.0,
                        top: 0,
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOutCubic,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedGroupId = group.id;
                              _reorderGroups();
                              _updateSelectedMembers();
                            });
                          },
                          child: AnimatedScale(
                            scale: isSelected ? 1.05 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutBack,
                            child: SizedBox(
                              width: 80,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: isSelected 
                                        ? _getGroupIconColor(group.icon)
                                        : _getGroupIconColor(group.icon).withOpacity(0.1),
                                      shape: BoxShape.circle,
                                      border: isSelected 
                                        ? Border.all(color: _getGroupIconColor(group.icon), width: 3)
                                        : Border.all(color: CupertinoColors.transparent, width: 0),
                                    ),
                                    child: Icon(
                                      _getGroupIcon(group.icon),
                                      color: isSelected ? CupertinoColors.white : _getGroupIconColor(group.icon),
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 300),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      color: isSelected ? CupertinoColors.label : CupertinoColors.secondaryLabel,
                                    ),
                                    child: Text(
                                      group.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      softWrap: false,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            }
          ),
        ),
      ],
    );
  }

  Widget _buildMemberSelector() {
    final Group? currentGroup = _availableGroups.cast<Group?>().firstWhere(
      (g) => g?.id == _selectedGroupId, 
      orElse: () => _availableGroups.isNotEmpty ? _availableGroups.first : null
    );

    if (currentGroup == null || _memberOrder == null || _memberOrder.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20.0, top: 16.0, bottom: 8.0),
          child: Row(
            children: [
              const Text(
                'SPLIT',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 8),
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
                      setState(() => _splitType = value);
                      _recalculateSplits();
                    }
                  },
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () {
                  setState(() {
                    if (_selectedMemberIds.length == _memberOrder.length) {
                      // Reset to just the payer selected
                      if (_memberOrder.isNotEmpty) {
                        _selectedMemberIds = {_memberOrder.first};
                      }
                    } else {
                      _selectedMemberIds = _memberOrder.toSet();
                    }
                    _syncExactAmountControllers();
                    _recalculateSplits();
                  });
                },
                child: Text(
                  _selectedMemberIds.length == _memberOrder.length ? 'DESELECT ALL' : 'SELECT ALL',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 20),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: CupertinoSearchTextField(
            placeholder: 'Find friends...',
            onChanged: (value) => setState(() => _memberSearchQuery = value),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Wrap(
              spacing: 12,
              runSpacing: 20,
              alignment: WrapAlignment.start,
              children: _memberOrder.asMap().entries.where((entry) {
                final String id = entry.value;
                final member = currentGroup.members!.firstWhere((m) => m.id == id);
                final query = _memberSearchQuery.toLowerCase();
                return query.isEmpty || member.name.toLowerCase().contains(query);
              }).map((entry) {
                final int index = entry.key;
                final String id = entry.value;
                final member = currentGroup.members!.firstWhere((m) => m.id == id);
                final isSelected = _selectedMemberIds.contains(id);
                final isPayer = index == 0;
                
                return SizedBox(
                  width: 80,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          GestureDetector(
                            onLongPress: () {
                              setState(() {
                                final String movedId = _memberOrder.removeAt(index);
                                _memberOrder.insert(0, movedId);
                                _paidByUserId = _memberOrder.first;
                              });
                              _recalculateSplits();
                            },
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  if (_selectedMemberIds.length > 1) {
                                    _selectedMemberIds.remove(id);
                                  }
                                } else {
                                  _selectedMemberIds.add(id);
                                  _syncExactAmountControllers();
                                }
                              });
                              _recalculateSplits();
                            },
                            child: AnimatedScale(
                              scale: isSelected ? 1.0 : 0.95,
                              duration: const Duration(milliseconds: 200),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey5,
                                  shape: BoxShape.circle,
                                  border: isPayer 
                                    ? Border.all(color: CupertinoColors.systemOrange, width: 3)
                                    : (isSelected ? Border.all(color: CupertinoColors.activeBlue, width: 2) : Border.all(color: CupertinoColors.transparent, width: 0)),
                                ),
                                child: Center(
                                  child: Text(
                                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: isSelected ? CupertinoColors.white : CupertinoColors.secondaryLabel,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (isPayer)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: CupertinoColors.systemOrange,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(CupertinoIcons.money_dollar, size: 12, color: CupertinoColors.white),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPayer ? 'Paid by ${member.name}' : member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isPayer || isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isPayer ? CupertinoColors.systemOrange : (isSelected ? CupertinoColors.label : CupertinoColors.secondaryLabel),
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
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            padding: EdgeInsets.zero,
                            style: TextStyle(
                              fontSize: 12,
                              color: _splitType == 'Equally' ? CupertinoColors.secondaryLabel : CupertinoColors.label,
                            ),
                            decoration: BoxDecoration(
                              color: _splitType == 'Equally' ? CupertinoColors.systemGrey5 : CupertinoColors.systemGrey6,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
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
