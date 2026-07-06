import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../auth/auth_service.dart';
import 'creator_center_screen.dart'
    show auroraNoteTarget, auroraLikesSavesTarget, auroraFollowerTarget;

const _bg = Color(0xFF0A0812);
const _glass = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
const _glassBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.1)
const _cyan = Color(0xFFA5F3FC);
const _primary = Color(0xFF6366F1);

// 极光计划详情页——固定深色星空背景，不跟随 ThemePreference。跟个人主页
// 头图区是同一类"刻意保留的局部深色例外"：这个页面卖的是"稀有感"，不该
// 被用户切成浅色主题冲淡掉
class AuroraScreen extends ConsumerStatefulWidget {
  const AuroraScreen({super.key});
  @override
  ConsumerState<AuroraScreen> createState() => _AuroraScreenState();
}

class _AuroraScreenState extends ConsumerState<AuroraScreen> {
  bool _loading = true;
  int _noteCount = 0;
  int _likesSaves = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/tutorials',
          queryParameters: {
            'author': user.username,
            'status': 'published',
            'limit': 50,
          },
        );
    if (!mounted) return;
    var likes = 0;
    var total = 0;
    if (res.success && res.data != null) {
      final list = (res.data['tutorials'] as List? ?? [])
          .where((j) => (j as Map)['user_id'] == user.id)
          .toList();
      total = (res.data['total'] as num?)?.toInt() ?? list.length;
      for (final j in list) {
        likes += ((j as Map)['likes'] as num?)?.toInt() ?? 0;
      }
    }
    setState(() {
      _noteCount = total;
      _likesSaves = likes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _cyan))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _backButton(),
                  const SizedBox(height: 12),
                  _hero(),
                  const SizedBox(height: 28),
                  _progressCard(user?.followerCount ?? 0),
                  const SizedBox(height: 16),
                  _benefitsCard(),
                  const SizedBox(height: 16),
                  _revenueCard(),
                  const SizedBox(height: 16),
                  _settlementCard(),
                  const SizedBox(height: 16),
                  _renewalCard(),
                  const SizedBox(height: 16),
                  _whyCard(),
                  const SizedBox(height: 16),
                  _earlyCreatorCard(),
                ],
              ),
      ),
    );
  }

  // ListView/SliverList 会给直接子项一个 cross axis 方向的 tight
  // constraint（min==max==视口宽度），Container 自己的 width:36 会被这个
  // tight constraint 顶掉变成撑满全宽——套一层 Align 让它只占内容尺寸,
  // 不然这个返回按钮会被拉成一条通栏
  Widget _backButton() => Align(
    alignment: Alignment.topLeft,
    child: GestureDetector(
      onTap: () => context.pop(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.arrow_back, size: 18, color: Colors.white),
      ),
    ),
  );

  Widget _hero() {
    return Stack(
      // Stack 默认 alignment 是 topStart——非 Positioned 的 Column 子项
      // 只会按自己最宽的子控件收缩宽度，然后贴在 Stack 左上角，Column 自己
      // 的 crossAxisAlignment.center 只能让图标/标题这些在这个收缩后的
      // 窄宽度内互相对齐，管不到整块内容相对全屏是不是居中——顶部两颗
      // 装饰光斑靠 Positioned 精确定位，不受这个 alignment 影响
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      children: [
        Positioned(left: -40, top: -20, child: _glow(_primary, 160)),
        Positioned(right: -30, top: 20, child: _glow(_cyan, 100)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _glassBorder),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '极光创作者计划',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'AURORA CREATOR PROGRAM',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '稀有、美丽、值得追寻——认真创作，极梦为你发光',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0)],
      ),
    ),
  );

  Widget _glassCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _progressCard(int followers) {
    return _glassCard(
      title: '我的申请进度',
      child: Column(
        children: [
          _progressRow('已发布笔记', _noteCount, auroraNoteTarget, '篇'),
          const SizedBox(height: 16),
          _progressRow('累计获赞/收藏', _likesSaves, auroraLikesSavesTarget, ''),
          const SizedBox(height: 16),
          _progressRow('粉丝数', followers, auroraFollowerTarget, '人'),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '认真创作两三个月就能达成，继续加油 ✨',
              style: TextStyle(fontSize: 12, color: _cyan),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressRow(String label, int value, int target, String unit) {
    final ratio = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$value',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text: ' / $target$unit',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation(_cyan),
          ),
        ),
      ],
    );
  }

  Widget _benefitsCard() {
    final items = [
      (
        Icons.workspace_premium,
        const Color(0xFF6366F1),
        '免费 Pro 会员',
        '价值 ¥39/月，5GB存储、AI功能、视频/音频块全解锁，不花一分钱',
      ),
      (
        Icons.shield_outlined,
        const Color(0xFFCA8A04),
        '创作者专属标识',
        '主页金色「创作者」badge，评论区也有标识，增加可信度',
      ),
      (
        Icons.attach_money,
        const Color(0xFF16A34A),
        '流量分成资格',
        '内容浏览量直接转化收益，看的人越多赚得越多',
      ),
      (
        Icons.rocket_launch_outlined,
        const Color(0xFF8B5CF6),
        '新功能优先体验',
        '平台新功能创作者优先内测，第一个用到好东西',
      ),
    ];
    return _glassCard(
      title: '加入后权益',
      child: Column(
        children: items
            .map(
              (it) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: it.$2.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(it.$1, color: it.$2, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            it.$3,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            it.$4,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _revenueCard() {
    return _glassCard(
      title: '流量分成制度',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
                children: const [
                  TextSpan(text: '分成池来源\n每月从会员订阅收入中拿出 '),
                  TextSpan(
                    text: '15–20%',
                    style: TextStyle(color: _cyan, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' 作为创作者基金，每月固定时间结算，规则透明公开'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '质量加权规则',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _weightTag('浏览量', '×1', const Color(0xFF6366F1))),
              const SizedBox(width: 8),
              Expanded(child: _weightTag('评论', '×2', const Color(0xFFEC4899))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _weightTag('点赞', '×3', const Color(0xFF16A34A))),
              const SizedBox(width: 8),
              Expanded(child: _weightTag('分享', '×4', const Color(0xFFEA580C))),
            ],
          ),
          const SizedBox(height: 8),
          _weightTag('收藏', '×5', const Color(0xFFCA8A04), sub: '最高权重'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '领域加权：稀缺领域（生命科学、宇宙物理）比泛话题内容权重更高\n'
              '时效加权：新内容前30天权重 ×1.5，持续产生流量的内容有持续收益',
              style: TextStyle(fontSize: 12, height: 1.6, color: _cyan),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '举个例子（月基金池 ¥10,000）',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF86EFAC),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '浏览 5,000 × 1 = 5,000\n'
                  '点赞 200 × 3 = 600\n'
                  '收藏 80 × 5 = 400\n'
                  '评论 30 × 2 = 60',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: Colors.white70,
                  ),
                ),
                Divider(height: 20, color: Colors.white24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '加权积分 = 6,060 分',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    Text(
                      '当月 ≈ ¥101',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF86EFAC),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightTag(String label, String weight, Color color, {String? sub}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
              if (sub != null) ...[
                const SizedBox(width: 6),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
          Text(
            weight,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settlementCard() {
    final rows = [
      (Icons.calendar_today_outlined, '每月1日结算上月收益'),
      (Icons.account_balance_wallet_outlined, '满 ¥50 可提现，支持微信/支付宝/银行卡'),
      (Icons.percent, '平台收取 10% 手续费，1-3 工作日到账'),
    ];
    return _glassCard(
      title: '结算规则',
      child: Column(
        children: rows
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(r.$1, size: 16, color: _cyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.$2,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _renewalCard() {
    const conditions = [
      '发布笔记 ≥ 2篇',
      '点赞他人 ≥ 20次',
      '发表评论 ≥ 5条',
      '回复评论 ≥ 5条',
      '新增粉丝 ≥ 5人',
      '获赞/收藏 ≥ 20',
    ];
    return _glassCard(
      title: '每月续期条件（满足任意3项）',
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.6,
            children: conditions
                .map(
                  (c) => Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      c,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          Text(
            '保持活跃就能续期，条件很宽松',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _whyCard() {
    const items = [
      '门槛低，10篇笔记就能申请',
      'Pro 会员直接免费，实实在在',
      '规则透明，积分可查，质量内容比水文值钱',
      '专为科学/数据/编程创作者设计',
      'Notebook+AI 工具让创作更高效',
    ];
    return _glassCard(
      title: '为什么选极梦',
      child: Column(
        children: items
            .map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _earlyCreatorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primary.withValues(alpha: 0.25), const Color(0xFF1A1040)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '先进来的人，赚得最多',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _cyan,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '目前极梦平台早期，创作者竞争少。现在积累的内容会持续产生收益——平台成长，分成池同步增大。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
