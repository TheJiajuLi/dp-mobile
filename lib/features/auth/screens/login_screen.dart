import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/jimeng_logo.dart';
import '../auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOAuthError());
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  // main.dart 的 deep link 处理器在 OAuth 失败时会带着 oauth_error 跳回
  // 这个页面——用 query 参数而不是直接弹 SnackBar，是因为发起弹窗那一刻
  // （MyApp 顶层）拿不到一个保证挂在 Scaffold 下面的 context
  void _checkOAuthError() {
    if (!mounted) return;
    final error = GoRouterState.of(context).uri.queryParameters['oauth_error'];
    if (error == null) return;
    _placeholderSnack(switch (error) {
      'google_failed' => 'Google 登录失败，请重试',
      'github_failed' => 'GitHub 登录失败，请重试',
      _ => '登录失败，请重试',
    });
  }

  Future<void> _loginWithGoogle() => _launchOAuth('google');
  Future<void> _loginWithGithub() => _launchOAuth('github');

  Future<void> _launchOAuth(String provider) async {
    final url = Uri.parse('${AppConstants.baseUrl}/auth/oauth/$provider');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _placeholderSnack('无法打开登录页面');
  }

  // Sign in with Apple（仅 iOS）：原生取凭证 → auth_service.appleLogin 换 token。
  // 用户主动取消（canceled）静默忽略，不弹错误
  Future<void> _signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final fullName = credential.givenName != null
          ? '${credential.givenName} ${credential.familyName ?? ''}'.trim()
          : null;
      if (!mounted) return;
      setState(() => _loading = true);
      final ok = await ref
          .read(authServiceProvider)
          .appleLogin(
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            fullName: fullName,
            email: credential.email,
          );
      if (!mounted) return;
      setState(() => _loading = false);
      if (ok) {
        context.go('/home');
      } else {
        _placeholderSnack('Apple 登录失败，请重试');
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      // 用户取消不算错误；其它授权异常才提示
      if (e.code != AuthorizationErrorCode.canceled && mounted) {
        _placeholderSnack('Apple 登录失败，请重试');
      }
    } catch (_) {
      if (mounted) _placeholderSnack('Apple 登录失败，请重试');
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final ok = await ref
        .read(authServiceProvider)
        .login(_emailCtrl.text.trim(), _pwdCtrl.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      context.go('/home');
    } else {
      final l10n = AppLocalizations.of(context)!;
      showAppToast(context, l10n.loginErrorInvalidCredentials);
    }
  }

  void _placeholderSnack(String message) {
    showAppToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D0B1A) : const Color(0xFFFAFAF8);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(child: _AuroraGlowLayer()),
            ),
            SafeArea(
              // 点空白处收起键盘
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
                  child: Column(
                    children: [
                      const JimengLogo(size: 80),
                      const SizedBox(height: 16),
                      Text(
                        l10n.appName,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dreaming Polar',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 2,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.4)
                              : const Color(0xFFAAAAAA),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _inputCard(isDark),
                            const SizedBox(height: 24),
                            _loginButton(l10n, isDark),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _divider(isDark),
                      const SizedBox(height: 16),
                      // Sign in with Apple——仅 iOS 显示（App Store 审核要求）
                      if (Platform.isIOS) ...[
                        _appleButton(isDark),
                        const SizedBox(height: 10),
                      ],
                      _thirdPartyRow(isDark),
                      const SizedBox(height: 24),
                      _registerRow(isDark),
                      const SizedBox(height: 32),
                      _agreement(context, l10n, isDark),
                    ],
                  ),
                ),
              ),
            ),
            if (Navigator.canPop(context))
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(
                      Icons.arrow_back_ios,
                      size: 18,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inputCard(bool isDark) {
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFEBEBEB);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF5F5F5);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final hintColor = isDark ? Colors.white38 : Colors.grey[400];
    final iconColor = isDark ? Colors.white54 : Colors.grey[500];

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.person_outline, size: 20, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: textColor, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '手机号 / 邮箱',
                      hintStyle: TextStyle(color: hintColor, fontSize: 15),
                      filled: false,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入手机号或邮箱' : null,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: dividerColor,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 20, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _pwdCtrl,
                    obscureText: _obscure,
                    style: TextStyle(color: textColor, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '密码',
                      hintStyle: TextStyle(color: hintColor, fontSize: 15),
                      filled: false,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                    onFieldSubmitted: (_) => _handleLogin(),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _obscure = !_obscure),
                  child: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => context.push('/forgot-password'),
                  child: Text(
                    '忘记',
                    style: TextStyle(fontSize: 13, color: iconColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginButton(AppLocalizations l10n, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _loading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? AppColors.primary : const Color(0xFF1A1A1A),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                l10n.login,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  Widget _divider(bool isDark) {
    final lineColor = isDark ? Colors.white24 : const Color(0xFFE5E5E5);
    final textColor = isDark ? Colors.white38 : Colors.grey[500];
    return Row(
      children: [
        Expanded(child: Container(height: 0.5, color: lineColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('或者', style: TextStyle(fontSize: 13, color: textColor)),
        ),
        Expanded(child: Container(height: 0.5, color: lineColor)),
      ],
    );
  }

  Widget _appleButton(bool isDark) {
    // 深色用白底黑字、浅色用黑底白字，符合 Apple 人机指南；圆角与其它按钮一致
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: SignInWithAppleButton(
        onPressed: _loading ? () {} : _signInWithApple,
        text: '通过 Apple 登录',
        height: 48,
        borderRadius: BorderRadius.circular(14),
        style: isDark
            ? SignInWithAppleButtonStyle.white
            : SignInWithAppleButtonStyle.black,
      ),
    );
  }

  Widget _thirdPartyRow(bool isDark) {
    final bg = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white;
    final borderSide = isDark
        ? BorderSide.none
        : const BorderSide(color: Color(0xFFEBEBEB), width: 0.5);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final style = OutlinedButton.styleFrom(
      backgroundColor: bg,
      side: borderSide,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _loginWithGoogle,
              style: style,
              icon: Icon(Icons.g_mobiledata, size: 24, color: textColor),
              label: Text(
                'Google',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _loginWithGithub,
              style: style,
              icon: Icon(Icons.code, size: 18, color: textColor),
              label: Text(
                'GitHub',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _registerRow(bool isDark) {
    final textColor = isDark ? Colors.white54 : Colors.grey[600];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('还没有账号？', style: TextStyle(fontSize: 13, color: textColor)),
        GestureDetector(
          onTap: () => context.push('/register'),
          child: const Text(
            '立即注册',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _agreement(BuildContext context, AppLocalizations l10n, bool isDark) {
    final textColor = isDark ? Colors.white38 : Colors.grey[400];
    final linkColor = isDark ? Colors.white70 : Colors.grey[700];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 2,
      children: [
        Text('登录即代表同意', style: TextStyle(fontSize: 11.5, color: textColor)),
        GestureDetector(
          onTap: () => context.push('/settings/terms'),
          child: Text(
            l10n.userAgreement,
            style: TextStyle(
              fontSize: 11.5,
              color: linkColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text('和', style: TextStyle(fontSize: 11.5, color: textColor)),
        GestureDetector(
          onTap: () => context.push('/settings/privacy-policy'),
          child: Text(
            l10n.privacyPolicy,
            style: TextStyle(
              fontSize: 11.5,
              color: linkColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuroraGlowLayer extends StatelessWidget {
  const _AuroraGlowLayer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned(
          top: -80,
          left: -100,
          child: _blob(
            isDark
                ? const Color(0xFF4A48B4).withValues(alpha: 0.35)
                : const Color(0xFF6366F1).withValues(alpha: 0.08),
          ),
        ),
        if (isDark)
          Positioned(
            top: -60,
            right: -120,
            child: _blob(const Color(0xFF6366F1).withValues(alpha: 0.20)),
          ),
      ],
    );
  }

  Widget _blob(Color color) => Container(
    width: 420,
    height: 420,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}
