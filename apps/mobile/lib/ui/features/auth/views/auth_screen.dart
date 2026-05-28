import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/app_localizations_context.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/design_system.dart';
import '../view_models/auth_view_model.dart';

const _brandIconAsset = 'assets/images/brand_icon.png';
const _googleContinueButtonAsset =
    'assets/google_brand/android_neutral_rd_ctn@4x.png';
const _heroAssets = [
  'assets/images/login/cropped/auth_hero_01.webp',
  'assets/images/login/cropped/auth_hero_02.webp',
  'assets/images/login/cropped/auth_hero_03.webp',
  'assets/images/login/cropped/auth_hero_04.webp',
  'assets/images/login/cropped/auth_hero_05.webp',
];

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController(text: 'demo@example.com');
  final _passwordController = TextEditingController(text: 'password123');
  final _nameController = TextEditingController(text: 'Test User');
  bool _registerMode = false;
  bool _preloadedAuthAssets = false;
  String? _nameError;
  String? _emailError;
  String? _passwordError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preloadedAuthAssets) return;
    _preloadedAuthAssets = true;
    precacheImage(const AssetImage(_brandIconAsset), context);
    precacheImage(const AssetImage(_googleContinueButtonAsset), context);
    for (final asset in _heroAssets) {
      precacheImage(AssetImage(asset), context);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AuthViewModel>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: FreshColors.screen,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(22, 18, 22, 24 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AuthTopBar(),
                  const SizedBox(height: FreshSpacing.lg),
                  const _LoginHeroCarousel(assets: _heroAssets),
                  const SizedBox(height: FreshSpacing.lg),
                  FreshCard(
                    padding: const EdgeInsets.all(18),
                    radius: FreshRadii.xl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_registerMode) ...[
                          TextField(
                            key: const ValueKey('display_name_field'),
                            controller: _nameController,
                            onChanged: (_) =>
                                _clearErrors(name: true, remote: true),
                            decoration: InputDecoration(
                              labelText: l10n.authNameLabel,
                              errorText: _nameError,
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: FreshSpacing.md),
                        ],
                        TextField(
                          key: const ValueKey('email_field'),
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (_) =>
                              _clearErrors(email: true, remote: true),
                          decoration: InputDecoration(
                            labelText: l10n.authEmailLabel,
                            errorText: _emailError,
                            prefixIcon: const Icon(
                              Icons.alternate_email_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(height: FreshSpacing.md),
                        TextField(
                          key: const ValueKey('password_field'),
                          controller: _passwordController,
                          obscureText: true,
                          onChanged: (_) =>
                              _clearErrors(password: true, remote: true),
                          decoration: InputDecoration(
                            labelText: l10n.authPasswordLabel,
                            errorText: _passwordError,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: FreshSpacing.lg),
                        FilledButton.icon(
                          key: const ValueKey('auth_submit_button'),
                          onPressed: viewModel.isLoading ? null : _submit,
                          icon: viewModel.isLoading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.keyboard_double_arrow_right_rounded,
                                ),
                          label: Text(
                            _registerMode
                                ? l10n.authCreateAccountButton
                                : l10n.authGetStartedButton,
                          ),
                        ),
                        const SizedBox(height: FreshSpacing.sm),
                        _GoogleSignInButton(
                          isEnabled: !viewModel.isLoading,
                          label: l10n.authContinueWithGoogleButton,
                          onPressed: () => viewModel.loginWithGoogle(),
                        ),
                        TextButton(
                          key: const ValueKey('auth_toggle_mode_button'),
                          onPressed: _toggleMode,
                          child: Text(
                            _registerMode
                                ? l10n.authUseExistingAccountButton
                                : l10n.authCreateAccountLink,
                          ),
                        ),
                        if (viewModel.error != null) ...[
                          const SizedBox(height: FreshSpacing.sm),
                          FreshStatusBanner(
                            icon: Icons.error_outline_rounded,
                            title: _authErrorTitle(l10n, viewModel.errorSource),
                            message: viewModel.error!,
                            color: FreshColors.coral,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() {
    final viewModel = context.read<AuthViewModel>();
    viewModel.clearError();
    final l10n = context.l10n;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final displayName = _nameController.text.trim();
    final nextNameError = _registerMode && displayName.isEmpty
        ? l10n.authNameRequiredError
        : null;
    final nextEmailError =
        _isValidEmail(email) ? null : l10n.authEmailInvalidError;
    final nextPasswordError = password.isEmpty
        ? l10n.authPasswordRequiredError
        : _registerMode && password.length < 8
            ? l10n.authPasswordTooShortError
            : null;

    setState(() {
      _nameError = nextNameError;
      _emailError = nextEmailError;
      _passwordError = nextPasswordError;
    });

    if (nextNameError != null ||
        nextEmailError != null ||
        nextPasswordError != null) {
      return Future<void>.value();
    }

    if (_registerMode) {
      return viewModel.register(email, password, displayName);
    }
    return viewModel.login(email, password);
  }

  void _toggleMode() {
    context.read<AuthViewModel>().clearError();
    setState(() {
      _registerMode = !_registerMode;
      _nameError = null;
      _emailError = null;
      _passwordError = null;
    });
  }

  void _clearErrors({
    bool name = false,
    bool email = false,
    bool password = false,
    bool remote = false,
  }) {
    if (remote) context.read<AuthViewModel>().clearError();
    if ((name && _nameError != null) ||
        (email && _emailError != null) ||
        (password && _passwordError != null)) {
      setState(() {
        if (name) _nameError = null;
        if (email) _emailError = null;
        if (password) _passwordError = null;
      });
    }
  }

  String _authErrorTitle(AppLocalizations l10n, AuthErrorSource? source) {
    return switch (source) {
      AuthErrorSource.register => l10n.authCreateAccountFailedTitle,
      _ => l10n.authSignInFailedTitle,
    };
  }

  bool _isValidEmail(String value) {
    return RegExp(
      r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
      caseSensitive: false,
    ).hasMatch(value);
  }
}

class _AuthTopBar extends StatelessWidget {
  const _AuthTopBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Image.asset(
            _brandIconAsset,
            key: const ValueKey('auth_brand_icon'),
            width: 42,
            height: 42,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: FreshSpacing.sm),
        Semantics(
          label: context.l10n.appTitle,
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Better',
                  key: const ValueKey('auth_brand_better_word'),
                  style: titleStyle?.copyWith(color: palette.limeDeep),
                ),
                Text(
                  'Calories',
                  key: const ValueKey('auth_brand_calories_word'),
                  style: titleStyle,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.isEnabled,
    required this.label,
    required this.onPressed,
  });

  final bool isEnabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: isEnabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('google_sign_in_button'),
            onTap: isEnabled ? onPressed : null,
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: Center(
                child: Opacity(
                  opacity: isEnabled ? 1 : 0.52,
                  child: Image.asset(
                    _googleContinueButtonAsset,
                    height: 44,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginHeroCarousel extends StatefulWidget {
  const _LoginHeroCarousel({required this.assets});

  final List<String> assets;

  @override
  State<_LoginHeroCarousel> createState() => _LoginHeroCarouselState();
}

class _LoginHeroCarouselState extends State<_LoginHeroCarousel>
    with TickerProviderStateMixin {
  static const _panDuration = Duration(milliseconds: 10500);
  static const _fadeDuration = Duration(milliseconds: 900);
  static final _fadeCurve = CurveTween(curve: Curves.easeOutCubic);

  late final AnimationController _panController;
  late final AnimationController _fadeController;
  int _currentIndex = 0;
  int _nextIndex = 1;
  bool _isFading = false;
  bool _animationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _panController = AnimationController(vsync: this, duration: _panDuration)
      ..addStatusListener(_handlePanStatus);
    _fadeController = AnimationController(vsync: this, duration: _fadeDuration)
      ..addStatusListener(_handleFadeStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate =
        !MediaQuery.of(context).disableAnimations && widget.assets.length > 1;
    if (shouldAnimate == _animationsEnabled) return;
    _animationsEnabled = shouldAnimate;
    if (_animationsEnabled) {
      _panController.forward(from: 0);
    } else {
      _panController.stop();
      _fadeController.stop();
      _panController.value = 0;
      _fadeController.value = 0;
      _isFading = false;
    }
  }

  @override
  void didUpdateWidget(covariant _LoginHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assets.length == widget.assets.length) return;
    _currentIndex = 0;
    _nextIndex = widget.assets.length > 1 ? 1 : 0;
    _isFading = false;
    _fadeController.value = 0;
    if (_animationsEnabled) {
      _panController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _panController
      ..removeStatusListener(_handlePanStatus)
      ..dispose();
    _fadeController
      ..removeStatusListener(_handleFadeStatus)
      ..dispose();
    super.dispose();
  }

  void _handlePanStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed ||
        !_animationsEnabled ||
        _isFading ||
        widget.assets.length < 2) {
      return;
    }
    setState(() => _isFading = true);
    _fadeController.forward(from: 0);
  }

  void _handleFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      _currentIndex = _nextIndex;
      _nextIndex = (_currentIndex + 1) % widget.assets.length;
      _isFading = false;
    });
    _fadeController.value = 0;
    if (_animationsEnabled) {
      _panController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height < 740 ? 318.0 : 372.0;
    final staticMode =
        MediaQuery.of(context).disableAnimations || widget.assets.length == 1;
    return SizedBox(
      key: const ValueKey('login_hero_carousel'),
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FreshRadii.xl),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1f080907),
              blurRadius: 28,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FreshRadii.xl),
          child: AnimatedBuilder(
            animation: Listenable.merge([_panController, _fadeController]),
            builder: (context, _) {
              final fade = _fadeCurve.transform(_fadeController.value);
              final panProgress = staticMode ? 0.0 : _panController.value;
              final fadeProgress = staticMode || !_isFading ? 0.0 : fade;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: 1 - fadeProgress,
                    child: _LoginHeroImage(
                      assetPath: widget.assets[_currentIndex],
                      index: _currentIndex,
                      progress: panProgress,
                    ),
                  ),
                  if (!staticMode && _isFading)
                    Opacity(
                      opacity: fadeProgress,
                      child: _LoginHeroImage(
                        assetPath: widget.assets[_nextIndex],
                        index: _nextIndex,
                        progress: 0,
                      ),
                    ),
                  const _HeroSloganScrim(),
                  Positioned(
                    left: 24,
                    right: 24,
                    top: height < 340 ? 22 : 28,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _HeroHeadline(
                        text: context.l10n.authHeroHeadline,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroHeadline extends StatelessWidget {
  const _HeroHeadline({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final baseStyle = Theme.of(context).textTheme.displayLarge?.copyWith(
          color: palette.ink,
          fontSize: 38,
          fontWeight: FontWeight.w800,
          height: 1.08,
        );
    final split = _splitHighlight(text);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: split.prefix),
          TextSpan(
            text: split.highlight,
            style: TextStyle(
              color: palette.limeDeep,
              background: Paint()
                ..color = palette.surface.withValues(alpha: 0.94),
            ),
          ),
        ],
      ),
      key: const ValueKey('auth_hero_headline'),
      maxLines: 3,
      overflow: TextOverflow.visible,
      style: baseStyle,
    );
  }

  _HighlightSplit _splitHighlight(String value) {
    final match = RegExp(r'\S+\s*$').firstMatch(value);
    if (match == null) {
      return _HighlightSplit('', value);
    }
    return _HighlightSplit(
      value.substring(0, match.start),
      value.substring(match.start, match.end),
    );
  }
}

class _HighlightSplit {
  const _HighlightSplit(this.prefix, this.highlight);

  final String prefix;
  final String highlight;
}

class _LoginHeroImage extends StatelessWidget {
  const _LoginHeroImage({
    required this.assetPath,
    required this.index,
    required this.progress,
  });

  final String assetPath;
  final int index;
  final double progress;

  static final AlignmentTween _alignmentTween = AlignmentTween(
    begin: Alignment.bottomRight,
    end: Alignment.bottomLeft,
  );

  @override
  Widget build(BuildContext context) {
    final alignment = _alignmentTween.transform(progress);
    return Image.asset(
      assetPath,
      key: ValueKey('login_hero_image_$index'),
      fit: BoxFit.cover,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      width: double.infinity,
      height: double.infinity,
    );
  }
}

class _HeroSloganScrim extends StatelessWidget {
  const _HeroSloganScrim();

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.46, 0.78],
          colors: [
            palette.surface.withValues(alpha: 0.96),
            palette.surface.withValues(alpha: 0.78),
            palette.surface.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
