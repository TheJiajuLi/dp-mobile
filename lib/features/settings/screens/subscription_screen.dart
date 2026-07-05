import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/storage_provider.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  static const _primary = Color(0xFF6366F1);
  static const _ink = Color(0xFF1A1A1A);
  static const _bg = Color(0xFFFAFAF8);
  static const _muted = Color(0xFF999999);
  static const _border = Color(0xFFF0F0F0);

  bool _isYearly = true;
  String _currentPlan = 'free';
  bool _loading = true;

  // 价格配置
  static const _prices = {
    'pro': {'monthly': 58, 'yearly': 39, 'yearlyTotal': 468},
    'promax': {'monthly': 148, 'yearly': 99, 'yearlyTotal': 1188},
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
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

  String _priceLabel(String plan) {
    final p = _prices[plan]!;
    final amount = _isYearly ? p['yearly'] : p['monthly'];
    return '¥$amount';
  }

  String _priceSubLabel(String plan) {
    final p = _prices[plan]!;
    if (_isYearly) {
      return '按年付 ¥${p['yearlyTotal']}';
    }
    return '按月付款';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: _ink),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '会员订阅',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: _border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _buildCurrentPlan(),
                _buildPeriodToggle(),
                _buildPlans(),
                _buildCompareTable(),
                _buildFaq(),
                _buildFooter(),
              ],
            ),
    );
  }

  // 当前套餐
  Widget _buildCurrentPlan() {
    final planNames = {'free': '免费版', 'pro': 'Pro 会员', 'pro_max': 'Pro Max 会员'};
    final planStorage = {
      'free': '200MB 存储',
      'pro': '5GB 存储',
      'pro_max': '20GB 存储',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person_outline, size: 20, color: _muted),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当前套餐', style: TextStyle(fontSize: 11, color: _muted)),
              const SizedBox(height: 2),
              Text(
                planNames[_currentPlan] ?? '免费版',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _ink,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            planStorage[_currentPlan] ?? '200MB 存储',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ),
    );
  }

  // 周期切换
  Widget _buildPeriodToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '选择周期',
            style: TextStyle(fontSize: 11, color: _muted, letterSpacing: .04),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F2),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                _periodBtn('按月', false),
                _periodBtn('按年', true, badge: '省33%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodBtn(String label, bool isYearly, {String? badge}) {
    final active = _isYearly == isYearly;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isYearly = isYearly),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active ? Border.all(color: _border, width: 0.5) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? _ink : _muted,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _ink,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 三个套餐卡片
  Widget _buildPlans() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          _buildPlanCard(
            planKey: 'free',
            name: '免费版',
            price: '¥0',
            priceSub: '永久免费',
            desc: '适合轻度使用，探索极梦基础功能',
            features: const [
              (true, '发布教程和笔记'),
              (true, '200MB 云端存储'),
              (true, 'Notebook 基础运行'),
              (false, '小梦 AI 生成功能'),
              (false, '文件 / 音频 / 视频块'),
            ],
            ctaLabel: _currentPlan == 'free' ? '当前套餐' : '降级到免费',
            ctaStyle: 'outline',
            featured: false,
          ),
          const SizedBox(height: 10),
          _buildPlanCard(
            planKey: 'pro',
            name: 'Pro',
            price: _priceLabel('pro'),
            priceSub: _priceSubLabel('pro'),
            desc: '为认真创作的你，解锁全部核心能力',
            features: const [
              (true, '5GB 云端存储'),
              (true, '小梦 AI 每日 20 次生成'),
              (true, '文件 / 音频块（≤5MB）'),
              (true, '视频块（≤50MB）'),
              (true, 'AI 封面 / 头像生成'),
            ],
            ctaLabel: _currentPlan == 'pro' ? '当前套餐' : '升级到 Pro',
            ctaStyle: _currentPlan == 'pro' ? 'outline' : 'black',
            featured: true,
            popularBadge: '最受欢迎',
          ),
          const SizedBox(height: 10),
          _buildPlanCard(
            planKey: 'pro_max',
            name: 'Pro Max',
            price: _priceLabel('promax'),
            priceSub: _priceSubLabel('promax'),
            desc: '创作者、研究者、重度用户的终极选择',
            features: const [
              (true, '20GB 云端存储'),
              (true, '小梦 AI 无限次生成'),
              (true, '视频块（≤100MB）'),
              (true, '优先客服支持'),
              (true, '早期新功能抢先体验'),
            ],
            ctaLabel: _currentPlan == 'pro_max' ? '当前套餐' : '升级到 Pro Max',
            ctaStyle: _currentPlan == 'pro_max' ? 'outline' : 'black',
            featured: false,
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required String planKey,
    required String name,
    required String price,
    required String priceSub,
    required String desc,
    required List<(bool, String)> features,
    required String ctaLabel,
    required String ctaStyle,
    bool featured = false,
    String? popularBadge,
  }) {
    final isCurrent = _currentPlan == planKey;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: featured ? _ink : _border,
              width: featured ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 名称+价格
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: planKey == 'pro' ? _primary : _ink,
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            price,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          if (planKey != 'free')
                            const Text(
                              '/月',
                              style: TextStyle(fontSize: 12, color: _muted),
                            ),
                        ],
                      ),
                      Text(
                        priceSub,
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 12,
                  color: _muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              // 功能列表
              ...features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: f.$1
                              ? (planKey == 'pro' ? _primary : _ink)
                              : const Color(0xFFF5F5F2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          f.$1 ? Icons.check : Icons.close,
                          size: 10,
                          color: f.$1 ? Colors.white : const Color(0xFFCCCCCC),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        f.$2,
                        style: TextStyle(
                          fontSize: 13,
                          color: f.$1 ? _ink : const Color(0xFFBBBBBB),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // CTA按钮
              SizedBox(
                width: double.infinity,
                child: _buildCtaButton(ctaLabel, ctaStyle, isCurrent, planKey),
              ),
            ],
          ),
        ),
        // 最受欢迎badge
        if (popularBadge != null)
          Positioned(
            top: -1,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: const BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Text(
                popularBadge,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCtaButton(
    String label,
    String style,
    bool isCurrent,
    String planKey,
  ) {
    if (style == 'outline' || isCurrent) {
      return OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFD0D0D0)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: _muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return ElevatedButton(
      onPressed: () => _handleUpgrade(planKey),
      style: ElevatedButton.styleFrom(
        backgroundColor: _ink,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _handleUpgrade(String planKey) {
    // 支付功能即将上线
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
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
            const Icon(Icons.credit_card_outlined, size: 40, color: _muted),
            const SizedBox(height: 16),
            const Text(
              '支付功能即将上线',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '微信支付 / 支付宝即将接入\n敬请期待',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _muted, height: 1.6),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ink,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  '我知道了',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 功能对比表
  Widget _buildCompareTable() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '功能对比',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.5),
            ),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
              },
              children: [
                // 表头
                TableRow(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5),
                    ),
                  ),
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('', style: TextStyle(fontSize: 11)),
                    ),
                    _tableHeader('免费'),
                    _tableHeader('Pro', accent: true),
                    _tableHeader('Max'),
                  ],
                ),
                // 数据行
                _compareRow('云端存储', '200MB', '5GB', '20GB'),
                _compareRow('AI生成', '-', '20次/天', '无限'),
                _compareRow('视频块', '-', '50MB', '100MB'),
                _compareBoolRow('音频块', false, true, true, last: false),
                _compareBoolRow('优先客服', false, false, true, last: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, {bool accent = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: accent ? _primary : _muted,
      ),
    ),
  );

  TableRow _compareRow(
    String label,
    String v1,
    String v2,
    String v3,
  ) => TableRow(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFF5F5F2), width: 0.5)),
    ),
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
      ),
      _tableCell(v1),
      _tableCell(v2, accent: true),
      _tableCell(v3),
    ],
  );

  TableRow _compareBoolRow(
    String label,
    bool v1,
    bool v2,
    bool v3, {
    bool last = false,
  }) => TableRow(
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(
              bottom: BorderSide(color: Color(0xFFF5F5F2), width: 0.5),
            ),
    ),
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
      ),
      _tableBool(v1),
      _tableBool(v2, accent: true),
      _tableBool(v3),
    ],
  );

  Widget _tableCell(String val, {bool accent = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      val,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: accent ? _primary : _ink,
      ),
    ),
  );

  Widget _tableBool(bool val, {bool accent = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Icon(
      val ? Icons.check : Icons.remove,
      size: 16,
      color: val ? (accent ? _primary : _ink) : const Color(0xFFDDDDDD),
    ),
  );

  // FAQ
  Widget _buildFaq() {
    final faqs = [
      ('随时可以取消吗？', '可以。订阅期间取消，到期前仍可使用会员功能，到期后自动降级为免费版，已有数据不会丢失。'),
      ('按年和按月有什么区别？', '按年付款相当于打67折，一次支付全年费用。按月更灵活，但总价偏高。'),
      ('超出存储配额怎么办？', '超出后无法继续上传新文件，但已有内容不受影响。可前往「云端存储」删除文件，或升级套餐扩大配额。'),
      ('支持哪些支付方式？', '即将支持微信支付、支付宝。目前处于内测阶段，敬请期待。'),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '常见问题',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.5),
            ),
            child: Column(
              children: faqs
                  .asMap()
                  .entries
                  .map(
                    (e) => _FaqItem(
                      question: e.value.$1,
                      answer: e.value.$2,
                      isLast: e.key == faqs.length - 1,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            const Text(
              '订阅服务由极梦（Dreaming Polar）提供',
              style: TextStyle(fontSize: 12, color: _muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {},
                  child: const Text(
                    '服务条款',
                    style: TextStyle(fontSize: 12, color: _primary),
                  ),
                ),
                const Text(
                  '  ·  ',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
                GestureDetector(
                  onTap: () {},
                  child: const Text(
                    '隐私政策',
                    style: TextStyle(fontSize: 12, color: _primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// FAQ展开收起组件
class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;
  final bool isLast;

  const _FaqItem({
    required this.question,
    required this.answer,
    required this.isLast,
  });

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.question,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 18,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Text(
              widget.answer,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF999999),
                height: 1.6,
              ),
            ),
          ),
        if (!widget.isLast)
          const Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 14,
            endIndent: 14,
            color: Color(0xFFF0F0F0),
          ),
      ],
    );
  }
}
