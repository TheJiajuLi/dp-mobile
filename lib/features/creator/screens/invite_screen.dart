import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../messages/utils/message_avatar.dart';

const _primary = Color(0xFF6366F1);

class InviteRecord {
  final String username;
  final String? avatar;
  final int joinedAt;
  final bool hasPublished;

  const InviteRecord({
    required this.username,
    required this.avatar,
    required this.joinedAt,
    required this.hasPublished,
  });
}

// 邀请好友页——展示专属邀请码、分享、奖励规则和邀请记录。数据来自
// GET /auth/referral/info：好友用你的邀请码注册并发布第一篇文章后，双方各得
// 7 天免费 Pro（叠加在现有会员到期日上）。入口在创作者中心「邀请好友」
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  bool _loading = true;
  String _referralCode = '';
  int _totalInvited = 0;
  int _activatedCount = 0;
  int _rewardDays = 0;
  List<InviteRecord> _invites = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/referral/info');
    if (!mounted) return;
    if (res.success && res.data != null) {
      final d = Map<String, dynamic>.from(res.data as Map);
      setState(() {
        _referralCode = d['referralCode']?.toString() ?? '';
        // totalInvited 缺失时退回 referralCount（老接口只给这个）
        _totalInvited =
            (d['totalInvited'] as num?)?.toInt() ??
            (d['referralCount'] as num?)?.toInt() ??
            0;
        _activatedCount = (d['activatedCount'] as num?)?.toInt() ?? 0;
        _rewardDays = (d['rewardDays'] as num?)?.toInt() ?? 0;
        _invites = ((d['invites'] as List?) ?? []).map((i) {
          final m = Map<String, dynamic>.from(i as Map);
          return InviteRecord(
            username: m['username']?.toString() ?? '用户',
            avatar: m['avatar']?.toString(),
            joinedAt: (m['joinedAt'] as num?)?.toInt() ?? 0,
            hasPublished: m['hasPublished'] == true,
          );
        }).toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  void _copyCode() {
    if (_referralCode.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _referralCode));
    showAppToast(context, '邀请码已复制', ok: true);
  }

  void _shareCode() {
    if (_referralCode.isEmpty) return;
    final text =
        '我在用极梦写数学和代码文章，公式完美渲染，代码可以直接运行。\n\n'
        '用我的邀请码注册，双方各得 7 天免费 Pro：\n\n'
        '邀请码：$_referralCode\n\n'
        'App Store 搜「极梦 DreamingPolar」';
    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '邀请好友',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildHero(),
                _buildRewardRow(isDark),
                _buildCodeCard(isDark),
                _buildStatsRow(isDark),
                if (_invites.isNotEmpty) ...[
                  _sectionTitle('邀请记录'),
                  ..._invites.map((i) => _buildInviteItem(i, isDark)),
                ],
                _buildRules(isDark),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildHero() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF2D1B69)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.group_outlined,
              color: Color(0xFF818CF8),
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '邀请好友，双方得 Pro',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '好友通过你的邀请码注册并发布第一篇文章，双方各得 7 天免费 Pro 体验。',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardRow(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          _rewardCard(
            isDark,
            icon: Icons.card_giftcard_outlined,
            iconColor: _primary,
            iconBg: const Color(0xFFEEF0FF),
            label: '你获得',
            value: '+7天 Pro',
          ),
          const SizedBox(width: 8),
          _rewardCard(
            isDark,
            icon: Icons.auto_awesome_outlined,
            iconColor: const Color(0xFF16A34A),
            iconBg: const Color(0xFFEAFBF1),
            label: '好友获得',
            value: '+7天 Pro',
          ),
          const SizedBox(width: 8),
          _rewardCard(
            isDark,
            icon: Icons.edit_note_outlined,
            iconColor: const Color(0xFFD97706),
            iconBg: const Color(0xFFFEF3C7),
            label: '触发条件',
            value: '发布第一篇',
          ),
        ],
      ),
    );
  }

  Widget _rewardCard(
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? Theme.of(context).cardColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor(isDark), width: 0.5),
        ),
        child: Column(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? iconColor.withValues(alpha: 0.16) : iconBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF999999)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).cardColor : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor(isDark), width: 0.5),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '你的专属邀请码',
              style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111118) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor(isDark), width: 0.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _referralCode.isEmpty ? '——' : _referralCode,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _copyCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '复制',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _shareCode,
              icon: const Icon(Icons.share_outlined, size: 16),
              label: const Text('分享给好友'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          _statCard(isDark, '$_totalInvited', '已邀请好友'),
          const SizedBox(width: 8),
          _statCard(isDark, '$_activatedCount', '已触发奖励'),
          const SizedBox(width: 8),
          _statCard(isDark, '$_rewardDays 天', '累计获得 Pro'),
        ],
      ),
    );
  }

  Widget _statCard(bool isDark, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? Theme.of(context).cardColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor(isDark), width: 0.5),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 14, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }

  Widget _buildInviteItem(InviteRecord invite, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).cardColor : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor(isDark), width: 0.5),
      ),
      child: Row(
        children: [
          buildMessageAvatar(invite.avatar, invite.username, radius: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  invite.hasPublished ? '已发布文章' : '还未发布文章',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: invite.hasPublished
                  ? (isDark
                        ? const Color(0xFF16A34A).withValues(alpha: 0.16)
                        : const Color(0xFFEAFBF1))
                  : (isDark
                        ? const Color(0xFF111118)
                        : const Color(0xFFF5F5F5)),
              borderRadius: BorderRadius.circular(99),
              border: invite.hasPublished
                  ? null
                  : Border.all(color: _borderColor(isDark), width: 0.5),
            ),
            child: Text(
              invite.hasPublished ? '+7天 ✓' : '待激活',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: invite.hasPublished
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF999999),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRules(bool isDark) {
    const rules = [
      '好友通过你的邀请码注册后，双方即获得资格',
      '好友发布第一篇文章后奖励正式激活，双方各得 7 天 Pro',
      '每邀请一位新好友可获得一次奖励，不限次数',
      '奖励在现有会员到期日上叠加，不浪费',
      '邀请码长期有效，分享后随时可用',
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 16, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).cardColor : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor(isDark), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '活动规则',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 10),
          ...rules.map(
            (rule) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '·  ',
                    style: TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rule,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF999999),
                        height: 1.6,
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

  Color _borderColor(bool isDark) =>
      isDark ? Theme.of(context).dividerColor : const Color(0xFFEBEBEB);
}
