import 'package:flutter/material.dart';

const Color authNavy = Color(0xFF101827);
const Color authPanel = Color(0xFF192436);
const Color authGreen = Color(0xFF39D6A0);
const Color authMuted = Color(0xFF9BAAC0);
const Color authBorder = Color(0xFF334155);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLogin = true;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _isLogin = !_isLogin;
    });

    _formKey.currentState?.reset();
  }

  void _submitForm() {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Authentication will be connected to Spring Boot next.
    // Do not treat this screen as a real login yet.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isLogin
              ? 'Login form validated. Backend connection is next.'
              : 'Registration form validated. Backend connection is next.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: authPanel,
      ),
    );
  }

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';

    if (username.isEmpty) {
      return 'Please enter your username';
    }

    if (username.length < 3) {
      return 'Username must contain at least 3 characters';
    }

    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Please enter your email';
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Please enter a valid email';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return 'Please enter your password';
    }

    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }

    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }

    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }

    return null;
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: authMuted, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF111C2C),
      labelStyle: const TextStyle(color: authMuted),
      errorMaxLines: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: authBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: authBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: authGreen, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFF8793)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFF8793), width: 1.5),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool hidden,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: hidden,
      validator: validator,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      decoration: _decoration(
        label: label,
        icon: Icons.lock_outline_rounded,
        suffixIcon: IconButton(
          tooltip: hidden ? 'Show password' : 'Hide password',
          onPressed: onToggle,
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: authMuted,
            size: 21,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: authNavy,
      body: Stack(
        children: [
          // Subtle decorative background.
          Positioned(
            top: -100,
            right: -110,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF174E47).withValues(alpha: 0.35),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF203D3A).withValues(alpha: 0.30),
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 56,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Brand
                            Center(
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF203D3A),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: const Color(0xFF30675B),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet_rounded,
                                  color: authGreen,
                                  size: 34,
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            const Text(
                              'HisabBook',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 29,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),

                            const SizedBox(height: 7),

                            const Text(
                              'Your money, made clear.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: authMuted, fontSize: 14),
                            ),

                            const SizedBox(height: 30),

                            // Authentication form
                            Container(
                              padding: const EdgeInsets.all(23),
                              decoration: BoxDecoration(
                                color: authPanel,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFF29364B),
                                ),
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _isLogin
                                          ? 'Welcome back'
                                          : 'Create your account',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 23,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    Text(
                                      _isLogin
                                          ? 'Sign in to manage your money.'
                                          : 'Start keeping track of your money.',
                                      style: const TextStyle(
                                        color: authMuted,
                                        fontSize: 13,
                                        height: 1.5,
                                      ),
                                    ),

                                    const SizedBox(height: 25),

                                    TextFormField(
                                      controller: _usernameController,
                                      validator: _validateUsername,
                                      textCapitalization:
                                          TextCapitalization.none,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      textInputAction: TextInputAction.next,
                                      decoration: _decoration(
                                        label: 'Username',
                                        icon: Icons.person_outline_rounded,
                                      ),
                                    ),

                                    if (!_isLogin) ...[
                                      const SizedBox(height: 16),

                                      TextFormField(
                                        controller: _emailController,
                                        validator: _validateEmail,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        autocorrect: false,
                                        textInputAction: TextInputAction.next,
                                        decoration: _decoration(
                                          label: 'Email address',
                                          icon: Icons.email_outlined,
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 16),

                                    _buildPasswordField(
                                      label: 'Password',
                                      controller: _passwordController,
                                      hidden: _hidePassword,
                                      onToggle: () {
                                        setState(() {
                                          _hidePassword = !_hidePassword;
                                        });
                                      },
                                      validator: _validatePassword,
                                    ),

                                    if (_isLogin)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Password recovery will be '
                                                  'added with the backend.',
                                                ),
                                              ),
                                            );
                                          },
                                          child: const Text(
                                            'Forgot password?',
                                            style: TextStyle(
                                              color: authGreen,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      )
                                    else ...[
                                      const SizedBox(height: 16),

                                      _buildPasswordField(
                                        label: 'Confirm password',
                                        controller: _confirmPasswordController,
                                        hidden: _hideConfirmPassword,
                                        onToggle: () {
                                          setState(() {
                                            _hideConfirmPassword =
                                                !_hideConfirmPassword;
                                          });
                                        },
                                        validator: _validateConfirmPassword,
                                      ),
                                    ],

                                    const SizedBox(height: 20),

                                    SizedBox(
                                      height: 52,
                                      child: FilledButton(
                                        onPressed: _submitForm,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: authGreen,
                                          foregroundColor: authNavy,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              _isLogin
                                                  ? Icons.login_rounded
                                                  : Icons
                                                        .person_add_alt_1_rounded,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              _isLogin
                                                  ? 'Login'
                                                  : 'Create Account',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 20),

                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _isLogin
                                                ? "Don't have an account?"
                                                : 'Already have an account?',
                                            style: const TextStyle(
                                              color: authMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _switchMode,
                                          child: Text(
                                            _isLogin ? 'Sign up' : 'Login',
                                            style: const TextStyle(
                                              color: authGreen,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 22),

                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: authMuted,
                                  size: 16,
                                ),
                                SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    'Simple money tracking, one step at a time.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: authMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
