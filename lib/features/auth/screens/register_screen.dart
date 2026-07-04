import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth_service.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _primary = Color(0xFF6366F1);
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pw2Ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePw = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pw = _pwCtrl.text;
    final pw2 = _pw2Ctrl.text;

    // 本地验证
    if (username.isEmpty || email.isEmpty || pw.isEmpty) {
      setState(() => _error = '请填写所有字段');
      return;
    }
    if (username.length < 2) {
      setState(() => _error = '用户名至少2个字符');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = '请输入正确的邮箱');
      return;
    }
    if (pw.length < 6) {
      setState(() => _error = '密码至少6位');
      return;
    }
    if (pw != pw2) {
      setState(() => _error = '两次密码不一致');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref
          .read(authServiceProvider)
          .register(username: username, email: email, password: pw);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // 返回按钮
              GestureDetector(
                onTap: () => context.pop(),
                child: Icon(
                  Icons.arrow_back_ios,
                  size: 20,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 32),
              // 标题
              const Text(
                '创建账号',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '加入极梦，开启数据分析之旅',
                style: TextStyle(fontSize: 15, color: Colors.grey[500]),
              ),
              const SizedBox(height: 36),

              // 用户名
              _label('用户名'),
              const SizedBox(height: 8),
              _field(
                controller: _usernameCtrl,
                hint: '你的用户名',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 16),

              // 邮箱
              _label('邮箱'),
              const SizedBox(height: 8),
              _field(
                controller: _emailCtrl,
                hint: 'your@email.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              // 密码
              _label('密码'),
              const SizedBox(height: 8),
              _field(
                controller: _pwCtrl,
                hint: '至少6位',
                icon: Icons.lock_outline,
                obscure: _obscurePw,
                suffix: GestureDetector(
                  onTap: () => setState(() => _obscurePw = !_obscurePw),
                  child: Icon(
                    _obscurePw
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.grey,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 确认密码
              _label('确认密码'),
              const SizedBox(height: 8),
              _field(
                controller: _pw2Ctrl,
                hint: '再次输入密码',
                icon: Icons.lock_outline,
                obscure: true,
                onSubmitted: (_) => _register(),
              ),
              const SizedBox(height: 20),

              // 错误提示
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 14,
                    ),
                  ),
                ),
              if (_error != null) const SizedBox(height: 16),

              // 注册按钮
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    disabledBackgroundColor: _primary.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          '注册',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // 已有账号
              Center(
                child: GestureDetector(
                  onTap: () => context.pop(),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14),
                      children: [
                        TextSpan(
                          text: '已有账号？',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                        const TextSpan(
                          text: '登录',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).textTheme.bodyLarge?.color,
    ),
  );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400]),
      prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Theme.of(context).inputDecorationTheme.fillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
