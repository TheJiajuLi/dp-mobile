import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/founding_badge.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../auth_service.dart';

const _primary = Color(0xFF6366F1);
const _ink = Color(0xFF1A1A1A);
const _bg = Color(0xFFFAFAF8);

final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
// 用户名允许任意语言的字母（中文/日文/韩文/西里尔等，\p{L}）+ 数字（\p{N}）
// + 下划线，只挡空格/标点/emoji。unicode:true 才能让 \p 类生效
final _usernameRegex = RegExp(r'^[\p{L}\p{N}_]+$', unicode: true);

// 三步注册（邮箱 → 邀请码 → 账号信息）+ 成功页，用 PageView 而不是分开的
// GoRoute，是因为这几步共享一次注册流程的状态（邀请码校验结果要带到
// 第三步渲染元老权益卡、带到最终提交），拆成独立页面反而要在页面间传
// 一堆参数
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _pageCtrl = PageController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  // 好友推荐码（选填）——注册时带上，好友发首篇文章后双方各得 7 天 Pro
  final _referralCtrl = TextEditingController();

  int _step = 0;
  bool _codeVerified = false;
  bool _isFoundingCreator = false;
  List<String> _codePerks = [];
  bool _verifying = false;
  bool _registering = false;
  bool _obscurePw = true;
  // 邀请码校验失败时的提示——服务端给什么文案就显示什么（"邀请码无效
  // 或已过期"这类），不猜测/改写
  String? _codeError;
  // 随机挑一条 slogan 并缓存——跟 login_screen.dart/splash_screen.dart
  // 同一套道理，didChangeDependencies 在语言/主题切换时会被重复调用，
  // 用可空字段 + ??= 才不会每次都重新随机
  String? _slogan;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    _slogan ??= [
      l10n.appSlogan,
      l10n.slogan2,
      l10n.slogan3,
    ][Random().nextInt(3)];
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _referralCtrl.dispose();
    super.dispose();
  }

  bool get _emailValid => _emailRegex.hasMatch(_emailCtrl.text.trim());

  bool get _usernameValid {
    final u = _usernameCtrl.text.trim();
    // 按字符数（grapheme）算长度——一个汉字算 1，不用 u.length（UTF-16 码元）
    final len = u.characters.length;
    return len >= 3 && len <= 20 && _usernameRegex.hasMatch(u);
  }

  bool get _passwordValid {
    final p = _passwordCtrl.text;
    return p.length >= 8 &&
        RegExp(r'[A-Za-z]').hasMatch(p) &&
        RegExp(r'[0-9]').hasMatch(p);
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    _pageCtrl.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  // 验证邀请码——只读校验，不消耗名额（真正生效在 _register 里连同
  // invite_code 一起提交注册时）
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _verifying = true;
      _codeError = null;
    });
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/invite/verify', data: {'code': code});
    if (!mounted) return;
    final data = res.data is Map ? res.data as Map : null;
    if (res.success && data?['valid'] == true) {
      setState(() {
        _codeVerified = true;
        _isFoundingCreator = data?['is_founding'] == true;
        _codePerks = ((data?['perks'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        _verifying = false;
      });
    } else {
      setState(() {
        _codeVerified = false;
        _isFoundingCreator = false;
        _codePerks = [];
        _codeError = res.message ?? data?['message']?.toString() ?? '邀请码无效或已过期';
        _verifying = false;
      });
    }
  }

  void _skipInviteCode() {
    setState(() {
      _codeVerified = false;
      _isFoundingCreator = false;
      _codePerks = [];
      _codeError = null;
    });
    _goToStep(2);
  }

  Future<void> _register() async {
    if (!_usernameValid || !_passwordValid) return;
    setState(() => _registering = true);
    try {
      await ref
          .read(authServiceProvider)
          .register(
            username: _usernameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            inviteCode: _codeVerified ? _codeCtrl.text.trim() : null,
            referralCode: _referralCtrl.text.trim().isEmpty
                ? null
                : _referralCtrl.text.trim(),
          );
      if (!mounted) return;
      // 标记"新用户还没看过创作指南"——只在注册流程置 false，进主页时会
      // 一次性叠上创作指南引导（见 _enterHome）。登录/老用户不写这个 key，
      // 默认按已看过处理，不会触发
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_creator_guide', false);
      if (!mounted) return;
      // register() 内部已经走完一次 /auth/login，currentUserProvider
      // 现在是服务端返回的真实用户数据——用它确认 is_founding_creator，
      // 不用第二步 verify 时客户端记的那份猜测值（万一码在这之间被
      // 别人用光/过期，服务端才是准的）
      final user = ref.read(currentUserProvider);
      setState(
        () =>
            _isFoundingCreator = user?.isFoundingCreator ?? _isFoundingCreator,
      );
      _goToStep(3);
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 成功页「开始创作」——进主页。新注册用户（has_seen_creator_guide==false）
  // 稍等主页加载完再一次性叠上创作指南，然后标记已看过。用提前拿到的
  // GoRouter（不是 context）做延迟跳转，因为这时 RegisterScreen 已经被
  // /home 替换、context 失效了
  Future<void> _enterHome() async {
    final router = GoRouter.of(context);
    final prefs = await SharedPreferences.getInstance();
    // 默认 true：只有注册流程显式置过 false 的新用户才触发，登录/老用户不会
    final seen = prefs.getBool('has_seen_creator_guide') ?? true;
    if (!mounted) return;
    router.go('/home');
    if (!seen) {
      await prefs.setBool('has_seen_creator_guide', true);
      Future.delayed(const Duration(milliseconds: 800), () {
        router.push('/creator/guide');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        // 点空白处收起键盘
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              if (_step < 3) _buildProgress(),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStep1Email(),
                    _buildStep2Code(),
                    _buildStep3Info(),
                    _buildStepSuccess(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 进度条（3步：邮箱/邀请码/账号信息），成功页不显示
  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        children: List.generate(
          3,
          (i) => Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: i < _step
                    ? _ink
                    : i == _step
                    ? _primary
                    : const Color(0xFFF0F0F0),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBox({required Widget child, Gradient? gradient, Color? color}) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? const Color(0xFFEEF0FF)) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  // 步骤1：邮箱
  Widget _buildStep1Email() {
    final l10n = AppLocalizations.of(context)!;
    final email = _emailCtrl.text.trim();
    final showValidation = email.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 极梦品牌 logo（四色弧线，透明底，保持 4:3 宽高比不拉伸）
          SvgPicture.asset('assets/images/jimeng_logo.svg', width: 96),
          const SizedBox(height: 16),
          Text(
            _slogan ?? l10n.appSlogan,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.createAccount,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '加入极梦，开始你的创作之旅',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '邮箱地址',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailCtrl,
            // 显式深色输入字色——不给 style 时会落到主题默认，在白底输入框上
            // 太浅、看不清刚输入的内容（注册页所有输入框统一补上）
            style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A)),
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'your@email.com',
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: showValidation && !_emailValid
                      ? const Color(0xFFDC2626)
                      : Colors.grey[200]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              !showValidation
                  ? '用于登录和找回密码'
                  : _emailValid
                  ? '邮箱格式正确'
                  : '请输入有效邮箱',
              style: TextStyle(
                fontSize: 12,
                color: !showValidation
                    ? Colors.grey[600]
                    : _emailValid
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _emailValid ? () => _goToStep(1) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                disabledBackgroundColor: const Color(0xFFF0F0F0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                '继续',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _emailValid ? Colors.white : Colors.grey[400],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey[300])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  l10n.alreadyHaveAccount,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey[300])),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: () => context.pop(),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey[300]!),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                l10n.login,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              Text(
                '继续即表示同意 ',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              GestureDetector(
                onTap: () => context.push('/settings/terms'),
                child: Text(
                  l10n.userAgreement,
                  style: const TextStyle(fontSize: 12, color: _primary),
                ),
              ),
              Text(
                ' 与 ',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              GestureDetector(
                onTap: () => context.push('/settings/privacy-policy'),
                child: Text(
                  l10n.privacyPolicy,
                  style: const TextStyle(fontSize: 12, color: _primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 步骤2：邀请码——权益卡片是通用营销文案（邀请码这类机制通常能解锁的
  // 权益说明），真正针对"这个码"的确认结果在校验成功后才出现
  Widget _buildStep2Code() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          _iconBox(
            child: const Icon(
              Icons.confirmation_number_outlined,
              color: _primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '有邀请码吗？',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '邀请码可解锁创始会员专属权益',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 15, color: _primary),
                    SizedBox(width: 6),
                    Text(
                      '邀请码专属权益',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final perk in const [
                  '「元老创作者」永久身份标识',
                  'Pro Max 会员免费 6 个月',
                  '极光计划免门槛直接开通',
                  '创始群成员，直接影响产品方向',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: Icon(Icons.circle, size: 4, color: _primary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            perk,
                            // 显式深色——这张卡是硬编码浅紫底，不写颜色的话
                            // 深色模式下会继承成白字、贴浅底看不见
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '邀请码',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF1A1A1A),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) {
                    if (_codeVerified || _codeError != null) {
                      setState(() {
                        _codeVerified = false;
                        _codeError = null;
                        _codePerks = [];
                      });
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'JIMENG',
                    filled: true,
                    fillColor: Colors.white,
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
                      borderSide: const BorderSide(color: _primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: _verifying ? null : _verifyCode,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _verifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _primary,
                          ),
                        )
                      : const Text(
                          '验证',
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _codeVerified
                  ? (_isFoundingCreator ? '✓ 邀请码有效，元老身份已确认' : '✓ 邀请码有效')
                  : _codeError ?? '输入邀请码后点击验证',
              style: TextStyle(
                fontSize: 12,
                color: _codeVerified
                    ? const Color(0xFF16A34A)
                    : _codeError != null
                    ? const Color(0xFFDC2626)
                    : Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _codeVerified ? () => _goToStep(2) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                disabledBackgroundColor: const Color(0xFFF0F0F0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                '使用邀请码继续',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _codeVerified ? Colors.white : Colors.grey[400],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _skipInviteCode,
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  children: const [
                    TextSpan(text: '没有邀请码？ '),
                    TextSpan(
                      text: '直接注册',
                      style: TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 步骤3：账号信息——isFoundingCreator 时头像图标/权益卡跟着变
  Widget _buildStep3Info() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          _isFoundingCreator
              ? _iconBox(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFF59E0B),
                      Color(0xFF818CF8),
                      Color(0xFF4ADE80),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A0E2E),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text('👑', style: TextStyle(fontSize: 28)),
                  ),
                )
              : _iconBox(
                  child: const Icon(Icons.bolt, color: _primary, size: 32),
                ),
          const SizedBox(height: 16),
          const Text(
            '设置账号信息',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          if (_isFoundingCreator) ...[
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 13, color: _primary),
                SizedBox(width: 4),
                Text(
                  '元老创作者通道',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '用户名',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameCtrl,
            style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A)),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '中文 / 字母 / 数字，3–20 位',
              filled: true,
              fillColor: Colors.white,
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
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '密码',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordCtrl,
            style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A)),
            obscureText: _obscurePw,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _register(),
            decoration: InputDecoration(
              hintText: '至少8位，含字母和数字',
              filled: true,
              fillColor: Colors.white,
              suffixIcon: GestureDetector(
                onTap: () => setState(() => _obscurePw = !_obscurePw),
                child: Icon(
                  _obscurePw
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.grey,
                  size: 20,
                ),
              ),
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
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '邀请码（选填）',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _referralCtrl,
            style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A)),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: '填好友邀请码，双方各得 7 天 Pro',
              prefixIcon: const Icon(
                Icons.card_giftcard_outlined,
                size: 18,
                color: Color(0xFF999999),
              ),
              filled: true,
              fillColor: Colors.white,
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
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          if (_isFoundingCreator && _codePerks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0E2E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        '★',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '注册完成后你将获得',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final perk in _codePerks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check,
                            size: 14,
                            color: Color(0xFF4ADE80),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              perk,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_usernameValid && _passwordValid && !_registering)
                  ? _register
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                disabledBackgroundColor: const Color(0xFFF0F0F0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _registering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '完成注册',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: (_usernameValid && _passwordValid)
                            ? Colors.white
                            : Colors.grey[400],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // 成功页——元老身份用极光头像环+大徽章，普通注册只是一句成功提示
  Widget _buildStepSuccess() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      child: Column(
        children: [
          _isFoundingCreator
              ? FoundingAvatarRing(
                  isFoundingCreator: true,
                  size: 88,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A0E2E),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text('👑', style: TextStyle(fontSize: 40)),
                  ),
                )
              : Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F8F0),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF16A34A),
                    size: 44,
                  ),
                ),
          const SizedBox(height: 20),
          Text(
            _isFoundingCreator ? '欢迎加入，元老！' : '注册成功',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isFoundingCreator ? '你是极梦最早的一批创作者\n感谢你的信任与支持' : '欢迎加入极梦，开始你的创作之旅',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
          if (_isFoundingCreator) ...[
            const SizedBox(height: 20),
            const FoundingBadgeLarge(),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _enterHome,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '开始创作',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
