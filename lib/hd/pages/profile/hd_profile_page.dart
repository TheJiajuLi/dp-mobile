import 'package:flutter/material.dart';

class HdProfilePage extends StatefulWidget {
  const HdProfilePage({super.key});
  @override
  State<HdProfilePage> createState() => _State();
}

class _State extends State<HdProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  final _tutorials = [
    {
      'title': '泊松分布完全指南',
      'bg': const Color(0xFF0D0D1A),
      'icon': Icons.code,
      'ic': const Color(0xFF818CF8),
      'domain': '编程',
      'views': '1.2k',
      'likes': '89',
      'status': '已发布',
    },
    {
      'title': 'Symlog Scale可视化详解',
      'bg': const Color(0xFFFEF3C7),
      'icon': Icons.functions,
      'ic': const Color(0xFFD97706),
      'domain': '数学',
      'views': '432',
      'likes': '31',
      'status': '已发布',
    },
    {
      'title': 'RFM客户分层模型完整Python实现',
      'bg': const Color(0xFFE8F8F0),
      'icon': Icons.show_chart,
      'ic': const Color(0xFF16A34A),
      'domain': '编程',
      'views': '891',
      'likes': '67',
      'status': '已发布',
    },
    {
      'title': '机器学习入门：线性回归从零实现',
      'bg': const Color(0xFFF5F5F2),
      'icon': Icons.description_outlined,
      'ic': const Color(0xFF999999),
      'domain': '编程',
      'views': '—',
      'likes': '',
      'status': '草稿',
    },
    {
      'title': '贝叶斯统计入门',
      'bg': const Color(0xFFEEF0FF),
      'icon': Icons.scatter_plot,
      'ic': const Color(0xFF6366F1),
      'domain': '数学',
      'views': '312',
      'likes': '28',
      'status': '已发布',
    },
    {
      'title': '时间序列预测ARIMA实战',
      'bg': const Color(0xFF0F0F2A),
      'icon': Icons.blur_circular,
      'ic': const Color(0xFFA78BFA),
      'domain': '天体',
      'views': '567',
      'likes': '44',
      'status': '已发布',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左栏
        SizedBox(
          width: 280,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: Color(0xFFE5E5EA), width: 0.5),
              ),
            ),
            child: _buildLeft(),
          ),
        ),
        // 右栏
        Expanded(child: _buildRight()),
      ],
    );
  }

  Widget _buildLeft() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 极光头像
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFF59E0B),
                      Color(0xFF818CF8),
                      Color(0xFF4ADE80),
                      Color(0xFFF59E0B),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      '兔',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE5E5EA),
                      width: 0.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    size: 13,
                    color: Color(0xFF555555),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '大兔兔',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            '@dreamingpolar',
            style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
          ),
          const SizedBox(height: 12),
          // 元老徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0E2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '★',
                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 14),
                ),
                SizedBox(width: 7),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '元老创作者',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'FOUNDING CREATOR',
                      style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFF818CF8),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Pro Max
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspace_premium,
                  size: 13,
                  color: Color(0xFF6366F1),
                ),
                SizedBox(width: 4),
                Text(
                  'Pro Max 会员',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6366F1)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '热爱数据分析和数学建模，专注于用代码讲清楚复杂概念。极梦元老创作者 #001。',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF555555),
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // 统计
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('12', '内容'),
              _stat('234', '粉丝'),
              _stat('56', '关注'),
              _stat('3.2k', '获赞'),
            ],
          ),
          const SizedBox(height: 16),
          // 标签
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: ['数据分析', 'Python', '数学建模', '统计学']
                .map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: const Color(0xFFE5E5EA),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          _info(Icons.location_on_outlined, '英国 · 曼彻斯特'),
          const SizedBox(height: 7),
          _info(Icons.calendar_today_outlined, '加入于 2026年7月'),
          const SizedBox(height: 7),
          _info(Icons.language, 'dreamingpolar.com', link: true),
        ],
      ),
    );
  }

  Widget _stat(String n, String l) => Column(
    children: [
      Text(
        n,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A1A1A),
        ),
      ),
      const SizedBox(height: 2),
      Text(l, style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
    ],
  );

  Widget _info(IconData icon, String text, {bool link = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: const Color(0xFF999999)),
      const SizedBox(width: 5),
      Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: link ? const Color(0xFF6366F1) : const Color(0xFF777777),
        ),
      ),
    ],
  );

  Widget _buildRight() {
    return Column(
      children: [
        // Tab栏
        Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E5EA), width: 0.5),
            ),
          ),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            labelColor: const Color(0xFF1A1A1A),
            unselectedLabelColor: const Color(0xFF999999),
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            indicatorColor: const Color(0xFF6366F1),
            indicatorWeight: 2,
            tabs: const [
              Tab(text: '教程 12'),
              Tab(text: '专栏 3'),
              Tab(text: '收藏 47'),
              Tab(text: '创作数据'),
              Tab(text: '极光计划'),
            ],
          ),
        ),
        // 内容
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildGrid(),
              _empty('专栏'),
              _empty('收藏'),
              _empty('创作数据'),
              _empty('极光计划'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: _tutorials.length,
      itemBuilder: (ctx, i) {
        final t = _tutorials[i];
        final isPub = t['status'] == '已发布';
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF0F0F0), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: t['bg'] as Color,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(
                          t['icon'] as IconData,
                          color: t['ic'] as Color,
                          size: 36,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t['domain'] as String,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 信息
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t['title'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A1A1A),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if ((t['views'] as String).isNotEmpty) ...[
                          Icon(
                            Icons.remove_red_eye,
                            size: 11,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            t['views'] as String,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.favorite_border,
                            size: 11,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            t['likes'] as String,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[400],
                            ),
                          ),
                        ] else
                          Text(
                            '—',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[400],
                            ),
                          ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isPub
                                ? const Color(0xFFE8F8F0)
                                : const Color(0xFFFFF7E6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t['status'] as String,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: isPub
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFD97706),
                            ),
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
      },
    );
  }

  Widget _empty(String label) => Center(
    child: Text(
      label,
      style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
    ),
  );
}
