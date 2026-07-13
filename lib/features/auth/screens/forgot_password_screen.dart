import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/jimeng_logo.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  // 后端 POST /auth/forgot-password 不管邮箱存不存在都回同一句"如果该
  // 邮箱已注册，重置链接已发送"——不泄露邮箱是否注册过，这里直接照抄
  // 后端的话术当成功态展示，不用自己再编一句
  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/forgot-password', data: {'email': email});
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success) {
        _sent = true;
      } else {
        _error = res.message ?? '发送失败，请稍后重试';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D0B1A) : const Color(0xFFFAFAF8);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Stack(
            children: [
              // 点空白处收起键盘
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 32),
                  child: _sent ? _buildSuccess(isDark) : _buildForm(isDark),
                ),
              ),
              Padding(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : Colors.grey[500];
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFEBEBEB);
    final hintColor = isDark ? Colors.white38 : Colors.grey[400];
    final iconColor = isDark ? Colors.white54 : Colors.grey[500];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const JimengLogo(size: 64),
        const SizedBox(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '忘记密码了？',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '输入你的注册邮箱，我们会发送重置链接给你。',
            style: TextStyle(fontSize: 14, color: muted, height: 1.6),
          ),
        ),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.email_outlined, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  style: TextStyle(color: ink, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'your@email.com',
                    hintStyle: TextStyle(color: hintColor, fontSize: 15),
                    filled: false,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFDC2626),
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
                    '发送重置邮件',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => context.pop(),
          child: Text('返回登录', style: TextStyle(fontSize: 13, color: muted)),
        ),
      ],
    );
  }

  Widget _buildSuccess(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : Colors.grey[500];
    final mutedLight = isDark ? Colors.white38 : Colors.grey[400];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: Color(0xFFDCFCE7),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 40,
            color: Color(0xFF16A34A),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '邮件已发送',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '重置链接已发送至\n${_emailCtrl.text.trim()}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: muted, height: 1.6),
        ),
        const SizedBox(height: 8),
        Text(
          '请检查收件箱（包括垃圾邮件）\n链接 1 小时内有效',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: mutedLight, height: 1.6),
        ),
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
              '返回登录',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() => _sent = false),
          child: Text(
            '没收到？重新发送',
            style: TextStyle(fontSize: 13, color: mutedLight),
          ),
        ),
      ],
    );
  }
}
