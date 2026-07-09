import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// 提问领域配色——提问 Sheet 的领域选择跟热门提问卡片的领域标签共用同一套
Color jisuoDomainColor(String d) => switch (d) {
  '编程开发' => const Color(0xFF6366F1),
  '数学' => const Color(0xFFD97706),
  '天体物理' => const Color(0xFF8B5CF6),
  '经济' => const Color(0xFF16A34A),
  '生命科学' => const Color(0xFFDC2626),
  _ => const Color(0xFF6B7280),
};

Color jisuoDomainBg(String d) => switch (d) {
  '编程开发' => const Color(0xFFEEF0FF),
  '数学' => const Color(0xFFFEF3C7),
  '天体物理' => const Color(0xFFF3E8FF),
  '经济' => const Color(0xFFDCFCE7),
  '生命科学' => const Color(0xFFFEE2E2),
  _ => const Color(0xFFF3F4F6),
};

class JisuoScreen extends StatefulWidget {
  const JisuoScreen({super.key});

  @override
  State<JisuoScreen> createState() => _JisuoScreenState();
}

class _JisuoScreenState extends State<JisuoScreen> {
  final _inputCtrl = TextEditingController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _placeholderSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showAskSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AskSheet(onPost: _postQuestion),
    );
  }

  // 后端目前没有 /auth/questions 这个接口——极索提问功能整体还是纯前端
  // mock，这里先原地假装发布成功，真正接后端时再替换成真实 POST
  Future<void> _postQuestion(String text, String domain, bool anon) async {
    await Future.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildTopBar()),
            SliverToBoxAdapter(child: _buildXiaoMeng()),
            SliverToBoxAdapter(child: _buildAppsSection()),
            SliverToBoxAdapter(child: _buildJmDivider('社区精选')),
            SliverToBoxAdapter(child: _buildHotQuestions()),
            SliverToBoxAdapter(child: _buildJmDivider('为你推荐')),
            SliverToBoxAdapter(child: _buildPickedContent()),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '极索',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              Text(
                '探索 · 提问 · 发现',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            color: Colors.grey[500],
            onPressed: () => _placeholderSnack('搜索历史即将上线'),
          ),
          GestureDetector(
            onTap: _showAskSheet,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXiaoMeng() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0A1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1230),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: _buildAuroraIcon(18)),
              ),
              const SizedBox(width: 8),
              const Text(
                '小梦',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '极梦 AI · 优先引用社区优质内容',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _openXiaoMeng,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '问问小梦...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _openXiaoMeng,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6366F1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_upward,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  ['泊松分布怎么理解？', 'Python数据清洗', '黑洞是什么', '线性回归推导']
                      .map(
                        (t) => GestureDetector(
                          onTap: () => _askXiaoMeng(t),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              t,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuroraIcon(double size) {
    return CustomPaint(
      size: Size(size, size * 0.85),
      painter: _AuroraIconPainter(),
    );
  }

  Widget _buildAppsSection() {
    // Notebook 是这个 App 里唯一真实存在的入口，首页去掉工具宫格之后
    // 在 iPhone 上一度没地方点进去了，这里补上；其余几个跟原来首页
    // 宫格是不同的一套（按学科分类，不是按工具类型），后端/页面都还没有，
    // 统一走"即将上线"占位
    final apps = [
      {
        'name': 'Notebook',
        'icon': Icons.code,
        'bg': const Color(0xFFEEF0FF),
        'color': const Color(0xFF6366F1),
        'route': '/notebook',
      },
      {
        'name': '数学建模',
        'icon': Icons.functions,
        'bg': const Color(0xFFFEF3C7),
        'color': const Color(0xFFD97706),
      },
      {
        'name': '可视化',
        'icon': Icons.bar_chart,
        'bg': const Color(0xFFDCFCE7),
        'color': const Color(0xFF16A34A),
      },
      {
        'name': '金融分析',
        'icon': Icons.currency_yen,
        'bg': const Color(0xFFFEE2E2),
        'color': const Color(0xFFDC2626),
      },
      {
        'name': '机器学习',
        'icon': Icons.psychology,
        'bg': const Color(0xFFF3E8FF),
        'color': const Color(0xFF8B5CF6),
      },
      {
        'name': '物理模拟',
        'icon': Icons.science,
        'bg': const Color(0xFFE0F2FE),
        'color': const Color(0xFF0284C7),
      },
      {
        'name': '生物信息',
        'icon': Icons.biotech,
        'bg': const Color(0xFFFFF7ED),
        'color': const Color(0xFFEA580C),
      },
      {
        'name': '更多',
        'icon': Icons.grid_view,
        'bg': null,
        'color': Colors.grey,
      },
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(
            children: [
              const Text(
                '应用',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _placeholderSnack('应用中心即将上线'),
                child: const Text(
                  '全部',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6366F1)),
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: apps.length,
          itemBuilder: (ctx, i) {
            final app = apps[i];
            final route = app['route'] as String?;
            return GestureDetector(
              onTap: () => route != null
                  ? context.push(route)
                  : _placeholderSnack('即将上线，敬请期待'),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: app['bg'] as Color? ?? Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      app['icon'] as IconData,
                      size: 26,
                      color: app['color'] as Color,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    app['name'] as String,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildJmDivider(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.grey.withValues(alpha: 0.15),
              thickness: 0.5,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  _buildAuroraIcon(12),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.grey.withValues(alpha: 0.15),
              thickness: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // 头像叠加用的固定配色——跟专家名单那套调色板保持一致
  static const _avatarColors = [
    Color(0xFF6366F1),
    Color(0xFFD97706),
    Color(0xFF16A34A),
  ];

  // 热门提问——目前后端没有"提问/回答"这套数据模型，先用静态占位展示
  // 布局效果，等后端有对应接口再接（跟精选内容一样，不是我漏接，是
  // 这次任务范围明确写了"先用静态数据，后续接API"）
  Widget _buildHotQuestions() {
    final questions = [
      {
        'domain': '编程开发',
        'text': '泊松分布和正态分布在实际建模时如何选择？有没有经验法则？',
        'answer_count': 3,
        'view_count': 234,
        'invited_count': 2,
      },
      {
        'domain': '数学',
        'text': '黎曼积分和勒贝格积分的本质区别是什么？',
        'answer_count': 2,
        'view_count': 189,
        'invited_count': 3,
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '热门提问',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey[400],
              letterSpacing: .04,
            ),
          ),
          const SizedBox(height: 8),
          ...questions.map((q) => _hotQuestionCard(q)),
        ],
      ),
    );
  }

  Widget _hotQuestionCard(Map<String, dynamic> q) {
    final domain = q['domain'] as String;
    final answerCount = q['answer_count'] as int;
    final viewCount = q['view_count'] as int;
    final invitedCount = q['invited_count'] as int;
    final avatarCount = answerCount < 3 ? answerCount : 3;

    return GestureDetector(
      onTap: () => _placeholderSnack('问题详情即将上线'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: jisuoDomainBg(domain),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    domain,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: jisuoDomainColor(domain),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    q['text'] as String,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: avatarCount * 14.0 + 4,
                  height: 20,
                  child: Stack(
                    children: List.generate(
                      avatarCount,
                      (i) => Positioned(
                        left: i * 14.0,
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 8,
                            backgroundColor: _avatarColors[i % _avatarColors.length],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$answerCount 个回答',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                const SizedBox(width: 8),
                Icon(Icons.remove_red_eye_outlined, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 3),
                Text(
                  '$viewCount',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                const Spacer(),
                if (invitedCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.phone_in_talk, size: 10, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          '已邀请 $invitedCount 位专家',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 精选内容——同样是静态占位（见上面热门提问的注释），后续接
  // tutorialsProvider 真实数据
  Widget _buildPickedContent() {
    final items = [
      {
        'title': '微积分基本定理的几何直觉与严格证明',
        'meta': '数学星人 · 856浏览 · 数学',
        'emoji': '📐',
        'bg': const Color(0xFFFEF3C7),
      },
      {
        'title': 'RFM客户分层模型：从零实现到业务落地',
        'meta': '数据老王 · 891浏览 · 编程',
        'emoji': '📊',
        'bg': const Color(0xFFEEF0FF),
      },
      {
        'title': 'CRISPR基因编辑：2026年最新突破全解读',
        'meta': '生科研究员 · 445浏览 · 生命科学',
        'emoji': '🧬',
        'bg': const Color(0xFFDCFCE7),
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: i < items.length - 1
                    ? BorderSide(
                        color: Colors.grey.withValues(alpha: 0.1),
                        width: 0.5,
                      )
                    : BorderSide.none,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['title'] as String,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['meta'] as String,
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 72,
                  height: 56,
                  decoration: BoxDecoration(
                    color: item['bg'] as Color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      item['emoji'] as String,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ARIA 页面目前本身也还是"开发中"占位屏，但它是这个功能真实存在的
  // 路由，比单纯弹一个toast更诚实——用户点进去至少能看到"这个功能在做了"
  // 而不是点了没反应
  void _openXiaoMeng() => context.push('/aria');

  // AriaScreen 目前是无参数的占位屏，还没有能接收预填问题的能力，先跳
  // 转过去，预填问题这部分等 ARIA 真正有输入框了再接
  void _askXiaoMeng(String question) => context.push('/aria');
}

// 极光Icon画笔
class _AuroraIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paints = [
      Paint()
        ..color = const Color(0xFF6366F1).withValues(alpha: 0.5)
        ..strokeWidth = size.width * 0.08
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
      Paint()
        ..color = const Color(0xFF818CF8).withValues(alpha: 0.8)
        ..strokeWidth = size.width * 0.08
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
      Paint()
        ..color = const Color(0xFF4ADE80)
        ..strokeWidth = size.width * 0.09
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    ];

    final offsets = [0.0, 0.1, 0.2];
    for (var i = 0; i < 3; i++) {
      final path = Path();
      final y0 = size.height * (0.7 + offsets[i]);
      final cp = Offset(size.width * 0.5, size.height * (0.1 + offsets[i]));
      path.moveTo(0, y0);
      path.quadraticBezierTo(cp.dx, cp.dy, size.width, y0);
      canvas.drawPath(path, paints[i]);
    }
  }

  @override
  bool shouldRepaint(_AuroraIconPainter oldDelegate) => false;
}

class _AskSheet extends StatefulWidget {
  final Future<void> Function(String text, String domain, bool anon) onPost;
  const _AskSheet({required this.onPost});

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _ctrl = TextEditingController();
  String? _domain;
  bool _anon = false;
  bool _posting = false;
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const _domains = ['编程开发', '数学', '天体物理', '经济', '生命科学', '科普'];

  Future<void> _submit() async {
    if (_ctrl.text.trim().length < 10 || _domain == null) return;
    setState(() => _posting = true);
    await widget.onPost(_ctrl.text.trim(), _domain!, _anon);
    if (!mounted) return;
    setState(() {
      _posting = false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _done ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildForm() {
    final canPost = _ctrl.text.trim().length >= 10 && _domain != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Text(
                '提问',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, size: 16, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '好问题能吸引领域专家作答，尽量描述清楚背景',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ctrl,
            maxLines: 4,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            autofocus: true,
            decoration: InputDecoration(
              hintText: '你想问什么？',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 16),
              border: InputBorder.none,
              counterStyle: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
            style: const TextStyle(fontSize: 16, height: 1.6),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '所属领域',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[400],
                  letterSpacing: .04,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _domains.map((d) {
                  final on = _domain == d;
                  return GestureDetector(
                    onTap: () => setState(() => _domain = d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: on ? jisuoDomainBg(d) : Colors.grey[50],
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: on ? jisuoDomainColor(d) : Colors.grey[200]!,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: on ? FontWeight.w500 : FontWeight.normal,
                          color: on ? jisuoDomainColor(d) : Colors.grey[600],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '匿名提问',
                      style: TextStyle(fontSize: 13, color: Color(0xFF374151)),
                    ),
                    Text(
                      '其他用户看不到你的名字',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _anon,
                onChanged: (v) => setState(() => _anon = v),
                activeThumbColor: const Color(0xFF6366F1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: canPost && !_posting ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: Colors.grey[200],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _posting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '发布提问',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final experts = [
      {
        'name': '大兔兔',
        'color': 0xFF6366F1,
        'role': '编程开发 · 12篇相关内容',
        'aurora': true,
      },
      {
        'name': '数学星人',
        'color': 0xFFD97706,
        'role': '数学 · 8篇相关内容',
        'aurora': false,
      },
      {
        'name': '生科研究员',
        'color': 0xFF16A34A,
        'role': '生命科学 · 5篇相关内容',
        'aurora': false,
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF0FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 30,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '提问已发布',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '极索已根据问题领域\n自动邀请以下专家为你解答',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[400], height: 1.6),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0E2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚡  已邀请 3 位领域专家',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(height: 10),
                ...experts.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Color(e['color'] as int),
                          child: Text(
                            (e['name'] as String).substring(0, 1),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    e['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (e['aurora'] == true) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFF59E0B,
                                        ).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: const Text(
                                        '★ 极光',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: Color(0xFFF59E0B),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                e['role'] as String,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '好的，期待回答',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
