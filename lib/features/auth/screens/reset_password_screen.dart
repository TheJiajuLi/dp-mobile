import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

// 从邮件里的 jimeng://reset-password?token=xxx 链接落地——main.dart 的
// deep link 监听器解析出 token 之后带着它 push 到这里
class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String token;
  const ResetPasswordScreen({super.key, required this.token});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _done = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _pwCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (pw.length < 6) {
      setState(() => _error = '密码至少6位');
      return;
    }
    if (pw != confirm) {
      setState(() => _error = '两次密码不一致');
      return;
    }
    if (widget.token.isEmpty) {
      setState(() => _error = '重置链接无效，请重新申请');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/reset-password',
          data: {'token': widget.token, 'newPassword': pw},
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      // 后端成功/token失效/token已用/token过期都走各自不同的 message，
      // 直接透传比自己编一句"重置失败，链接可能已过期"更准确
      if (res.success) {
        _done = true;
      } else {
        _error = res.message ?? '重置失败，请重试';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D0B1A) : const Color(0xFFFAFAF8);
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: ink),
          title: Text(
            '设置新密码',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ),
        body: SafeArea(
          // 点空白处收起键盘
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: _done ? _buildDone(isDark) : _buildForm(isDark),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : Colors.grey[500];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          '设置新密码',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        Text('请设置你的新密码', style: TextStyle(fontSize: 14, color: muted)),
        const SizedBox(height: 32),
        _pwField(isDark, '新密码', _pwCtrl),
        const SizedBox(height: 12),
        _pwField(isDark, '确认新密码', _confirmCtrl),
        if (_error != null) ...[const SizedBox(height: 12), _errorBox(_error!)],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark
                  ? AppColors.primary
                  : const Color(0xFF1A1A1A),
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
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '确认重置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _pwField(bool isDark, String label, TextEditingController ctrl) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : Colors.grey[600];
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFEBEBEB);
    final hintColor = isDark ? Colors.white38 : Colors.grey[400];
    final iconColor = isDark ? Colors.white54 : Colors.grey[500];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  obscureText: _obscure,
                  style: TextStyle(color: ink, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '至少6位',
                    hintStyle: TextStyle(color: hintColor, fontSize: 15),
                    filled: false,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorBox(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFEE2E2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            msg,
            style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
          ),
        ),
      ],
    ),
  );

  Widget _buildDone(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : Colors.grey[500];

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 40,
              color: Color(0xFF16A34A),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '密码已重置',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          Text('请用新密码重新登录', style: TextStyle(fontSize: 14, color: muted)),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? AppColors.primary
                    : const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '去登录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
