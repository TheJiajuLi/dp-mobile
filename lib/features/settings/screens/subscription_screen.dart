import 'dart:async';
import '../../../core/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../shared/widgets/app_toast.dart';
import '../../auth/auth_service.dart';
import '../../messages/utils/message_avatar.dart';
import '../../subscription/purchase_service.dart';
import '../providers/storage_provider.dart';

typedef _Feature = (IconData icon, String title, String subtitle);
typedef _Section = (String title, List<_Feature>);

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

enum _Plan { pro, proMax, aurora }

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  static const _primary = AppColors.primary;
  // Pro Max 的品牌辅色——跟 Pro 的靛紫区分开，参考图里 Pro Max 全程用
  // 一个偏洋红的紫色（按钮/图标/边框），不是简单复用 _primary
  static const _proMaxAccent = Color(0xFF9B5DE5);
  static const _green = AppColors.success;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _ink =>
      Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1A1A1A);
  Color get _muted => _isDark ? Colors.white54 : const Color(0xFF999999);
  // 浅色统一成首页/极索/创作者中心那种偏米白的 #FAFAF8，不再是冷灰白的
  // 全局 scaffoldBackgroundColor——页面背景暖一档，卡片保持纯白，两者
  // 拉开一点差才有"卡片浮在页面上"的层次感，深色维持主题背景
  Color get _bg =>
      _isDark ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFFFAFAF8);
  Color get _cardBg => Theme.of(context).cardColor;
  Color get _border => Theme.of(context).dividerColor;
  Color get _solidFill => _isDark ? _primary : const Color(0xFF1A1A1A);
  Color get _subtleBg =>
      _isDark ? Theme.of(context).dividerColor : const Color(0xFFF5F5F2);
  // 卡片投影——只在浅色下给，深色沿用"描边而非投影"分层的既有约定
  // （跟 settings_row.dart 的 SettingsGroup 同一份取值）
  List<BoxShadow>? get _cardShadow => _isDark
      ? null
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  _Plan _tab = _Plan.pro;
  String _currentPlan = 'free';
  bool _loading = true;

  static const _proSections = <_Section>[
    (
      '创作增强',
      [
        (Icons.storage_outlined, '云端存储 200MB → 5GB', '音视频/高清图全部能传'),
        (Icons.audiotrack_outlined, '附加音频块', '发布内容可附带音频文件'),
        (Icons.attach_file, '文件附件（PDF/数据集）', '读者需 Pro 才能下载'),
      ],
    ),
    (
      'Notebook 阅读权限',
      [(Icons.play_circle_outline, '阅读他人笔记时可运行代码', '免费读者只能看代码，不能交互运行')],
    ),
    (
      '聊天增强',
      [
        (Icons.code, '聊天发送代码片段', 'Code Block 支持'),
        (Icons.functions, '聊天发送 LaTeX 公式', '数学表达无障碍'),
        (Icons.videocam_outlined, '聊天发送音频/视频文件', '媒体文件私信支持'),
      ],
    ),
    (
      '小梦 AI',
      [
        (Icons.auto_awesome, '小梦 AI 摘要生成', '一键生成文章摘要'),
        (Icons.image_outlined, '小梦 AI 封面生成', '每日 20 次'),
        (Icons.face_retouching_natural, '小梦 AI 头像生成', '定制专属头像'),
      ],
    ),
    (
      '身份与体验',
      [
        (Icons.verified_outlined, '专属 Pro 角标', '评论区+主页显示'),
        (Icons.text_fields, '评论专属字体', '区别于普通用户视觉风格'),
        (Icons.ios_share, '内容一键导出 PDF', '任意教程/笔记打印导出'),
      ],
    ),
  ];

  static const _proMaxExclusive = <_Feature>[
    (Icons.storage_outlined, '云端存储 5GB → 20GB', '海量文件无压力'),
    (Icons.auto_awesome, 'AI 生成次数无限', '不再有每日限制'),
    (Icons.videocam_outlined, '视频大小上限 100MB', '高清视频随意传'),
    (Icons.rocket_launch_outlined, '早期新功能优先体验', '第一个用到好东西'),
  ];

  // 极光创作者计划的门槛/权益/续期条件都是真实数字——跟战略计划书里
  // 「种子用户策略」/「用户旅程设计」一致，不是随手编的占位值
  static const _auroraRequirements = <_Feature>[
    (Icons.description_outlined, '已发布笔记', '≥ 10 篇'),
    (Icons.favorite_border, '累计获赞/收藏', '≥ 100'),
    (Icons.people_outline, '粉丝数', '≥ 50 人'),
  ];

  static const _auroraBenefits = <_Feature>[
    (Icons.workspace_premium_outlined, '免费获得 Pro 所有权益', '价值 ¥39/月，不花一分钱'),
    (Icons.attach_money, '流量分成资格', '内容浏览直接转化收益，质量加权'),
    (Icons.shield_outlined, '金色「创作者」专属标识', '主页 + 评论区全部显示'),
    (Icons.rocket_launch_outlined, '新功能优先体验', '平台内测资格，第一个用到好东西'),
  ];

  static const _auroraRenewal = <(IconData, String)>[
    (Icons.description_outlined, '发布笔记 ≥ 2 篇'),
    (Icons.thumb_up_outlined, '点赞他人 ≥ 20 次'),
    (Icons.chat_bubble_outline, '发表评论 ≥ 5 条'),
    (Icons.reply_outlined, '回复评论 ≥ 5 条'),
    (Icons.person_add_outlined, '新增粉丝 ≥ 5 人'),
    (Icons.favorite_border, '获赞收藏 ≥ 20'),
  ];

  StreamSubscription<PurchaseResult>? _resultSub;

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
    // 订阅购买结果流：成功/恢复弹提示并刷新当前套餐，失败/取消give反馈
    _resultSub = ref
        .read(purchaseServiceProvider)
        .results
        .listen(_onPurchaseResult);
  }

  @override
  void dispose() {
    _resultSub?.cancel();
    super.dispose();
  }

  void _onPurchaseResult(PurchaseResult r) {
    if (!mounted) return;
    switch (r.outcome) {
      case PurchaseOutcome.success:
      case PurchaseOutcome.restored:
        _snack(
          r.outcome == PurchaseOutcome.restored ? '已恢复购买' : '订阅成功，欢迎加入！',
          ok: true,
        );
        // 后端已更新 membership，刷新页面顶部"当前套餐"展示
        ref.invalidate(storageUsageProvider);
        _loadCurrentPlan();
      case PurchaseOutcome.canceled:
        break; // 用户主动取消，不打扰
      case PurchaseOutcome.error:
        _snack('购买失败：${r.message ?? '请稍后重试'}');
    }
  }

  void _snack(String msg, {bool ok = false}) {
    if (!mounted) return;
    showAppToast(context, msg, ok: ok);
  }

  Future<void> _loadCurrentPlan() async {
    try {
      final storage = await ref.read(storageUsageProvider.future);
      setState(() {
        _currentPlan = storage['membership'] as String? ?? 'free';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                      children: [
                        _buildCurrentPlanCard(),
                        const SizedBox(height: 18),
                        _buildTabSwitch(),
                        const SizedBox(height: 20),
                        switch (_tab) {
                          _Plan.pro => _buildProTab(),
                          _Plan.proMax => _buildProMaxTab(),
                          _Plan.aurora => _buildAuroraTab(),
                        },
                        // 极光计划是创作者激励、不是内购，不显示购买页脚
                        if (_tab != _Plan.aurora) _buildPurchaseFooter(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.arrow_back_ios_new, size: 15, color: _ink),
            ),
          ),
          Expanded(
            child: Text(
              '会员中心',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(width: 34),
        ],
      ),
    );
  }

  Widget _buildCurrentPlanCard() {
    final planNames = {'free': '免费版', 'pro': 'Pro 会员', 'pro_max': 'Pro Max 会员'};
    final planStorage = {'free': '200 MB', 'pro': '5 GB', 'pro_max': '20 GB'};
    // 之前是一个通用人形图标占位——这里其实拿得到真实登录用户，直接用
    // 真头像，跟应用其它地方（消息/好友列表）同一套渲染规则
    final user = ref.watch(currentUserProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 0.5),
        boxShadow: _cardShadow,
      ),
      child: Row(
        children: [
          user == null
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _subtleBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.person_outline, size: 20, color: _muted),
                )
              : buildMessageAvatar(user.avatar, user.username, radius: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前方案', style: TextStyle(fontSize: 11, color: _muted)),
              const SizedBox(height: 2),
              Text(
                planNames[_currentPlan] ?? '免费版',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('存储空间', style: TextStyle(fontSize: 11, color: _muted)),
              const SizedBox(height: 2),
              Text(
                planStorage[_currentPlan] ?? '200 MB',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: _subtleBg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _tabBtn('Pro', _Plan.pro, _primary),
          _tabBtn('Pro Max', _Plan.proMax, _proMaxAccent),
          _tabBtn('极光计划', _Plan.aurora, _primary),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, _Plan plan, Color accent) {
    final active = _tab == plan;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = plan),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? (_isDark ? accent : _cardBg) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? (_isDark ? Colors.white : _ink) : _muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _planHeaderCard({
    required String name,
    required Color accent,
    required String price,
    String? annualNote,
    required String ctaLabel,
    required bool isCurrent,
    required VoidCallback onCta,
    bool busy = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1),
        boxShadow: _cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      price,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(' /月', style: TextStyle(fontSize: 13, color: _muted)),
                  ],
                ),
                if (annualNote != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    annualNote,
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ],
            ),
          ),
          _headerCta(ctaLabel, accent, isCurrent, onCta, busy),
        ],
      ),
    );
  }

  Widget _headerCta(
    String label,
    Color accent,
    bool isCurrent,
    VoidCallback onCta,
    bool busy,
  ) {
    if (busy) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: _isDark ? accent : _solidFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }
    if (isCurrent) {
      return OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: _border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text('当前套餐', style: TextStyle(fontSize: 13, color: _muted)),
      );
    }
    return GestureDetector(
      onTap: onCta,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _isDark ? accent : _solidFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              '7天免费试用',
              style: TextStyle(fontSize: 9, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {Color? color}) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color ?? _muted,
      ),
    ),
  );

  Widget _featureCard(
    List<_Feature> features, {
    Color? bg,
    Color? border,
    Color? titleColor,
    Color? subtitleColor,
    Color? iconBg,
    Color? iconColor,
    Color? checkColor,
    Color? dividerColor,
  }) {
    final rows = <Widget>[];
    for (var i = 0; i < features.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 0.5, color: dividerColor ?? _border));
      }
      final f = features[i];
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg ?? _subtleBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(f.$1, size: 17, color: iconColor ?? _muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.$2,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      f.$3,
                      style: TextStyle(
                        fontSize: 12,
                        color: subtitleColor ?? _muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.check, size: 20, color: checkColor ?? _green),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: bg ?? _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? _border, width: 0.5),
        boxShadow: _cardShadow,
      ),
      child: Column(children: rows),
    );
  }

  Widget _buildProTab() {
    // watch 让商品加载完/购买中状态变化时本页重建，价格与按钮转圈才跟得上
    final svc = ref.watch(purchaseServiceProvider);
    final monthly = svc.productById(kProProductMonthly);
    final yearly = svc.productById(kProProductYearly);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _planHeaderCard(
          name: '极梦 PRO',
          accent: _primary,
          // 有真实商品就用 App Store 本地化价格，没有则退回兜底文案
          price: monthly?.price ?? '¥39',
          annualNote: yearly != null
              ? '按年付 ${yearly.price}/年'
              : '按年付享 8 折 · ¥374/年',
          ctaLabel: '立即订阅',
          isCurrent: _currentPlan == 'pro',
          busy:
              svc.isPurchasing(kProProductMonthly) ||
              svc.isPurchasing(kProProductYearly),
          onCta: () => _handleUpgrade('pro'),
        ),
        const SizedBox(height: 22),
        for (final section in _proSections) ...[
          _sectionTitle(section.$1),
          _featureCard(section.$2),
          const SizedBox(height: 20),
        ],
        _sectionTitle('存储空间对比'),
        _buildStorageCompare(),
      ],
    );
  }

  Widget _buildProMaxTab() {
    final svc = ref.watch(purchaseServiceProvider);
    final monthly = svc.productById(kProMaxProductMonthly);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _planHeaderCard(
          name: '极梦 PRO MAX',
          accent: _proMaxAccent,
          price: monthly?.price ?? '¥69',
          ctaLabel: '立即订阅',
          isCurrent: _currentPlan == 'pro_max',
          busy: svc.isPurchasing(kProMaxProductMonthly),
          onCta: () => _handleUpgrade('pro_max'),
        ),
        const SizedBox(height: 22),
        // "专属升级"这块无论明暗主题都固定用深色卡片——顶级套餐的
        // "尊贵感"是设计上刻意的，不需要跟随主题反色
        _sectionTitle('Pro Max 专属升级', color: Colors.white54),
        _featureCard(
          _proMaxExclusive,
          bg: const Color(0xFF16131F),
          border: _proMaxAccent.withValues(alpha: 0.35),
          titleColor: Colors.white,
          subtitleColor: Colors.white54,
          iconBg: _proMaxAccent.withValues(alpha: 0.18),
          iconColor: _proMaxAccent,
          checkColor: _proMaxAccent,
          dividerColor: Colors.white12,
        ),
        const SizedBox(height: 20),
        _sectionTitle('包含全部 Pro 权益'),
        for (final section in _proSections) ...[
          _featureCard(section.$2),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildAuroraTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 极光计划的入口卡无论明暗主题都固定用深靛紫渐变——呼应个人主页
        // 默认封面的极地星空基调，是这个计划自己的品牌色，不跟主题走
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF241D52), Color(0xFF3A2E7A)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '极光创作者计划',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'AURORA CREATOR PROGRAM',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 0.5,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      '免费获得',
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                '满足条件后系统自动通过，免费获得 Pro 全部权益 + 流量分成资格',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _sectionTitle('申请条件（同时满足）'),
        _requirementCard(_auroraRequirements),
        const SizedBox(height: 20),
        _sectionTitle('极光专属权益'),
        _featureCardNoCheck(_auroraBenefits),
        const SizedBox(height: 20),
        _sectionTitle('每月续期（满足任意 3 项）'),
        _renewalGrid(),
      ],
    );
  }

  Widget _requirementCard(List<_Feature> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) rows.add(Divider(height: 0.5, color: _border));
      final f = items[i];
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(f.$1, size: 18, color: _primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(f.$2, style: TextStyle(fontSize: 14, color: _ink)),
              ),
              Text(
                f.$3,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 0.5),
        boxShadow: _cardShadow,
      ),
      child: Column(children: rows),
    );
  }

  Widget _featureCardNoCheck(List<_Feature> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) rows.add(Divider(height: 0.5, color: _border));
      final f = items[i];
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _subtleBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(f.$1, size: 17, color: _primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.$2,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(f.$3, style: TextStyle(fontSize: 12, color: _muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 0.5),
        boxShadow: _cardShadow,
      ),
      child: Column(children: rows),
    );
  }

  // 跟上面"极光专属权益"统一视觉语言——白底卡片 + 浅色圆角图标底 + 主色
  // 图标，而不是原来一整块纯色（_subtleBg）平铺的无图标文字块
  Widget _renewalGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.2,
      children: _auroraRenewal
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: _subtleBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.$1, size: 14, color: _primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: _ink),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildStorageCompare() {
    final rows = <(String, String, double, Color)>[
      ('免费版', '200 MB', 0.08, _muted),
      ('Pro', '5 GB', 0.28, _primary),
      ('Pro Max', '20 GB', 1.0, _solidFill),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 0.5),
        boxShadow: _cardShadow,
      ),
      child: Column(
        children: rows
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          r.$1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: r.$4,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          r.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: r.$3,
                        minHeight: 6,
                        backgroundColor: _subtleBg,
                        valueColor: AlwaysStoppedAnimation(r.$4),
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

  // 发起订阅：Pro 有月付/年付两个商品 → 弹周期选择；Pro Max 只有月付 → 直接买。
  // 商品没加载出来（ASC 未配置/设备不支持）时给出可读提示，不闷掉。
  void _handleUpgrade(String planKey) {
    final svc = ref.read(purchaseServiceProvider);
    if (!svc.isAvailable) {
      _snack('当前设备暂不支持内购');
      return;
    }
    if (planKey == 'pro') {
      final monthly = svc.productById(kProProductMonthly);
      final yearly = svc.productById(kProProductYearly);
      if (monthly == null && yearly == null) {
        _snack('商品信息加载中，请稍后重试');
        return;
      }
      if (monthly != null && yearly != null) {
        _showPeriodPicker(svc, monthly, yearly);
      } else {
        svc.buy((monthly ?? yearly)!);
      }
    } else {
      final m = svc.productById(kProMaxProductMonthly);
      if (m == null) {
        _snack('商品信息加载中，请稍后重试');
        return;
      }
      svc.buy(m);
    }
  }

  void _showPeriodPicker(
    PurchaseService svc,
    ProductDetails monthly,
    ProductDetails yearly,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              '选择订阅周期',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 16),
            _periodOption(ctx, svc, monthly, '按月付', null),
            const SizedBox(height: 10),
            _periodOption(ctx, svc, yearly, '按年付', '更省'),
          ],
        ),
      ),
    );
  }

  Widget _periodOption(
    BuildContext ctx,
    PurchaseService svc,
    ProductDetails product,
    String label,
    String? badge,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        svc.buy(product);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _subtleBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              product.price,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 底部：恢复购买 + 法务链接。订阅类应用上架要求这两样都要有。
  Widget _buildPurchaseFooter() {
    return Column(
      children: [
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () async {
            await ref.read(purchaseServiceProvider).restore();
            _snack('正在恢复购买…');
          },
          child: const Text(
            '恢复购买',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _primary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GestureDetector(
              onTap: () => context.push('/settings/terms'),
              child: Text(
                '用户协议',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
            Text('  ·  ', style: TextStyle(fontSize: 12, color: _muted)),
            GestureDetector(
              onTap: () => context.push('/settings/privacy-policy'),
              child: Text(
                '隐私政策',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '订阅到期自动续费，可随时在 App Store 订阅管理中取消',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: _muted, height: 1.5),
        ),
      ],
    );
  }
}
