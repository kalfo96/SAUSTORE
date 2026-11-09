import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/section_card.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authService,
    required this.childBuilder,
    this.onSessionReady,
    this.onSessionClosed,
  });

  final AuthService authService;
  final Widget Function(VoidCallback onSignOut) childBuilder;
  final Future<void> Function()? onSessionReady;
  final Future<void> Function()? onSessionClosed;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _hasAccount;
  bool _signedIn = false;
  bool _openingSession = false;
  bool _closingSession = false;
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    widget.authService.apiClient?.addListener(_sessionChanged);
    _loadAccount();
  }

  @override
  void dispose() {
    widget.authService.apiClient?.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted ||
        _closingSession ||
        widget.authService.apiClient?.isAuthenticated != false) {
      return;
    }
    if (_signedIn || _openingSession) {
      setState(() {
        _signedIn = false;
        _openingSession = false;
        _sessionError = null;
      });
      widget.onSessionClosed?.call();
    }
  }

  Future<void> _loadAccount() async {
    final hasAccount = await widget.authService.hasAccount;
    if (mounted) setState(() => _hasAccount = hasAccount);
  }

  Future<void> _enterSession() async {
    setState(() {
      _openingSession = true;
      _sessionError = null;
    });
    try {
      await widget.onSessionReady?.call();
      if (!mounted) return;
      if (widget.authService.isRemote &&
          widget.authService.apiClient?.isAuthenticated != true) {
        setState(() => _openingSession = false);
        return;
      }
      setState(() {
        _signedIn = true;
        _openingSession = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _openingSession = false;
        _sessionError =
            widget.authService.isRemote &&
                widget.authService.apiClient?.isAuthenticated != true
            ? null
            : 'The live inventory could not be opened. Check your connection and try again.';
      });
    }
  }

  Future<void> _leaveSession() async {
    _closingSession = true;
    try {
      await widget.authService.signOut();
      await widget.onSessionClosed?.call();
    } finally {
      _closingSession = false;
      if (mounted) {
        setState(() {
          _signedIn = false;
          _sessionError = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasAccount == null || _openingSession) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Opening your workspace…'),
            ],
          ),
        ),
      );
    }
    if (_sessionError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(_sessionError!, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _enterSession,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry connection'),
                  ),
                  TextButton(
                    onPressed: _leaveSession,
                    child: const Text('Back to login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_signedIn) {
      return widget.childBuilder(() {
        _leaveSession();
      });
    }
    return AuthScreen(
      authService: widget.authService,
      initialMode: _hasAccount! ? AuthMode.login : AuthMode.register,
      onAuthenticated: () {
        _enterSession();
      },
      onAccountCreated: () {
        setState(() => _hasAccount = true);
        _enterSession();
      },
    );
  }
}

/// A brand welcome panel, with a code-native stock journey illustration.
class _AuthWelcome extends StatelessWidget {
  const _AuthWelcome({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const mint = Color(0xFFACE6D4);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 24 : 32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF142B35), Color(0xFF15433F)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(painter: _CoastalLinesPainter()),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 20 : 38),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: compact ? 50 : 62,
                      height: compact ? 48 : 60,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FBF7),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Image.asset(
                        'assets/sau_inn_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DreamStore',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontSize: compact ? 23 : 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Sau Inn Beach Hotel',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFB9D5D2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (compact) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Good stock. Smooth service.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: mint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 70),
                  Text(
                    'BEHIND EVERY GREAT STAY',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: mint,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'A calmer way\nto run your\nstockroom.',
                    style: theme.textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontSize: 46,
                      height: 1.12,
                      letterSpacing: -1.7,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Know what arrived, where it belongs, and what your teams used. More clarity for every department.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFC2DAD6),
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 66),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.055),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.13),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          child: _JourneyStep(
                            icon: Icons.move_to_inbox_outlined,
                            label: 'Received',
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF5F8D86),
                          size: 17,
                        ),
                        Expanded(
                          child: _JourneyStep(
                            icon: Icons.grid_view_rounded,
                            label: 'Assigned',
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF5F8D86),
                          size: 17,
                        ),
                        Expanded(
                          child: _JourneyStep(
                            icon: Icons.restaurant_rounded,
                            label: 'Used',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Made for the rhythm of hotel life.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFABC8C3),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyStep extends StatelessWidget {
  const _JourneyStep({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFACE6D4), size: 25),
        const SizedBox(height: 12),
        Text(
          label,
          maxLines: 1,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}

class _CoastalLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8AD9CB).withValues(alpha: 0.075)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 7; i++) {
      final inset = i * 20.0;
      canvas.drawOval(
        Rect.fromLTWH(
          size.width * 0.3 + inset,
          size.height * 0.39 + inset,
          size.width * 1.15,
          size.height * 0.94,
        ),
        paint,
      );
    }
    canvas.drawCircle(
      Offset(size.width * 0.95, size.height * 0.12),
      size.width * 0.19,
      Paint()..color = const Color(0xFF8AD9CB).withValues(alpha: 0.045),
    );
  }

  @override
  bool shouldRepaint(covariant _CoastalLinesPainter oldDelegate) => false;
}

enum AuthMode { login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.authService,
    required this.initialMode,
    required this.onAuthenticated,
    required this.onAccountCreated,
  });

  final AuthService authService;
  final AuthMode initialMode;
  final VoidCallback onAuthenticated;
  final VoidCallback onAccountCreated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  late AuthMode _mode;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _busy = false;
  String? _error;

  bool get _isRegistering => _mode == AuthMode.register;

  @override
  void initState() {
    super.initState();
    _mode = widget.authService.isRemote ? AuthMode.login : widget.initialMode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isRegistering) {
        await widget.authService.register(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
        widget.onAccountCreated();
      } else {
        final valid = await widget.authService.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (!valid) {
          throw const AuthException('Email or password is incorrect.');
        }
        widget.onAuthenticated();
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode(AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _formKey.currentState?.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 940;
            final pageInset = constraints.maxWidth < 600 ? 16.0 : 32.0;
            return SingleChildScrollView(
              padding: EdgeInsets.all(pageInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - pageInset * 2).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 1120 : 460),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                flex: 11,
                                child: _AuthWelcome(compact: false),
                              ),
                              const SizedBox(width: 48),
                              Expanded(
                                flex: 10,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 24),
                                  child: _buildForm(context),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _AuthWelcome(compact: true),
                              const SizedBox(height: 24),
                              _buildForm(context),
                            ],
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SectionCard(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 20 : 28),
      child: AnimatedSize(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'YOUR HOTEL WORKSPACE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isRegistering ? 'Create your account' : 'Welcome back',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _isRegistering
                    ? 'Create access for this browser or device.'
                    : 'Sign in to manage hotel stock and usage reports.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              if (!widget.authService.isRemote)
                SegmentedButton<AuthMode>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    side: WidgetStatePropertyAll(
                      BorderSide(color: scheme.outlineVariant),
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.medium),
                      ),
                    ),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: AuthMode.login,
                      label: Text('Log in'),
                      icon: Icon(Icons.login),
                    ),
                    ButtonSegment(
                      value: AuthMode.register,
                      label: Text('Register'),
                      icon: Icon(Icons.person_add_alt_1),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (selection) => _switchMode(selection.first),
                ),
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (_isRegistering) ...[
                      TextFormField(
                        controller: _nameController,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().length < 2
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _emailController,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) =>
                          value == null || !value.contains('@')
                          ? 'Enter a valid email address'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      autofillHints: [
                        _isRegistering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: _isRegistering
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: _isRegistering || _busy
                          ? null
                          : (_) => _submit(),
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.length < 6
                          ? 'Use at least 6 characters'
                          : null,
                    ),
                    if (_isRegistering) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmController,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: _busy ? null : (_) => _submit(),
                        obscureText: _obscureConfirmation,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: const Icon(Icons.verified_user_outlined),
                          suffixIcon: IconButton(
                            tooltip: _obscureConfirmation
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () =>
                                  _obscureConfirmation = !_obscureConfirmation,
                            ),
                            icon: Icon(
                              _obscureConfirmation
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value != _passwordController.text
                            ? 'Passwords do not match'
                            : null,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(AppRadii.small),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: scheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _isRegistering
                                    ? Icons.arrow_forward
                                    : Icons.login,
                              ),
                        label: Text(
                          _busy
                              ? 'Please wait...'
                              : _isRegistering
                              ? 'Create account'
                              : 'Log in',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isRegistering)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : _showForgotEmail,
                        child: const Text('Forgot email?'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _showForgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.devices_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.authService.isRemote
                            ? 'Connected to your hotel’s live database. Stock is shared across signed-in devices. Internet is required.'
                            : 'Account and stock are saved only in this browser or device. This is not a shared cloud login.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showForgotEmail() async {
    if (widget.authService.isRemote) {
      await _showLiveAccessHelp();
      return;
    }
    final email = await widget.authService.recoverEmail();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.email_outlined),
        title: const Text('Your account email'),
        content: Text(
          email == null
              ? 'No local account was found on this device.'
              : 'This device account uses:\n\n$email',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLiveAccessHelp() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.admin_panel_settings_outlined),
      title: const Text('Live account access'),
      content: const Text(
        'Your hotel administrator manages live accounts. Contact them to confirm your email or reset your password. Name and email alone cannot reset a live password.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  Future<void> _showForgotPassword() async {
    if (widget.authService.isRemote) {
      await _showLiveAccessHelp();
      return;
    }
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final messenger = ScaffoldMessenger.of(context);
    var obscurePassword = true;
    var obscureConfirmation = true;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          icon: const Icon(Icons.lock_reset_outlined),
          title: const Text('Reset password'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter the name and email used on this device.'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                    ),
                    validator: (value) => value == null || !value.contains('@')
                        ? 'Enter a valid email'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      suffixIcon: IconButton(
                        tooltip: obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword,
                        ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.length < 6
                        ? 'Use at least 6 characters'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmController,
                    obscureText: obscureConfirmation,
                    decoration: InputDecoration(
                      labelText: 'Confirm new password',
                      suffixIcon: IconButton(
                        tooltip: obscureConfirmation
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setDialogState(
                          () => obscureConfirmation = !obscureConfirmation,
                        ),
                        icon: Icon(
                          obscureConfirmation
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value != passwordController.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  await widget.authService.resetPassword(
                    name: nameController.text,
                    email: emailController.text,
                    newPassword: passwordController.text,
                  );
                  if (!dialogContext.mounted) return;
                  messenger.hideCurrentSnackBar();
                  Navigator.pop(dialogContext);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Password updated. You can now log in.'),
                    ),
                  );
                } on AuthException catch (authError) {
                  setDialogState(() => error = authError.message);
                }
              },
              child: const Text('Update password'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
  }
}
