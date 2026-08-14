import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 创作设置——内容/互动/编辑器/小梦AI 四组偏好，全部用 SharedPreferences 本地
// 持久化（这些是「创作默认偏好」，非账号级服务端配置）。开关即存即生效于本地，
// 具体消费方（发布流程读默认可见性、编辑器读默认块类型/自动保存、小梦读语言）
// 后续按需接入，这里先做设置面板本身。
const _primary = AppColors.primary;

class CreatorSettingsScreen extends ConsumerStatefulWidget {
  const CreatorSettingsScreen({super.key});

  @override
  ConsumerState<CreatorSettingsScreen> createState() =>
      _CreatorSettingsScreenState();
}

class _CreatorSettingsScreenState extends ConsumerState<CreatorSettingsScreen> {
  bool _loading = true;

  // 内容
  String _visibility = 'public';
  bool _allowComment = true;
  bool _allowRepost = false;
  bool _allowDownload = true;
  // 互动
  bool _notifyComment = true;
  bool _notifyLike = true;
  bool _notifyFollow = true;
  // 编辑器
  String _autosave = '30s';
  String _defaultBlock = 'text';
  // Notebook「+ 添加 Cell」新建时的默认类型（跟发布块编辑器的 _defaultBlock
  // 是两套体系：这里是 cell 类型 python/markdown/sql/r/latex）
  String _notebookCell = 'python';
  bool _showPreview = true;
  // 小梦 AI
  String _aiLang = 'zh';
  String _aiCodeLang = 'python';
  bool _aiAutoSummary = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _visibility = p.getString('creator_visibility') ?? 'public';
      _allowComment = p.getBool('creator_allow_comment') ?? true;
      // 默认 true——跟后端 allow_repost 默认 1（允许）、发布 payload 的
      // 默认一致，避免"设置显示关但文章实际允许转载"的自相矛盾
      _allowRepost = p.getBool('creator_allow_repost') ?? true;
      _allowDownload = p.getBool('creator_allow_download') ?? true;
      _notifyComment = p.getBool('creator_notify_comment') ?? true;
      _notifyLike = p.getBool('creator_notify_like') ?? true;
      _notifyFollow = p.getBool('creator_notify_follow') ?? true;
      _autosave = p.getString('creator_autosave') ?? '30s';
      _defaultBlock = p.getString('creator_default_block') ?? 'text';
      _notebookCell = p.getString('notebook_default_cell') ?? 'python';
      _showPreview = p.getBool('creator_show_preview') ?? true;
      _aiLang = p.getString('creator_ai_lang') ?? 'zh';
      _aiCodeLang = p.getString('creator_ai_code_lang') ?? 'python';
      _aiAutoSummary = p.getBool('creator_ai_auto_summary') ?? false;
      _loading = false;
    });
  }

  Future<void> _save(String key, dynamic value) async {
    final p = await SharedPreferences.getInstance();
    if (value is bool) {
      await p.setBool(key, value);
    } else if (value is String) {
      await p.setString(key, value);
    }
  }

  // —————————————————————————————— 主题色
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark
      ? Theme.of(context).scaffoldBackgroundColor
      : const Color(0xFFFAFAF8);
  Color get _card => _isDark ? const Color(0xFF17171F) : Colors.white;
  Color get _border =>
      _isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFEDEDE9);
  Color get _ink => _isDark ? const Color(0xFFF0F2F8) : const Color(0xFF111111);
  Color get _muted =>
      _isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 18, color: _ink),
            onPressed: () => context.pop(),
          ),
          title: Text(
            '创作设置',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
            : ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 32),
                children: [
                  _sectionLabel('内容设置'),
                  _card_([
                    _selectRow(
                      iconBg: const Color(0xFFEEF0FF),
                      icon: Icons.visibility_outlined,
                      iconColor: _primary,
                      label: '文章默认可见性',
                      value: _visibilityLabel(),
                      onTap: _showVisibilitySheet,
                    ),
                    _toggleRow(
                      iconBg: const Color(0xFFEAF8F0),
                      icon: Icons.chat_bubble_outline,
                      iconColor: const Color(0xFF16A34A),
                      label: '允许评论',
                      value: _allowComment,
                      onChanged: (v) {
                        setState(() => _allowComment = v);
                        _save('creator_allow_comment', v);
                      },
                    ),
                    _toggleRow(
                      iconBg: const Color(0xFFFDF0DC),
                      icon: Icons.content_copy_outlined,
                      iconColor: const Color(0xFFD97706),
                      label: '允许转载',
                      value: _allowRepost,
                      onChanged: (v) {
                        setState(() => _allowRepost = v);
                        _save('creator_allow_repost', v);
                      },
                    ),
                    _toggleRow(
                      iconBg: const Color(0xFFEEF0FF),
                      icon: Icons.download_outlined,
                      iconColor: _primary,
                      label: '允许下载附件',
                      value: _allowDownload,
                      onChanged: (v) {
                        setState(() => _allowDownload = v);
                        _save('creator_allow_download', v);
                      },
                    ),
                  ]),

                  _sectionLabel('互动设置'),
                  _card_([
                    _toggleRow(
                      iconBg: const Color(0xFFEEF0FF),
                      icon: Icons.notifications_outlined,
                      iconColor: _primary,
                      label: '新评论通知',
                      value: _notifyComment,
                      onChanged: (v) {
                        setState(() => _notifyComment = v);
                        _save('creator_notify_comment', v);
                      },
                    ),
                    _toggleRow(
                      iconBg: const Color(0xFFEAF8F0),
                      icon: Icons.favorite_outline,
                      iconColor: const Color(0xFF16A34A),
                      label: '获赞通知',
                      value: _notifyLike,
                      onChanged: (v) {
                        setState(() => _notifyLike = v);
                        _save('creator_notify_like', v);
                      },
                    ),
                    _toggleRow(
                      iconBg: const Color(0xFFFDF0DC),
                      icon: Icons.person_add_outlined,
                      iconColor: const Color(0xFFD97706),
                      label: '新粉丝通知',
                      value: _notifyFollow,
                      onChanged: (v) {
                        setState(() => _notifyFollow = v);
                        _save('creator_notify_follow', v);
                      },
                    ),
                  ]),

                  _sectionLabel('编辑器设置'),
                  _card_([
                    _selectRow(
                      iconBg: const Color(0xFFEEF0FF),
                      icon: Icons.save_outlined,
                      iconColor: _primary,
                      label: '自动保存间隔',
                      value: _autosaveLabel(),
                      onTap: _showAutosaveSheet,
                    ),
                    _selectRow(
                      iconBg: const Color(0xFFEAF8F0),
                      icon: Icons.view_agenda_outlined,
                      iconColor: const Color(0xFF16A34A),
                      label: '默认内容块类型',
                      value: _blockLabel(),
                      onTap: _showDefaultBlockSheet,
                    ),
                    _selectRow(
                      iconBg: const Color(0xFFEAF1FB),
                      icon: Icons.terminal_outlined,
                      iconColor: const Color(0xFF3776AB),
                      label: 'Notebook 默认 Cell 类型',
                      value: _notebookCellLabel(),
                      onTap: _showNotebookCellSheet,
                    ),
                    _toggleRow(
                      iconBg: const Color(0xFFFDF0DC),
                      icon: Icons.preview_outlined,
                      iconColor: const Color(0xFFD97706),
                      label: '发布前显示预览',
                      value: _showPreview,
                      onChanged: (v) {
                        setState(() => _showPreview = v);
                        _save('creator_show_preview', v);
                      },
                    ),
                  ]),

                  _sectionLabel('小梦 AI 设置'),
                  _card_([
                    _selectRow(
                      iconBg: const Color(0xFFEEF0FF),
                      icon: Icons.auto_awesome_outlined,
                      iconColor: _primary,
                      label: 'AI 偏好语言',
                      value: _aiLangLabel(),
                      onTap: _showAiLangSheet,
                    ),
                    _selectRow(
                      iconBg: const Color(0xFFEAF8F0),
                      icon: Icons.code_outlined,
                      iconColor: const Color(0xFF16A34A),
                      label: 'AI 默认代码语言',
                      value: _codeLangLabel(),
                      onTap: _showCodeLangSheet,
                    ),
                    _toggleRow(
                      iconBg: const Color(0xFFFDF0DC),
                      icon: Icons.auto_fix_high_outlined,
                      iconColor: const Color(0xFFD97706),
                      label: '发布时 AI 自动摘要',
                      value: _aiAutoSummary,
                      onChanged: (v) {
                        setState(() => _aiAutoSummary = v);
                        _save('creator_ai_auto_summary', v);
                      },
                    ),
                  ]),
                ],
              ),
      ),
    );
  }

  // —————————————————————————————— 通用组件
  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 18, 14, 8),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: _muted,
      ),
    ),
  );

  Widget _card_(List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border, width: 0.5),
    ),
    child: Column(
      children: List.generate(children.length, (i) {
        return Column(
          children: [
            children[i],
            if (i < children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 60),
                child: Divider(height: 0.5, thickness: 0.5, color: _border),
              ),
          ],
        );
      }),
    ),
  );

  Widget _iconBox(Color iconBg, IconData icon, Color iconColor) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: _isDark ? iconColor.withValues(alpha: 0.16) : iconBg,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, size: 17, color: iconColor),
  );

  Widget _toggleRow({
    required Color iconBg,
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        _iconBox(iconBg, icon, iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 15, color: _ink)),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: _primary,
        ),
      ],
    ),
  );

  Widget _selectRow({
    required Color iconBg,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      child: Row(
        children: [
          _iconBox(iconBg, icon, iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 15, color: _ink)),
          ),
          Text(value, style: TextStyle(fontSize: 14, color: _muted)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: _muted),
        ],
      ),
    ),
  );

  // —————————————————————————————— Sheet 选择器
  void _showVisibilitySheet() => _showOptionSheet(
    title: '文章默认可见性',
    options: const [
      ('public', '公开', '所有人可见'),
      ('private', '仅自己可见', '只有你能看到，适合草稿存档'),
    ],
    current: _visibility,
    onSelect: (v) {
      setState(() => _visibility = v);
      _save('creator_visibility', v);
    },
  );

  void _showAutosaveSheet() => _showOptionSheet(
    title: '自动保存间隔',
    options: const [
      ('10s', '10 秒', null),
      ('30s', '30 秒', null),
      ('60s', '1 分钟', null),
      ('off', '关闭自动保存', null),
    ],
    current: _autosave,
    onSelect: (v) {
      setState(() => _autosave = v);
      _save('creator_autosave', v);
    },
  );

  void _showDefaultBlockSheet() => _showOptionSheet(
    title: '默认内容块类型',
    options: const [
      ('text', '文字块', null),
      ('heading', '标题块', null),
      ('code', '代码块', null),
      ('latex', 'LaTeX 块', null),
    ],
    current: _defaultBlock,
    onSelect: (v) {
      setState(() => _defaultBlock = v);
      _save('creator_default_block', v);
    },
  );

  void _showNotebookCellSheet() => _showOptionSheet(
    title: 'Notebook 默认 Cell 类型',
    options: const [
      ('python', 'Python', null),
      ('markdown', 'Markdown', null),
      ('sql', 'SQL', null),
      ('r', 'R', null),
      ('latex', 'LaTeX', null),
    ],
    current: _notebookCell,
    onSelect: (v) {
      setState(() => _notebookCell = v);
      _save('notebook_default_cell', v);
    },
  );

  void _showAiLangSheet() => _showOptionSheet(
    title: 'AI 偏好语言',
    options: const [
      ('zh', '中文', null),
      ('en', 'English', null),
      ('zh-en', '中英混合', null),
    ],
    current: _aiLang,
    onSelect: (v) {
      setState(() => _aiLang = v);
      _save('creator_ai_lang', v);
    },
  );

  void _showCodeLangSheet() => _showOptionSheet(
    title: 'AI 默认代码语言',
    options: const [
      ('python', 'Python', null),
      ('javascript', 'JavaScript', null),
      ('sql', 'SQL', null),
      ('r', 'R', null),
    ],
    current: _aiCodeLang,
    onSelect: (v) {
      setState(() => _aiCodeLang = v);
      _save('creator_ai_code_lang', v);
    },
  );

  // 通用底部选择弹层：标题 + 选项列表（选中打勾），可带副标题说明
  void _showOptionSheet({
    required String title,
    required List<(String, String, String?)> options,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
              ...options.map((opt) {
                final selected = current == opt.$1;
                return InkWell(
                  onTap: () {
                    onSelect(opt.$1);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: _border, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                opt.$2,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: selected ? _primary : _ink,
                                ),
                              ),
                              if (opt.$3 != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  opt.$3!,
                                  style: TextStyle(fontSize: 12, color: _muted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (selected)
                          const Icon(Icons.check, size: 18, color: _primary),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // —————————————————————————————— 值 → 展示文案
  String _visibilityLabel() => _visibility == 'private' ? '仅自己可见' : '公开';

  String _autosaveLabel() {
    switch (_autosave) {
      case '10s':
        return '10 秒';
      case '60s':
        return '1 分钟';
      case 'off':
        return '关闭';
      default:
        return '30 秒';
    }
  }

  String _blockLabel() {
    switch (_defaultBlock) {
      case 'heading':
        return '标题';
      case 'code':
        return '代码';
      case 'latex':
        return 'LaTeX';
      default:
        return '文字';
    }
  }

  String _notebookCellLabel() {
    switch (_notebookCell) {
      case 'markdown':
        return 'Markdown';
      case 'sql':
        return 'SQL';
      case 'r':
        return 'R';
      case 'latex':
        return 'LaTeX';
      default:
        return 'Python';
    }
  }

  String _aiLangLabel() {
    switch (_aiLang) {
      case 'en':
        return 'English';
      case 'zh-en':
        return '中英混合';
      default:
        return '中文';
    }
  }

  String _codeLangLabel() {
    switch (_aiCodeLang) {
      case 'javascript':
        return 'JavaScript';
      case 'sql':
        return 'SQL';
      case 'r':
        return 'R';
      default:
        return 'Python';
    }
  }
}
