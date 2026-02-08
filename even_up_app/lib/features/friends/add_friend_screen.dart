import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/friends'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameController.text,
          'email': _emailController.text,
        }),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception('Failed to add friend');
      }
    } catch (e) {
      if (mounted) {
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
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Add Friend'),
        trailing: _isLoading
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _addFriend,
                child: const Text('Done'),
              ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 20.0, top: 16.0, bottom: 8.0),
              child: Text(
                'FRIEND DETAILS',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoTextFormFieldRow(
                  controller: _nameController,
                  placeholder: 'Full Name',
                  prefix: const Icon(CupertinoIcons.person, size: 20),
                ),
                CupertinoTextFormFieldRow(
                  controller: _emailController,
                  placeholder: 'Email Address',
                  prefix: const Icon(CupertinoIcons.mail, size: 20),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Text(
                'Your friend will receive an invitation to join Even Up.',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
