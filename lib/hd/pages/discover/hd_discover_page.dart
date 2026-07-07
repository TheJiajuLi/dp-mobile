import 'package:flutter/material.dart';

// Placeholder数据
const _kTutorials = [
  {
    'id': '1',
    'title': '泊松分布：从数学原理到Python实战',
    'author': '大兔兔',
    'domain': '编程',
    'views': '1.2k',
    'color': Color(0xFF0D0D1A),
    'icon': Icons.code,
    'iconColor': Color(0xFF818CF8),
    'desc': '泊松分布描述单位时间内独立随机事件发生次数的离散概率分布，在排队论、保险精算、物理学等领域有广泛应用。',
  },
  {
    'id': '2',
    'title': '微积分基本定理的几何直觉',
    'author': '数学星人',
    'domain': '数学',
    'views': '856',
    'color': Color(0xFFFEF3C7),
    'icon': Icons.functions,
    'iconColor': Color(0xFFD97706),
    'desc': '微积分基本定理建立了积分与导数的深刻联系，是整个微积分学科的核心。',
  },
  {
    'id': '3',
    'title': '黑洞的史瓦西半径意味着什么',
    'author': '宇宙观测员',
    'domain': '天体物理',
    'views': '2.3k',
    'color': Color(0xFF0F0F2A),
    'icon': Icons.blur_circular,
    'iconColor': Color(0xFFA78BFA),
    'desc': '史瓦西半径定义了黑洞事件视界的大小，是广义相对论最重要的预测之一。',
  },
  {
    'id': '4',
    'title': '2026年Q2宏观经济数据全面解读',
    'author': '经济观察家',
    'domain': '经济',
    'views': '634',
    'color': Color(0xFFE8F8F0),
    'icon': Icons.show_chart,
    'iconColor': Color(0xFF16A34A),
    'desc': '本季度GDP增速4.7%，CPI温和上涨，就业市场保持韧性，货币政策预期转向。',
  },
  {
    'id': '5',
    'title': 'CRISPR基因编辑2026最新进展',
    'author': '生科研究员',
    'domain': '生命科学',
    'views': '445',
    'color': Color(0xFFFEE2E2),
    'icon': Icons.biotech,
    'iconColor': Color(0xFFDC2626),
    'desc': 'CRISPR-Cas9技术在基因治疗领域取得重大突破，多项临床试验进入关键阶段。',
  },
  {
    'id': '6',
    'title': 'RFM客户分层模型完整实现',
    'author': '数据老王',
    'domain': '编程',
    'views': '891',
    'color': Color(0xFFEEF0FF),
    'icon': Icons.people_outline,
    'iconColor': Color(0xFF6366F1),
    'desc': 'RFM模型通过最近购买时间、购买频率、购买金额三个维度对客户进行精准分层。',
  },
];

const _kDomains = ['全部', '编程', '数学', '天体物理', '经济', '生命科学'];

class HdDiscoverPage extends StatefulWidget {
  const HdDiscoverPage({super.key});

  @override
  State<HdDiscoverPage> createState() => _HdDiscoverPageState();
}

class _HdDiscoverPageState extends State<HdDiscoverPage> {
  Map<String, dynamic>? _selected = _kTutorials.first;
  String _domain = '全部';

  List<Map<String, dynamic>> get _filtered {
    if (_domain == '全部') return _kTutorials;
    return _kTutorials.where((t) => t['domain'] == _domain).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 左栏：270px
        SizedBox(
          width: 270,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: Color(0xFFE5E5EA), width: 0.5),
              ),
            ),
            child: Column(
              children: [
                // 筛选chips
                _buildFilterBar(),
                // 列表
                Expanded(
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) => _buildListItem(_filtered[i]),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 右栏：预览
        Expanded(
          child: _selected != null ? _buildPreview(_selected!) : _buildEmpty(),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: _kDomains.map((d) {
          final on = _domain == d;
          return GestureDetector(
            onTap: () => setState(() => _domain = d),
            child: Container(
              margin: const EdgeInsets.only(right: 6, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: on ? const Color(0xFF6366F1) : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: on ? const Color(0xFF6366F1) : const Color(0xFFE5E5EA),
                  width: 0.5,
                ),
              ),
              child: Center(
                child: Text(
                  d,
                  style: TextStyle(
                    fontSize: 12,
                    color: on ? Colors.white : const Color(0xFF888888),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildListItem(Map<String, dynamic> t) {
    final selected = _selected?['id'] == t['id'];
    return GestureDetector(
      onTap: () => setState(() => _selected = t),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF0FF) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? const Color(0xFF6366F1) : Colors.transparent,
              width: 2.5,
            ),
            bottom: const BorderSide(color: Color(0xFFF0F0F0), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // 封面色块
            Container(
              width: 50,
              height: 40,
              decoration: BoxDecoration(
                color: t['color'] as Color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                t['icon'] as IconData,
                color: t['iconColor'] as Color,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t['title'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      color: const Color(0xFF1A1A1A),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${t['author']} · ${t['views']}浏览',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(Map<String, dynamic> t) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: t['color'] as Color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      // 底部渐变
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 标题
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t['title'] as String,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                t['domain'] as String,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 作者行
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6366F1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          (t['author'] as String)[0],
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['author'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          '${t['domain']} · ${t['views']}浏览',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // 阅读全文
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Text(
                              '阅读全文',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 10,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 分割线
                const Divider(color: Color(0xFFF0F0F0), height: 1),
                const SizedBox(height: 14),

                // 简介
                Text(
                  t['desc'] as String,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF555555),
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined, size: 44, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            '从左侧选择一篇内容开始阅读',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
