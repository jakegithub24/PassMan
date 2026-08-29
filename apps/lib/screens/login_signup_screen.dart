import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

enum AuthMode { login, signup }

class LoginSignupScreen extends StatefulWidget {
  final Function(String email, String password, {String? salt})? onLogin;
  final Function(String email, String password, {String? salt})? onSignup;

  const LoginSignupScreen({
    super.key,
    this.onLogin,
    this.onSignup,
  });

  @override
  State<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

class _LoginSignupScreenState extends State<LoginSignupScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  AuthMode _authMode = AuthMode.login;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode mode) {
    if (_authMode != mode) {
      HapticFeedback.selectionClick();
      setState(() {
        _authMode = mode;
        _formKey.currentState?.reset();
      });
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email address is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Master password is required';
    }
    if (value.length < 8) {
      return 'Master password must be at least 8 characters';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (_authMode == AuthMode.signup) {
      if (value == null || value.isEmpty) {
        return 'Please confirm your master password';
      }
      if (value != _passwordController.text) {
        return 'Master passwords do not match';
      }
    }
    return null;
  }

  void _handleSubmit() {
    HapticFeedback.lightImpact();
    if (_formKey.currentState?.validate() ?? false) {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;

      if (_authMode == AuthMode.login) {
        widget.onLogin?.call(email, password);
      } else {
        widget.onSignup?.call(email, password);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.frameBg,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            // 1. Ambient Background Layer (Cached via RepaintBoundary)
            const Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: AmbientBackgroundPainter(),
                ),
              ),
            ),

            // 2. Responsive Content Canvas
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 900;
                  return Center(
                    child: isDesktop
                        ? _buildDesktopLayout(context, constraints)
                        : _buildMobileLayout(context, constraints),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Fluent Desktop Layout (Adaptive Dual-Pane Card)
  // Matches UI-UX/UI/desktop_login_sign_up.html
  // ---------------------------------------------------------------------------

  Widget _buildDesktopLayout(BuildContext context, BoxConstraints constraints) {
    final cardWidth = math.min(1000.0, math.max(880.0, constraints.maxWidth - 48.0));
    final cardHeight = math.min(720.0, math.max(650.0, constraints.maxHeight - 48.0));

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Container(
          width: cardWidth,
          height: cardHeight,
          decoration: BoxDecoration(
            color: AppColors.contentBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.hairline, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A14161A), // 0 1px 2px rgba(20,22,26,0.04)
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
              BoxShadow(
                color: Color(0x1414161A), // 0 20px 40px rgba(20,22,26,0.08)
                blurRadius: 40,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: Visual Hero Panel (flex: 1.05)
                Expanded(
                  flex: 105,
                  child: _buildDesktopVisualHero(context),
                ),

                // Right: Auth Form Side (flex: 1.0)
                Expanded(
                  flex: 100,
                  child: _buildDesktopFormSide(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopVisualHero(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.visualHeroGradient,
      ),
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [
          // Hardware-accelerated ambient glowing orbs
          Positioned(
            top: -90,
            right: -100,
            width: 340,
            height: 340,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x24FFFFFF), Color(0x00FFFFFF)],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            width: 220,
            height: 220,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),

          // Foreground Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Brand Header (.av-brand)
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0x38FFFFFF),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Image.asset(
                        'assets/logo/PassMan.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'PassMan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),

                // Big Logo Centered (.av-logo-big)
                Expanded(
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 44,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/logo/PassMan.png',
                        width: 124,
                        height: 124,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),

                // Bottom Content: Feature Card + Headline + Subtitle
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Unified Feature Card (.av-card)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.cardHeroBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.cardHeroBorder, width: 1),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: AppColors.cardHeroIconBg,
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: const Icon(Icons.lock_outline, size: 14, color: Colors.white),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'End-to-end encrypted',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(height: 1),
                                        Text(
                                          'Only you hold the key',
                                          style: TextStyle(
                                            color: Color(0xBFFFFFFF),
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: AppColors.cardHeroIconBg,
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: const Icon(Icons.sync, size: 14, color: Colors.white),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Synced everywhere',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(height: 1),
                                        Text(
                                          'Desktop, mobile, browser',
                                          style: TextStyle(
                                            color: Color(0xBFFFFFFF),
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Hero Headline (h2)
                    const Text(
                      'Every password,\none vault, zero worry.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        letterSpacing: -0.3,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Hero Subtitle (p)
                    const Text(
                      'Sign in to pick up your vault right where you left it, on any device.',
                      style: TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12.5,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopFormSide(BuildContext context) {
    return Container(
      color: AppColors.contentBg,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AppGlassCard(
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            backgroundColor: AppColors.glassWhite,
            borderColor: AppColors.glassBorderStrong,
            blurSigma: 20,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1414161A), // 0 24px 48px rgba(20,22,26,0.10)
                blurRadius: 40,
                offset: Offset(0, 20),
              ),
            ],
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: _buildAuthForm(context, isCompact: false),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile / Compact Android Layout (Fixed & Non-scrollable viewport)
  // Matches UI-UX/UI/mobile_login_sign_up.html
  // ---------------------------------------------------------------------------

  Widget _buildMobileLayout(BuildContext context, BoxConstraints constraints) {
    final maxWidth = math.min(364.0, constraints.maxWidth - 32.0);

    return Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mobile Brand Header (.m-auth-brand-row)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x380C447C), // rgba(12,68,124,0.22)
                          blurRadius: 14,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.asset(
                        'assets/logo/PassMan.png',
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  const Text(
                    'PassMan',
                    style: TextStyle(
                      fontSize: 19.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Mobile Glass Container (.auth-card)
              AppGlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                backgroundColor: AppColors.glassWhite,
                borderColor: AppColors.glassBorderStrong,
                blurSigma: 20,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1414161A),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
                child: _buildAuthForm(context, isCompact: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Core Auth Form Widget (Compact, Non-overflowing & Fluent)
  // ---------------------------------------------------------------------------

  Widget _buildAuthForm(BuildContext context, {required bool isCompact}) {
    final isLogin = _authMode == AuthMode.login;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Segmented Tabs (.auth-tabs)
          Container(
            padding: const EdgeInsets.all(3.5),
            decoration: BoxDecoration(
              color: const Color(0x80FFFFFF), // rgba(255,255,255,0.50)
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0x99FFFFFF)), // rgba(255,255,255,0.60)
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    title: 'Log in',
                    isActive: isLogin,
                    isCompact: isCompact,
                    onTap: () => _switchMode(AuthMode.login),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildTabButton(
                    title: 'Sign up',
                    isActive: !isLogin,
                    isCompact: isCompact,
                    onTap: () => _switchMode(AuthMode.signup),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isCompact ? 14 : 18),

          // 2. Title & Subtitle with Animated Crossfade
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Column(
              key: ValueKey<bool>(isLogin),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLogin ? 'Welcome back' : 'Create your vault',
                  style: TextStyle(
                    fontSize: isCompact ? 18 : 19.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isLogin
                      ? (isCompact
                          ? 'Sign in to access your encrypted vault.'
                          : 'Enter your details to access your vault.')
                      : 'Set up your encrypted vault in under a minute.',
                  style: TextStyle(
                    fontSize: isCompact ? 11.5 : 12,
                    color: AppColors.inkSoft,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isCompact ? 12 : 16),

          // 3. Email Field (.field-group)
          _buildFieldLabel('Email', isCompact: isCompact),
          TextFormField(
            controller: _emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            validator: _validateEmail,
            onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w500),
            decoration: _buildInputDecoration(
              hintText: 'you@example.com',
              prefixIcon: Icons.mail_outline,
              isCompact: isCompact,
            ),
          ),
          SizedBox(height: isCompact ? 10 : 14),

          // 4. Master Password Field (.field-group)
          _buildFieldLabel('Master password', isCompact: isCompact),
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            textInputAction: isLogin ? TextInputAction.done : TextInputAction.next,
            autofillHints: [isLogin ? AutofillHints.password : AutofillHints.newPassword],
            validator: _validatePassword,
            onFieldSubmitted: (_) {
              if (isLogin) {
                _handleSubmit();
              } else {
                _confirmPasswordFocus.requestFocus();
              }
            },
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w500),
            decoration: _buildInputDecoration(
              hintText: '••••••••••••',
              prefixIcon: Icons.lock_outline,
              isCompact: isCompact,
              suffixIcon: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 16,
                    color: AppColors.inkSoft,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
            ),
          ),

          // 5. Confirm Password Field with Smooth Animated Reveal (Sign up only)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            child: !isLogin
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: isCompact ? 10 : 14),
                      _buildFieldLabel('Confirm master password', isCompact: isCompact),
                      TextFormField(
                        controller: _confirmPasswordController,
                        focusNode: _confirmPasswordFocus,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        validator: _validateConfirmPassword,
                        onFieldSubmitted: (_) => _handleSubmit(),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w500),
                        decoration: _buildInputDecoration(
                          hintText: '••••••••••••',
                          prefixIcon: Icons.lock_reset,
                          isCompact: isCompact,
                          suffixIcon: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 16,
                                color: AppColors.inkSoft,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 4),

          // 6. Remember Me & Forgot Password Row (Login mode only)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOutCubic,
            child: isLogin
                ? Padding(
                    padding: EdgeInsets.only(top: 2, bottom: isCompact ? 12 : 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _rememberMe = !_rememberMe);
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: _rememberMe ? AppColors.navy : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: _rememberMe ? AppColors.navy : AppColors.inkSoft,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: _rememberMe
                                        ? const Icon(Icons.check, size: 10, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  const Flexible(
                                    child: Text(
                                      'Remember me',
                                      style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: TextButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Zero-Knowledge notice: Master passwords cannot be reset without your local salt/keys.'),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              isCompact ? 'Forgot?' : 'Forgot password?',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(height: 8),
          ),

          // 7. Primary Submit Button (.auth-submit) with Material Ripple
          _buildSubmitButton(isLogin, isCompact: isCompact),
          SizedBox(height: isCompact ? 12 : 16),

          // 8. Divider (.auth-divider)
          const Row(
            children: [
              Expanded(child: Divider(color: AppColors.dividerHairline, height: 1)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'or continue with',
                  style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                ),
              ),
              Expanded(child: Divider(color: AppColors.dividerHairline, height: 1)),
            ],
          ),
          SizedBox(height: isCompact ? 10 : 14),

          // 9. Social Buttons (.auth-socials)
          Row(
            children: [
              Expanded(
                child: _buildSocialButton(
                  customIcon: const GoogleLogoWidget(size: 14),
                  label: 'Google',
                  isCompact: isCompact,
                  onTap: () => HapticFeedback.lightImpact(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSocialButton(
                  icon: Icons.apple,
                  label: 'Apple',
                  isCompact: isCompact,
                  onTap: () => HapticFeedback.lightImpact(),
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 12 : 16),

          // 10. Footer Switch Link (.auth-footer)
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  isLogin ? "Don't have an account? " : "Already have an account? ",
                  style: TextStyle(fontSize: isCompact ? 11.5 : 12, color: AppColors.inkSoft),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _switchMode(isLogin ? AuthMode.signup : AuthMode.login),
                    child: Text(
                      isLogin ? 'Sign up' : 'Log in',
                      style: TextStyle(
                        fontSize: isCompact ? 11.5 : 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Micro-Interactive Widgets & Buttons
  // ---------------------------------------------------------------------------

  Widget _buildFieldLabel(String label, {required bool isCompact}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isCompact ? 3.5 : 5),
      child: Text(
        label,
        style: TextStyle(
          fontSize: isCompact ? 11.5 : 12,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
    required bool isCompact,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: AppColors.inkSoft, fontSize: isCompact ? 12 : 12.5),
      filled: true,
      fillColor: AppColors.inputBg,
      prefixIcon: Icon(prefixIcon, size: isCompact ? 14 : 15, color: AppColors.inkSoft),
      suffixIcon: suffixIcon,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isCompact ? 9 : 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.inputBorder, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.inputBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required bool isActive,
    required bool isCompact,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutCubic,
          padding: EdgeInsets.symmetric(vertical: isCompact ? 7 : 8),
          decoration: BoxDecoration(
            gradient: isActive ? AppColors.primaryGradient : null,
            color: isActive ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: Color(0x4D0C447C), // rgba(12,68,124,0.30)
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: isCompact ? 12.5 : 13,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(bool isLogin, {required bool isCompact}) {
    return Container(
      width: double.infinity,
      height: isCompact ? 40 : 44,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(11),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D0C447C), // rgba(12,68,124,0.30)
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleSubmit,
          borderRadius: BorderRadius.circular(11),
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          child: Center(
            child: Text(
              isLogin ? 'Log in' : 'Create account',
              style: TextStyle(
                color: Colors.white,
                fontSize: isCompact ? 13 : 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    IconData? icon,
    Widget? customIcon,
    required String label,
    required bool isCompact,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: AppColors.navy.withValues(alpha: 0.1),
        highlightColor: AppColors.navy.withValues(alpha: 0.05),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 8 : 9),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.glassBorderStrong, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (customIcon != null)
                customIcon
              else if (icon != null)
                Icon(icon, size: isCompact ? 15 : 17, color: AppColors.ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: isCompact ? 11.5 : 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Ambient Background Painter (Dual ambient radial gradients)
// -----------------------------------------------------------------------------
class AmbientBackgroundPainter extends CustomPainter {
  const AmbientBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Base frame fill #EEF3F1
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.frameBg,
    );

    // 2. Radial tint 1 (#DBE9F6) at 15% 10%
    final center1 = Offset(size.width * 0.15, size.height * 0.10);
    final radius1 = (size.width * 0.65).clamp(320.0, 750.0);
    final paint1 = Paint()
      ..shader = ui.Gradient.radial(
        center1,
        radius1,
        [AppColors.tint1, AppColors.tint1.withValues(alpha: 0.0)],
        [0.0, 1.0],
      );
    canvas.drawCircle(center1, radius1, paint1);

    // 3. Radial tint 2 (#E4EEFA) at 85% 90%
    final center2 = Offset(size.width * 0.85, size.height * 0.90);
    final radius2 = (size.width * 0.60).clamp(300.0, 700.0);
    final paint2 = Paint()
      ..shader = ui.Gradient.radial(
        center2,
        radius2,
        [AppColors.tint2, AppColors.tint2.withValues(alpha: 0.0)],
        [0.0, 1.0],
      );
    canvas.drawCircle(center2, radius2, paint2);
  }

  @override
  bool shouldRepaint(covariant AmbientBackgroundPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// Official Google 4-Color Vector Logo Painter
// -----------------------------------------------------------------------------
class GoogleLogoWidget extends StatelessWidget {
  final double size;
  const GoogleLogoWidget({super.key, this.size = 15});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: const _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    // Blue Path (#4285F4)
    final bluePath = Path()
      ..moveTo(22.56, 12.25)
      ..cubicTo(22.56, 11.47, 22.49, 10.72, 22.36, 10.0)
      ..lineTo(12.0, 10.0)
      ..lineTo(12.0, 14.26)
      ..lineTo(17.92, 14.26)
      ..cubicTo(17.67, 15.63, 16.89, 16.79, 15.72, 17.58)
      ..lineTo(15.72, 20.35)
      ..lineTo(19.29, 20.35)
      ..cubicTo(21.37, 18.43, 22.56, 15.61, 22.56, 12.25)
      ..close();
    canvas.drawPath(bluePath, Paint()..color = const Color(0xFF4285F4));

    // Green Path (#34A853)
    final greenPath = Path()
      ..moveTo(12.0, 23.0)
      ..cubicTo(14.97, 23.0, 17.46, 22.02, 19.28, 20.34)
      ..lineTo(15.71, 17.57)
      ..cubicTo(14.72, 18.23, 13.45, 18.63, 12.0, 18.63)
      ..cubicTo(9.14, 18.63, 6.71, 16.7, 5.84, 14.1)
      ..lineTo(2.18, 14.1)
      ..lineTo(2.18, 16.95)
      ..cubicTo(4.0, 20.57, 7.7, 23.0, 12.0, 23.0)
      ..close();
    canvas.drawPath(greenPath, Paint()..color = const Color(0xFF34A853));

    // Yellow Path (#FBBC05)
    final yellowPath = Path()
      ..moveTo(5.84, 14.1)
      ..cubicTo(5.62, 13.44, 5.5, 12.73, 5.5, 12.0)
      ..cubicTo(5.5, 11.27, 5.63, 10.56, 5.84, 9.9)
      ..lineTo(5.84, 7.05)
      ..lineTo(2.18, 7.05)
      ..cubicTo(1.43, 8.55, 1.0, 10.23, 1.0, 12.0)
      ..cubicTo(1.0, 13.77, 1.43, 15.45, 2.18, 16.95)
      ..lineTo(5.84, 14.1)
      ..close();
    canvas.drawPath(yellowPath, Paint()..color = const Color(0xFFFBBC05));

    // Red Path (#EA4335)
    final redPath = Path()
      ..moveTo(12.0, 5.38)
      ..cubicTo(13.62, 5.38, 15.06, 5.94, 16.21, 7.02)
      ..lineTo(19.36, 3.87)
      ..cubicTo(17.45, 2.09, 14.97, 1.0, 12.0, 1.0)
      ..cubicTo(7.7, 1.0, 3.99, 3.47, 2.18, 7.05)
      ..lineTo(5.84, 9.9)
      ..cubicTo(6.71, 7.3, 9.14, 5.38, 12.0, 5.38)
      ..close();
    canvas.drawPath(redPath, Paint()..color = const Color(0xFFEA4335));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleLogoPainter oldDelegate) => false;
}
