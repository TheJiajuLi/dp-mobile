import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/aurora_progress_model.dart';

const _bg = Color(0xFF0A0812);
const _glass = Color(0x0FFFFFFF);
const _glassBorder = Color(0x1AFFFFFF);
const _cyan = Color(0xFFA5F3FC);
const _primary = AppColors.primary;
const _gold = Color(0xFFF59E0B);
const _green = AppColors.success;

// 极光创作者"每月续期"进度页——跟 creator/screens/aurora_screen.dart
// 不是同一个页面：那边是"还没入选"时的申请门槛/宣传页（一次性达标
// 10篇/100赞/50粉丝），这里是"已经入选"之后每月要保持活跃续期
// Pro Max 的进度追踪（6项任意满足3项），数据源是真实的
// GET /auth/aurora/progress，不是本地估算
class AuroraProgressScreen extends ConsumerStatefulWidget {
  const AuroraProgressScreen({super.key});

  @override
  ConsumerState<AuroraProgressScreen> createState() =>
      _AuroraProgressScreenState();
}

class _AuroraProgressScreenState extends ConsumerState<AuroraProgressScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loading = true;
  String? _error;
  AuroraProgress? _progress;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ref.read(apiClientProvider).get('/auth/aurora/progress');
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.message ?? '加载失败';
      });
      return;
    }
    setState(() {
      _progress = AuroraProgress.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '极光创作者 · 续期进度',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          indicatorColor: _gold,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: '我的进度'),
            Tab(text: '续费规则'),
            Tab(text: '历史记录'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _cyan))
            : _error != null
            ? _errorState()
            : TabBarView(
                controller: _tabCtrl,
                children: [
                  _progressTab(_progress!),
                  _rulesTab(),
                  _historyTab(_progress!),
                ],
              ),
      ),
    );
  }

  Widget _errorState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _error!,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _load,
          child: const Text('重试', style: TextStyle(color: _cyan)),
        ),
      ],
    ),
  );

  Widget _glassCard({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _glass,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _glassBorder),
    ),
    child: child,
  );

  // ── Tab 1：我的进度 ──────────────────────────────────────────────
  Widget _progressTab(AuroraProgress progress) {
    final m = progress.currentMonth;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (progress.isAuroraCreator ? _gold : _cyan)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      progress.isAuroraCreator
                          ? Icons.workspace_premium
                          : Icons.hourglass_empty,
                      color: progress.isAuroraCreator ? _gold : _cyan,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          progress.isAuroraCreator ? '极光创作者已激活' : '尚未激活极光创作者',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          m.yearMonth,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (m.isQualified ? _green : _primary).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  m.isQualified
                      ? '本月已满足续期条件（${m.metConditions}/6 项），月底自动续期 Pro Max'
                      : '本月已满足 ${m.metConditions}/6 项，任意满足 3 项即可续期',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: m.isQualified ? const Color(0xFF86EFAC) : _cyan,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '本月活跃指标',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 6),
              _conditionRow(
                icon: Icons.edit_note,
                iconBg: const Color(0xFFEEF0FF),
                iconColor: _primary,
                label: '发布笔记',
                current: m.publishedCount,
                target: 2,
              ),
              _conditionRow(
                icon: Icons.thumb_up_outlined,
                iconBg: const Color(0xFFECFDF5),
                iconColor: _green,
                label: '点赞他人',
                current: m.likedOthersCount,
                target: 20,
              ),
              _conditionRow(
                icon: Icons.chat_bubble_outline,
                iconBg: const Color(0xFFFEF3C7),
                iconColor: const Color(0xFFD97706),
                label: '发表评论',
                current: m.commentedCount,
                target: 5,
              ),
              _conditionRow(
                icon: Icons.reply_outlined,
                iconBg: const Color(0xFFFCE7F3),
                iconColor: const Color(0xFFDB2777),
                label: '回复评论',
                current: m.repliedCount,
                target: 5,
              ),
              _conditionRow(
                icon: Icons.person_add_outlined,
                iconBg: const Color(0xFFE0F2FE),
                iconColor: const Color(0xFF0284C7),
                label: '新增粉丝',
                current: m.newFollowersCount,
                target: 5,
              ),
              _conditionRow(
                icon: Icons.favorite_border,
                iconBg: const Color(0xFFFEE2E2),
                iconColor: const Color(0xFFDC2626),
                label: '获赞 + 收藏',
                current: m.receivedLikesSavesCount,
                target: 20,
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _conditionRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required int current,
    required int target,
    bool isLast = false,
  }) {
    final isDone = current >= target;
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
          Text(
            '$current / $target',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDone ? const Color(0xFF86EFAC) : Colors.white38,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isDone
                  ? _green.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDone ? Icons.check : Icons.circle_outlined,
              size: 13,
              color: isDone ? const Color(0xFF86EFAC) : Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2：续费规则 ──────────────────────────────────────────────
  Widget _rulesTab() {
    const rules = [
      ('发布笔记', '≥ 2 篇', Icons.edit_note),
      ('点赞他人', '≥ 20 次', Icons.thumb_up_outlined),
      ('发表评论', '≥ 5 条', Icons.chat_bubble_outline),
      ('回复评论', '≥ 5 条', Icons.reply_outlined),
      ('新增粉丝', '≥ 5 人', Icons.person_add_outlined),
      ('获赞 + 收藏', '≥ 20', Icons.favorite_border),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '每月续期条件（满足任意 3 项）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '保持基本活跃就能续期，条件很宽松',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 14),
              ...rules.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(r.$3, size: 16, color: _cyan),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r.$1,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Text(
                        r.$2,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _cyan,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '结算方式',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '系统每月自动统计上一个自然月的活跃数据，满足任意 3 项即视为'
                '达标，达标后自动续期 1 个月 Pro Max 会员，不需要手动申请或'
                '续费。不满足条件的月份不会扣除已有会员时长，只是不再叠加'
                'Pro Max，到期后回落到之前的会员等级。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.7,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab 3：历史记录 ──────────────────────────────────────────────
  Widget _historyTab(AuroraProgress progress) {
    if (progress.history.isEmpty) {
      return Center(
        child: Text(
          '暂无历史记录',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: progress.history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final h = progress.history[i];
        return _glassCard(
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (h.isQualified ? _green : Colors.white).withValues(
                    alpha: h.isQualified ? 0.18 : 0.06,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  h.isQualified ? Icons.check_circle : Icons.remove_circle_outline,
                  size: 18,
                  color: h.isQualified ? const Color(0xFF86EFAC) : Colors.white38,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.yearMonth,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      h.isQualified
                          ? (h.renewedAt != null ? '已续期 · 满足 ${h.metConditions}/6 项' : '满足 ${h.metConditions}/6 项')
                          : '未满足条件 · ${h.metConditions}/6 项',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
