import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/auth_service.dart';
import '../services/notebook_service.dart';

const _primary = Color(0xFF6366F1);

class NotebookHomeScreen extends ConsumerStatefulWidget {
  const NotebookHomeScreen({super.key});
  @override
  ConsumerState<NotebookHomeScreen> createState() => _State();
}

class _State extends ConsumerState<NotebookHomeScreen> {
  List<Map<String, dynamic>> _recent = [];
  NotebookService? _svc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final user = ref.read(currentUserProvider);
    _svc = NotebookService(user?.id ?? 'guest');
    final recent = await _svc!.getRecentList();
    setState(() { _recent = recent; _loading = false; });
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return '早上好 👋';
    if (h < 18) return '下午好 👋';
    return '晚上好 👋';
  }

  void _showNewSheet() {
    final ctrl = TextEditingController();
    String type = 'python';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, 12, 20,
            MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
              margin: const EdgeInsets.only(bottom: 16)),
            const Text('新建 Notebook',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('选择类型，开始你的分析之旅',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl, autofocus: true,
              decoration: InputDecoration(
                hintText: 'Notebook 名称',
                filled: true, fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12)),
            ),
            const SizedBox(height: 14),
            Row(children: [
              for (final t in [
                ('python', 'Python', Icons.code),
                ('latex', 'LaTeX', Icons.functions),
                ('mixed', '混合', Icons.layers),
              ]) Expanded(child: GestureDetector(
                onTap: () => setState(() => type = t.$1),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: type == t.$1
                      ? _primary.withValues(alpha: 0.1) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: type == t.$1 ? _primary : Colors.transparent)),
                  child: Column(children: [
                    Icon(t.$3,
                      color: type == t.$1 ? _primary : Colors.grey, size: 20),
                    const SizedBox(height: 4),
                    Text(t.$2, style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: type == t.$1 ? _primary : Colors.grey[600])),
                  ]),
                ),
              )),
            ]),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final name = ctrl.text.trim();
                  if (name.isEmpty) return;
                  final nb = await _svc!.create(name, type);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) context.push('/notebook/${nb.id}');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary, elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
                child: const Text('创建',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: Colors.white)),
              )),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: SafeArea(child: Column(children: [
        // 顶部栏
        Container(color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Row(children: [
                Icon(Icons.arrow_back_ios, size: 16, color: _primary),
                Text('返回', style: TextStyle(fontSize: 13, color: _primary)),
              ]),
            ),
            const SizedBox(width: 8),
            const Text('极梦 Notebook',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            GestureDetector(onTap: _showNewSheet,
              child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _primary,
                  borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.add, color: Colors.white, size: 20))),
          ])),

        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
            onRefresh: _init,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Hero
                Container(width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade100)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_greeting(),
                      style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                    const SizedBox(height: 4),
                    const Text('从哪里开始？',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _showNewSheet,
                        icon: const Icon(Icons.add, color: Colors.white, size: 18),
                        label: const Text('新建 Notebook',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                            color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary, elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))))),
                  ])),

                // 最近
                if (_recent.isNotEmpty) ...[
                  _SectionHeader(title: '最近打开', action: '全部', onAction: () {}),
                  const SizedBox(height: 10),
                  ..._recent.map((nb) => _RecentCard(nb: nb,
                    onTap: () => context.push('/notebook/${nb['id']}'),
                    onDelete: () async {
                      await _svc!.delete(nb['id']);
                      _init();
                    })),
                  const SizedBox(height: 20),
                ],

                // 模板
                const _SectionHeader(title: '模板'),
                const SizedBox(height: 10),
                SizedBox(height: 110,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final t in [
                      ('数据分析', Icons.bar_chart, const Color(0xFF6366F1), const Color(0xFFEEF0FF), 'python'),
                      ('机器学习', Icons.psychology, const Color(0xFF16A34A), const Color(0xFFE8F8F0), 'python'),
                      ('数学推导', Icons.functions, const Color(0xFFC026D3), const Color(0xFFFDF0F8), 'latex'),
                      ('可视化', Icons.show_chart, const Color(0xFF2563EB), const Color(0xFFE6F1FB), 'python'),
                    ]) _TemplateCard(
                      name: t.$1, icon: t.$2, color: t.$3, bg: t.$4,
                      onTap: () async {
                        final nb = await _svc!.create(t.$1, t.$5);
                        if (context.mounted) context.push('/notebook/${nb.id}');
                      }),
                  ])),
                const SizedBox(height: 80),
              ]),
            ),
          )),
      ])),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _SectionHeader({required this.title, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    const Spacer(),
    if (action != null) GestureDetector(onTap: onAction,
      child: Text(action!, style: const TextStyle(fontSize: 14, color: _primary))),
  ]);
}

class _RecentCard extends StatelessWidget {
  final Map<String, dynamic> nb;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _RecentCard({required this.nb, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colors = [
      [const Color(0xFFEEF0FF), const Color(0xFF6366F1)],
      [const Color(0xFFE8F8F0), const Color(0xFF16A34A)],
      [const Color(0xFFFFF7E6), const Color(0xFFD97706)],
      [const Color(0xFFFDF0F8), const Color(0xFFC026D3)],
      [const Color(0xFFE6F1FB), const Color(0xFF2563EB)],
    ];
    final icons = [Icons.bar_chart, Icons.functions, Icons.psychology,
      Icons.code, Icons.table_chart];
    final idx = (nb['id'] as String).hashCode.abs() % 5;
    final lang = nb['lang'] ?? 'python';
    final badgeColor = {'python': _primary, 'latex': const Color(0xFFC026D3),
      'mixed': const Color(0xFF16A34A)}[lang] ?? _primary;
    final updatedAt = nb['updatedAt'] as int? ?? 0;
    final diff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - updatedAt;
    final timeStr = diff < 3600 ? '${diff ~/ 60}分钟前'
      : diff < 86400 ? '${diff ~/ 3600}小时前' : '${diff ~/ 86400}天前';

    return Dismissible(
      key: Key(nb['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(color: Colors.red,
          borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade100)),
          child: Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(color: colors[idx][0],
                borderRadius: BorderRadius.circular(12)),
              child: Icon(icons[idx], color: colors[idx][1], size: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nb['name'] ?? '',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    lang == 'latex' ? 'LaTeX' : lang == 'mixed' ? '混合' : 'Python',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                      color: badgeColor))),
                const SizedBox(width: 8),
                Text('${nb['cellCount'] ?? 0} cells',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                const SizedBox(width: 8),
                Text(timeStr,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ]),
            ])),
            const Icon(Icons.chevron_right, color: Color(0xFFC7C7CC), size: 20),
          ]),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color, bg;
  final VoidCallback onTap;
  const _TemplateCard({required this.name, required this.icon,
    required this.color, required this.bg, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 95, height: 110,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(color: bg,
            borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 22)),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w600), textAlign: TextAlign.center),
      ])),
  );
}
