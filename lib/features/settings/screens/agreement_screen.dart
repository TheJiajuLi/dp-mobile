import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/app_toast.dart';

const _primary = AppColors.primary;
const _green = AppColors.success;
const _red = Color(0xFFDC2626);

// 用户协议——极梦原创声明协议的签署 / 状态展示 / 撤回。真实端点：
//   GET  /auth/agreement/status  → {signed, signedAt(秒), version, canWithdraw, protectedCount}
//   POST /auth/agreement/sign    {version}
//   POST /auth/agreement/withdraw
// 撤回冷静期 30 天（后端 WITHDRAW_LOCK_SECONDS），前端按 signedAt+30d 算倒计时
class AgreementScreen extends ConsumerStatefulWidget {
  const AgreementScreen({super.key});

  @override
  ConsumerState<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends ConsumerState<AgreementScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/agreement/status');
    if (!mounted) return;
    setState(() {
      if (res.success && res.data is Map) {
        _status = Map<String, dynamic>.from(res.data as Map);
      }
      // 失败也停 loading——按"未签署"兜底展示，不卡在转圈
      _loading = false;
    });
  }

  bool get _signed => _status?['signed'] == true;
  bool get _canWithdraw => _status?['canWithdraw'] == true;
  int get _protectedCount => (_status?['protectedCount'] as num?)?.toInt() ?? 0;
  int? get _signedAt => (_status?['signedAt'] as num?)?.toInt();

  String _formatTime(int? tsSec) {
    if (tsSec == null) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(tsSec * 1000);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }

  // 撤回解锁日期（signedAt + 30 天）格式化为 yyyy-MM-dd
  String _withdrawUnlockDate() {
    final s = _signedAt;
    if (s == null) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch((s + 30 * 24 * 3600) * 1000);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)}';
  }

  int _daysLeftNum() {
    final s = _signedAt;
    if (s == null) return 0;
    final unlockAt = s + 30 * 24 * 3600;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return ((unlockAt - now) / 86400).ceil();
  }

  String _daysLeft() {
    final d = _daysLeftNum();
    return d > 0 ? '还剩 $d 天' : '可申请';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFFAFAF8),
      appBar: AppBar(
        title: const Text('用户协议'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _signed
          ? _buildSigned(isDark)
          : _buildUnsigned(isDark),
    );
  }

  // ---------------- 未签署 ----------------
  Widget _buildUnsigned(bool isDark) {
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _statusCard(
                isDark: isDark,
                badgeText: '未签署',
                badgeColor: muted,
                badgeBg: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF0F0F0),
                desc: '签署此协议，承诺发布内容为原创。极梦将为你的作品提供著作权保护，并计入极光积累。',
                rows: [
                  _row('协议状态', '未签署', valueColor: muted),
                  _row('受保护文章', '0 篇', valueColor: muted),
                  _row('极光积累', '未计入', valueColor: _red),
                  _row('著作权标识', '未启用', valueColor: muted),
                ],
              ),
              const SizedBox(height: 14),
              _benefitsCard(
                isDark: isDark,
                title: '🛡️ 签署后你将获得',
                items: const [
                  '所有发布内容自动获得著作权保护',
                  '文章正式计入极光创作者积累',
                  '创作者主页展示原创协议标识',
                  '签署30天后可随时申请撤回',
                ],
              ),
              const SizedBox(height: 14),
              _noticeCard(
                isDark: isDark,
                icon: '📘',
                title: '签署前须知',
                text: '签署即承诺你发布的内容为原创，不存在抄袭、洗稿等行为。签署后30天内不可撤回。',
              ),
            ],
          ),
        ),
        _bottomBar(
          isDark,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showSignSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '阅读并签署协议',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- 已签署 ----------------
  Widget _buildSigned(bool isDark) {
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _statusCard(
                isDark: isDark,
                badgeText: '✓ 已生效',
                badgeColor: _green,
                badgeBg: _green.withValues(alpha: isDark ? 0.18 : 0.10),
                desc: '你的发布内容已受著作权保护，并正式计入极光创作者积累。',
                rows: [
                  _row('签署时间', _formatTime(_signedAt), valueColor: ink),
                  _row(
                    '协议版本',
                    (_status?['version'] as String?) ?? 'v1.0',
                    valueColor: ink,
                  ),
                  _row('受保护文章', '$_protectedCount 篇', valueColor: _green),
                  _row('极光积累', '计入中', valueColor: _green),
                  _row(
                    '可撤回时间',
                    _canWithdraw ? '现在可申请' : '${_withdrawUnlockDate()} 后',
                    valueColor: ink,
                  ),
                  if (!_canWithdraw)
                    _row('距可撤回', _daysLeft(), valueColor: _red),
                ],
              ),
              const SizedBox(height: 14),
              _benefitsCard(
                isDark: isDark,
                title: '🛡️ 协议权益（生效中）',
                items: const [
                  '所有发布内容自动获得著作权标识',
                  '文章正式计入极光创作者积累',
                  '创作者主页展示「已签原创协议」',
                ],
              ),
              const SizedBox(height: 14),
              _timelineCard(isDark),
              const SizedBox(height: 14),
              _noticeCard(
                isDark: isDark,
                icon: '⚠️',
                title: '撤回须知',
                text: '撤回后，已发布文章将失去著作权标识，不再计入极光积累。再次发布需重新签署。',
                danger: true,
              ),
            ],
          ),
        ),
        _bottomBar(
          isDark,
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _canWithdraw ? _showWithdrawDialog : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: _red,
                disabledForegroundColor: muted,
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: BorderSide(
                  color: _canWithdraw
                      ? _red
                      : (isDark
                            ? Theme.of(context).dividerColor
                            : const Color(0xFFEEEEEE)),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _canWithdraw ? '申请撤回协议' : '申请撤回协议（${_daysLeft()}解锁）',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- 组件 ----------------
  Widget _statusCard({
    required bool isDark,
    required String badgeText,
    required Color badgeColor,
    required Color badgeBg,
    required String desc,
    required List<Widget> rows,
  }) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final secondary = isDark ? Colors.white70 : const Color(0xFF666666);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Theme.of(context).dividerColor
              : const Color(0xFFEEEEEE),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '极梦原创声明协议',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: TextStyle(fontSize: 13, height: 1.6, color: secondary),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, String value, {required Color valueColor}) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : const Color(0xFF999999);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: muted)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _benefitsCard({
    required bool isDark,
    required String title,
    required List<String> items,
  }) {
    final textColor = isDark ? const Color(0xFFC7CBEE) : const Color(0xFF444B6E);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A35)
            : const Color(0xFFEEF0FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? const Color(0xFF2E2E55)
              : const Color(0xFFC7D2FE),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(height: 12),
          ...items.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: _primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeCard({
    required bool isDark,
    required String icon,
    required String title,
    required String text,
    bool danger = false,
  }) {
    final accent = danger ? _red : const Color(0xFF2563EB);
    final bg = danger
        ? (isDark ? const Color(0xFF2A1518) : const Color(0xFFFEF2F2))
        : (isDark ? const Color(0xFF12203A) : const Color(0xFFEFF6FF));
    final border = danger
        ? (isDark ? const Color(0xFF4A2226) : const Color(0xFFFCA5A5))
        : (isDark ? const Color(0xFF1E3358) : const Color(0xFFBFDBFE));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$icon $title',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: isDark ? Colors.white70 : const Color(0xFF555555),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineCard(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Theme.of(context).dividerColor
              : const Color(0xFFEEEEEE),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '签署记录',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 14),
          _timelineItem(
            dotColor: _primary,
            time: _formatTime(_signedAt),
            text: '签署极梦原创声明协议 ${(_status?['version'] as String?) ?? 'v1.0'}',
            ink: ink,
            muted: muted,
            showLine: true,
          ),
          _timelineItem(
            dotColor: muted,
            time: '${_withdrawUnlockDate()} 后可操作',
            text: '可申请撤回协议',
            ink: muted,
            muted: muted,
            showLine: false,
          ),
        ],
      ),
    );
  }

  Widget _timelineItem({
    required Color dotColor,
    required String time,
    required String text,
    required Color ink,
    required Color muted,
    required bool showLine,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (showLine)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: muted.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showLine ? 14 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time, style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 3),
                  Text(text, style: TextStyle(fontSize: 13, color: ink)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(bool isDark, {required Widget child}) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Theme.of(context).dividerColor
                  : const Color(0xFFEEEEEE),
              width: 0.5,
            ),
          ),
        ),
        child: child,
      ),
    );
  }

  // ---------------- 签署 Sheet ----------------
  void _showSignSheet() {
    var agreed = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
        final secondary = isDark ? Colors.white70 : const Color(0xFF555555);
        final border = isDark
            ? Theme.of(ctx).dividerColor
            : const Color(0xFFEEEEEE);
        return StatefulBuilder(
          builder: (ctx, setSt) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                    child: Text(
                      '极梦原创声明协议 v1.0',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 260,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        _agreementText,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.8,
                          color: secondary,
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: border),
                  InkWell(
                    onTap: () => setSt(() => agreed = !agreed),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.only(top: 1),
                            decoration: BoxDecoration(
                              color: agreed ? _primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: agreed ? _primary : border,
                                width: 1.5,
                              ),
                            ),
                            child: agreed
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '我已阅读并理解上述协议，承诺发布内容为原创，同意签署极梦原创声明协议。',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: agreed ? () => _sign(ctx) : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: _primary.withValues(
                                alpha: 0.4,
                              ),
                              disabledForegroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              '签署协议',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              '取消',
                              style: TextStyle(
                                fontSize: 14,
                                color: secondary,
                              ),
                            ),
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
      },
    );
  }

  Future<void> _sign(BuildContext sheetCtx) async {
    Navigator.pop(sheetCtx);
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/agreement/sign', data: {'version': 'v1.0'});
    if (!mounted) return;
    if (res.success) {
      showAppToast(context, '协议签署成功 🛡️', ok: true);
      _loadStatus();
    } else {
      showAppToast(context, res.message ?? '签署失败，请重试');
    }
  }

  // ---------------- 撤回 ----------------
  void _showWithdrawDialog() {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('确认撤回协议'),
        content: const Text(
          '撤回后：\n'
          '• 已发布文章失去著作权标识\n'
          '• 不再计入极光创作者积累\n'
          '• 再次发布需重新签署\n\n'
          '此操作不可撤销，确认撤回？',
          style: TextStyle(fontSize: 13.5, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text('取消', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => _withdraw(dCtx),
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('确认撤回'),
          ),
        ],
      ),
    );
  }

  Future<void> _withdraw(BuildContext dCtx) async {
    Navigator.pop(dCtx);
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/agreement/withdraw');
    if (!mounted) return;
    if (res.success) {
      showAppToast(context, '协议已撤回', ok: true);
      _loadStatus();
    } else {
      showAppToast(context, res.message ?? '撤回失败，请重试');
    }
  }
}

const _agreementText = '''一、协议目的
本协议旨在保护极梦平台创作者的原创权益，鼓励优质原创内容创作，建立可信赖的知识创作社区。

二、创作者承诺
签署本协议即表明你承诺：所发布内容为本人原创，不存在抄袭、洗稿、剽窃他人成果等行为；如引用他人内容，将注明出处。

三、极梦的承诺
极梦平台将为签署创作者发布的内容提供著作权标识，内容哈希与时间戳永久存证，可作为维权证据。发布内容正式计入极光创作者积累体系。

四、协议变更与撤回
签署后30天内不可撤回，此后可随时申请撤回。撤回后已发布内容将失去著作权标识，且不再计入极光积累。再次发布需重新签署。

五、法律效力
本协议具有法律约束力，签署记录以加密形式永久储存，可作为维权证明。本协议目前处于试验阶段。''';
