import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/auth_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/greeting.dart';
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

  void _showNewSheet() {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController();
    String type = 'python';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, 12, 20,
            MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
              margin: const EdgeInsets.only(bottom: 16)),
            Text(l10n.newNotebook,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(l10n.chooseTypeSubtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl, autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.notebookNameHint,
                filled: true, fillColor: Theme.of(ctx).inputDecorationTheme.fillColor,
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
                ('mixed', l10n.langMixed, Icons.layers),
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
                child: Text(l10n.create,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: Colors.white)),
              )),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        // 顶部栏
        Container(color: Theme.of(context).cardColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Row(children: [
                const Icon(Icons.arrow_back_ios, size: 16, color: _primary),
                Text(l10n.back, style: const TextStyle(fontSize: 13, color: _primary)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(l10n.appNotebookTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                  decoration: BoxDecoration(color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Theme.of(context).dividerColor)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${greetingText(context)} 👋',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                    const SizedBox(height: 4),
                    Text(l10n.whereToStart,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _showNewSheet,
                        icon: const Icon(Icons.add, color: Colors.white, size: 18),
                        label: Text(l10n.newNotebook,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                            color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary, elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))))),
                  ])),

                // 最近
                if (_recent.isNotEmpty) ...[
                  _SectionHeader(title: l10n.recentlyOpened, action: l10n.viewAll, onAction: () {}),
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
                _SectionHeader(title: l10n.templates),
                const SizedBox(height: 10),
                SizedBox(height: 122,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final t in [
                      (l10n.tagDataAnalysis, Icons.bar_chart, const Color(0xFF6366F1), const Color(0xFFEEF0FF), 'python'),
                      (l10n.tagMachineLearning, Icons.psychology, const Color(0xFF16A34A), const Color(0xFFE8F8F0), 'python'),
                      (l10n.templateMathDerivation, Icons.functions, const Color(0xFFC026D3), const Color(0xFFFDF0F8), 'latex'),
                      (l10n.tagVisualization, Icons.show_chart, const Color(0xFF2563EB), const Color(0xFFE6F1FB), 'python'),
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
    final l10n = AppLocalizations.of(context)!;
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
    final timeStr = diff < 3600 ? l10n.timeMinutesAgo(diff ~/ 60)
      : diff < 86400 ? l10n.timeHoursAgo(diff ~/ 3600) : l10n.timeDaysAgo(diff ~/ 86400);

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
          decoration: BoxDecoration(color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor)),
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
                    lang == 'latex' ? 'LaTeX' : lang == 'mixed' ? l10n.langMixed : 'Python',
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
    // 英文文案（如"Machine Learning"）比中文长不少，固定95宽+不限行数的
    // Text 在英文下会把卡片撑到底部溢出——加宽一点，并且把文字限制在2行
    // 内、超出省略号收尾。上一版只加了maxLines/ellipsis没提高度，2行文字
    // 实测还是比留给它的34px高2px放不下——这次把卡片和外层横向ListView
    // 的SizedBox都从110提到122，留出实打实的余量，不再卡在临界值上
    child: Container(width: 108, height: 122,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(color: bg,
            borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 22)),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w600), textAlign: TextAlign.center,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      ])),
  );
}
