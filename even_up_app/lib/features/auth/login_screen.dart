import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/user_session.dart';
import 'package:even_up_app/features/home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 0 = Sign In, 1 = Sign Up
  int _selectedSegment = 0;
  bool _isLoading = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController(); // Sign Up only
  final _confirmPasswordController = TextEditingController(); // Sign Up only

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter your email and password.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        UserSession.instance.login(
          token: body['token'],
          userId: body['userId'],
          name: body['name'],
          email: body['email'],
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          CupertinoPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        _showError(body['error'] ?? 'Login failed.');
      }
    } catch (e) {
      _showError('Could not connect to server: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }
    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password, 'name': name}),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 201) {
        // Auto-login after signup
        UserSession.instance.login(
          token: body['token'],
          userId: body['userId'],
          name: body['name'],
          email: body['email'],
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          CupertinoPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        _showError(body['error'] ?? 'Sign up failed.');
      }
    } catch (e) {
      _showError('Could not connect to server: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _selectedSegment == 1;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              // Logo + Title
              const Icon(
                CupertinoIcons.square_split_2x1_fill,
                size: 72,
                color: CupertinoColors.activeBlue,
              ),
              const SizedBox(height: 12),
              const Text(
                'EvenUp',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1.5,
                ),
              ),
              const Text(
                'Split expenses with friends',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
              const SizedBox(height: 40),

              // Segment Control
              CupertinoSlidingSegmentedControl<int>(
                groupValue: _selectedSegment,
                children: const {
                  0: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Sign In'),
                  ),
                  1: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Sign Up'),
                  ),
                },
                onValueChanged: (val) {
                  if (val != null) setState(() => _selectedSegment = val);
                },
              ),
              const SizedBox(height: 32),

              // Form Fields
              CupertinoListSection.insetGrouped(
                margin: EdgeInsets.zero,
                children: [
                  if (isSignUp)
                    CupertinoTextFormFieldRow(
                      controller: _nameController,
                      placeholder: 'Full Name',
                      textCapitalization: TextCapitalization.words,
                      prefix: const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: Icon(CupertinoIcons.person, size: 20, color: CupertinoColors.secondaryLabel),
                      ),
                    ),
                  CupertinoTextFormFieldRow(
                    controller: _emailController,
                    placeholder: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    prefix: const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(CupertinoIcons.mail, size: 20, color: CupertinoColors.secondaryLabel),
                    ),
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _passwordController,
                    placeholder: 'Password',
                    obscureText: true,
                    prefix: const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(CupertinoIcons.lock, size: 20, color: CupertinoColors.secondaryLabel),
                    ),
                  ),
                  if (isSignUp)
                    CupertinoTextFormFieldRow(
                      controller: _confirmPasswordController,
                      placeholder: 'Confirm Password',
                      obscureText: true,
                      prefix: const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: Icon(CupertinoIcons.lock_shield, size: 20, color: CupertinoColors.secondaryLabel),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 24),

              // Submit Button
              _isLoading
                  ? const Center(child: CupertinoActivityIndicator())
                  : CupertinoButton.filled(
                      onPressed: isSignUp ? _handleSignup : _handleLogin,
                      child: Text(isSignUp ? 'Create Account' : 'Sign In'),
                    ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
