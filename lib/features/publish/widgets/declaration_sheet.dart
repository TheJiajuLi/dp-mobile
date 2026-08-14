import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

const _primary = AppColors.primary;

// 发布前的「原创声明」确认 Sheet：勾选同意后「确认并发布」才激活，勾选即
// 记录签署时间戳展示。真正的签署落库（SharedPreferences + payload）由调用
// 方在 onConfirmed 里处理——这个组件只负责展示和勾选交互
class DeclarationSheet extends StatefulWidget {
  // 勾选并点「确认并发布」后回调；调用方在里面保存签署记录、pop、继续发布
  final Future<void> Function() onConfirmed;
  const DeclarationSheet({super.key, required this.onConfirmed});

  @override
  State<DeclarationSheet> createState() => _DeclarationSheetState();
}

class _DeclarationSheetState extends State<DeclarationSheet> {
  bool _agreed = false;
  DateTime? _signedAt;
  bool _submitting = false;

  static const _clauses = [
    '本文章为本人原创内容，未在其他平台发布或抄袭他人作品',
    '文章中引用的内容已注明来源，不存在侵权情况',
    '本人对所发布内容的真实性和合法性负责',
    '授权极梦平台在保留署名的前提下展示和传播本文章',
  ];

  String _fmt(DateTime t) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${p(t.month)}/${p(t.day)} '
        '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  Future<void> _confirm() async {
    if (!_agreed || _submitting) return;
    setState(() => _submitting = true);
    // 父级会保存签署记录、pop 掉本 Sheet 并继续发布——之后本 State 已卸载，
    // 不再 setState
    await widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    final border = isDark
        ? Theme.of(context).dividerColor
        : const Color(0xFFEEEEEE);
    final cardBg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFF7F7F9);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF818CF8), AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '原创声明',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '发布前请确认以下内容',
              style: TextStyle(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border, width: 0.5),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _clauses.length; i++) ...[
                    if (i > 0) Divider(height: 0.5, color: border),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 7, right: 10),
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _clauses[i],
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _submitting
                  ? null
                  : () => setState(() {
                      _agreed = !_agreed;
                      _signedAt = _agreed ? DateTime.now() : null;
                    }),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 1),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _agreed ? _primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _agreed ? _primary : border,
                        width: 1.5,
                      ),
                    ),
                    child: _agreed
                        ? const Icon(Icons.check, size: 15, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 14, height: 1.5, color: ink),
                        children: const [
                          TextSpan(text: '我已阅读并同意上述声明，本文章为'),
                          TextSpan(
                            text: '原创内容',
                            style: TextStyle(
                              color: _primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_signedAt != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '签署时间：${_fmt(_signedAt!)}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('取消', style: TextStyle(color: muted)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: (_agreed && !_submitting) ? _confirm : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      disabledBackgroundColor: isDark
                          ? Colors.white12
                          : const Color(0xFFBBBBBB),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '确认并发布',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
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
