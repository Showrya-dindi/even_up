import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:even_up_app/core/models/group.dart';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/user_session.dart';
import 'package:even_up_app/core/active_state.dart';

class GroupInfoScreen extends StatelessWidget {
  final Group group;
  const GroupInfoScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final DateFormat formatter = DateFormat('MMMM d, yyyy');
    
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Group Info'),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 24),
            _buildHeader(),
            const SizedBox(height: 32),
            _buildMetadataSection(formatter),
            const SizedBox(height: 32),
            _buildMembersSection(),
            const SizedBox(height: 32),
            _buildActionsSection(context),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: _getGroupIconColor(group.icon).withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _getGroupIcon(group.icon),
            size: 50,
            color: _getGroupIconColor(group.icon),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          group.name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataSection(DateFormat formatter) {
    return CupertinoListSection.insetGrouped(
      header: const Text('Details'),
      children: [
        CupertinoListTile(
          title: const Text('Created'),
          subtitle: Text(formatter.format(group.createdAt)),
          leading: const Icon(CupertinoIcons.calendar, color: CupertinoColors.systemGrey),
        ),
      ],
    );
  }

  Widget _buildMembersSection() {
    return CupertinoListSection.insetGrouped(
      header: Text('${group.members?.length ?? 0} Members'),
      children: group.members?.map((member) => CupertinoListTile(
        leading: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: CupertinoColors.systemGrey5,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
        title: Text(member.name),
        subtitle: member.id == group.createdBy ? const Text('Group Creator') : null,
      )).toList() ?? [
        const CupertinoListTile(title: Text('No members found'))
      ],
    );
  }

  Widget _buildActionsSection(BuildContext context) {
    final isCreator = group.createdBy == UserSession.instance.userId;

    return CupertinoListSection.insetGrouped(
      children: [
        CupertinoListTile(
          title: const Text('Leave Group', style: TextStyle(color: CupertinoColors.destructiveRed)),
          leading: const Icon(CupertinoIcons.square_arrow_left, color: CupertinoColors.destructiveRed),
          onTap: () {
            _showConfirmationDialog(
              context, 
              'Leave Group', 
              'Are you sure you want to leave this group?',
              () => _leaveGroup(context),
            );
          },
        ),
        if (isCreator)
          CupertinoListTile(
            title: const Text('Delete Group', style: TextStyle(color: CupertinoColors.destructiveRed)),
            leading: const Icon(CupertinoIcons.trash, color: CupertinoColors.destructiveRed),
            onTap: () {
              debugPrint('UI: Tapped delete for ${group.id}');
              _showConfirmationDialog(
                context, 
                'Delete Group', 
                'Are you sure you want to permanently delete this group? This action cannot be undone.',
                () => _deleteGroup(context),
              );
            },
          ),
      ],
    );
  }

  Future<void> _leaveGroup(BuildContext context) async {
    try {
      debugPrint('UI: Sending LEAVE request for group ${group.id}');
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/groups/${group.id}/leave'),
        headers: UserSession.instance.authHeaders,
      );

      debugPrint('UI: LEAVE response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        debugPrint('UI: Leave success, notifying state');
        activeGroupState.notifyGroupsChanged();
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        if (context.mounted) {
          _showError(context, 'Failed to leave group (Status: ${response.statusCode}): ${response.body}');
        }
      }
    } catch (e) {
      debugPrint('UI: Error during LEAVE: $e');
      if (context.mounted) {
        _showError(context, 'Error leaving group: $e');
      }
    }
  }

  Future<void> _deleteGroup(BuildContext context) async {
    try {
      debugPrint('UI: Sending DELETE request for group ${group.id}');
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/groups/${group.id}'),
        headers: UserSession.instance.authHeaders,
      );

      debugPrint('UI: DELETE response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        debugPrint('UI: Delete success, notifying state');
        activeGroupState.notifyGroupsChanged();
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        if (context.mounted) {
          _showError(context, 'Failed to delete group (Status: ${response.statusCode}): ${response.body}');
        }
      }
    } catch (e) {
      debugPrint('UI: Error during DELETE: $e');
      if (context.mounted) {
        _showError(context, 'Error deleting group: $e');
      }
    }
  }

  void _showError(BuildContext context, String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showConfirmationDialog(BuildContext rootContext, String title, String content, VoidCallback onConfirm) {
    showCupertinoDialog(
      context: rootContext,
      builder: (BuildContext dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <CupertinoDialogAction>[
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              // Dismiss dialog from the root navigator
              Navigator.pop(dialogContext);
              onConfirm();
            },
            child: const Text('Confirm'),
          ),
        ],
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
