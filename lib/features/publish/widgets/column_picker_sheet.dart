import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/profile_refresh_signal.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../column/models/column_model.dart';

const _primary = AppColors.primary;

class ColumnPickerResult {
  final String? columnId;
  final String? columnName;
  const ColumnPickerResult(this.columnId, this.columnName);
}

enum ColumnSheetStep { list, create, success }

// 加入专栏 sheet——一个 StatefulWidget 里切三步（列表/新建表单/创建成功），
// 不是三个各自独立弹出的 dialog/sheet，靠 _step 切内容，高度跟着内容变。
// 单独抽成 ConsumerStatefulWidget（而不是塞进 PublishScreen 里一堆闭包）
// 是因为这几步各自都有自己的表单状态（颜色选择/名称/简介），放一起会很乱
class ColumnPickerSheet extends ConsumerStatefulWidget {
  final String? initialColumnId;
  const ColumnPickerSheet({super.key, this.initialColumnId});

  @override
  ConsumerState<ColumnPickerSheet> createState() => _ColumnPickerSheetState();
}

class _ColumnPickerSheetState extends ConsumerState<ColumnPickerSheet> {
  static const _coverColors = [
    AppColors.primary,
    Color(0xFFD97706),
    AppColors.success,
    Color(0xFFDC2626),
    Color(0xFF8B5CF6),
    Color(0xFF0284C7),
  ];
  // 专栏没有封面图时，图标/颜色按 id 第一个字符确定性地选一个——不是真的
  // 按"学科分类"分的（columns_table 压根没有 domain 这个字段），只是让
  // 没传封面的专栏在列表里看起来不是清一色一个图标
  static const _fallbackIcons = [
    Icons.code,
    Icons.functions,
    Icons.blur_circular,
    Icons.show_chart,
    Icons.biotech,
    Icons.library_books,
  ];

  ColumnSheetStep _step = ColumnSheetStep.list;
  bool _loading = true;
  String? _loadError;
  List<ColumnModel> _columns = [];
  String? _selectedId;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int _colorIndex = 0;
  bool _creating = false;
  String? _createdName;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialColumnId;
    _loadColumns();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadColumns() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final res = await ref.read(apiClientProvider).get('/auth/columns/mine');
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() {
        _loading = false;
        _loadError = res.message;
      });
      return;
    }
    final columns = ((res.data as Map)['columns'] as List? ?? [])
        .map((j) => ColumnModel.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    setState(() {
      _columns = columns;
      _loading = false;
    });
  }

  // 选已有专栏——勾选之后停一下再关（让用户看到真的选中了），不需要
  // 额外的"确认"按钮
  Future<void> _selectExisting(ColumnModel col) async {
    setState(() => _selectedId = col.id);
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    Navigator.pop(context, ColumnPickerResult(col.id, col.name));
  }

  Future<void> _createColumn() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    // 颜色只是这个创建表单自己的预览效果——columns_table 没有存颜色的
    // 字段，创建之后列表里显示的颜色还是走上面那套按id确定性选色的规则，
    // 不是这里挑的这个，创建接口也不接受这个字段
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/columns',
          data: {'name': name, 'description': _descCtrl.text.trim()},
        );
    if (!mounted) return;
    setState(() => _creating = false);
    if (!res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
      return;
    }
    notifyProfileShouldRefresh(ref);
    final newId = (res.data as Map?)?['id'] as String?;
    setState(() {
      _selectedId = newId;
      _createdName = name;
      _step = ColumnSheetStep.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          switch (_step) {
            ColumnSheetStep.list => _buildListStep(l10n),
            ColumnSheetStep.create => _buildCreateStep(l10n),
            ColumnSheetStep.success => _buildSuccessStep(l10n),
          },
        ],
      ),
    );
  }

  Widget _sheetHeader(
    String title, {
    VoidCallback? onBack,
    bool showClose = true,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack)
          else
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          if (showClose)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildListStep(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetHeader(l10n.joinColumnAction),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.myColumnsLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: _primary)),
          )
        else if (_loadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.actionFailedWithReason('$_loadError'),
              style: const TextStyle(fontSize: 13, color: Color(0xFFFF3B30)),
            ),
          )
        else if (_columns.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.noColumnsCreatedYetPrompt,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          )
        else
          ..._columns.map((col) => _columnRow(col)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _step = ColumnSheetStep.create),
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.createColumnAction),
            // 跟上方「我的专栏」卡片同一套容器视觉语言：cardColor 填充 +
            // #EBEBEB 0.5px 细边 + 圆角 12，不再是跳出来的紫色描边框。只保留
            // 「+新建专栏」文字/图标的紫色作为唯一的"新建"操作提示
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              backgroundColor: Theme.of(context).cardColor,
              side: const BorderSide(color: Color(0xFFEBEBEB), width: 0.5),
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _columnRow(ColumnModel col) {
    final selected = _selectedId == col.id;
    final seed = col.id.isNotEmpty ? col.id.codeUnitAt(0) : 0;
    final fallbackColor = _coverColors[seed % _coverColors.length];
    final fallbackIcon = _fallbackIcons[seed % _fallbackIcons.length];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GestureDetector(
        onTap: () => _selectExisting(col),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFEEF0FF)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _primary : const Color(0xFFEBEBEB),
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: (col.coverImage?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: col.coverImage!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: 44,
                          height: 44,
                          color: fallbackColor,
                          child: Icon(
                            fallbackIcon,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      )
                    : Container(
                        width: 44,
                        height: 44,
                        color: fallbackColor,
                        child: Icon(
                          fallbackIcon,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      col.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.columnArticlesSubscribers(
                        col.articleCount,
                        col.subscriberCount,
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? _primary : const Color(0xFFDDDDDD),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateStep(AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // 点空白处收起键盘
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHeader(
                l10n.createColumnAction,
                onBack: () => setState(() => _step = ColumnSheetStep.list),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '专栏颜色',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: List.generate(_coverColors.length, (i) {
                        final c = _coverColors[i];
                        final selected = _colorIndex == i;
                        return GestureDetector(
                          onTap: () => setState(() => _colorIndex = i),
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: c.withValues(alpha: 0.4),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          l10n.columnNameLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '*',
                          style: TextStyle(
                            color: Color(0xFFFF3B30),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l10n.columnNameHint,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.columnIntroLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: l10n.columnDescOptionalLabel,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _creating ? null : _createColumn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _creating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(l10n.createColumnAction),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessStep(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(
                context,
                ColumnPickerResult(_selectedId, _createdName),
              ),
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F8F0),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 36, color: AppColors.success),
          ),
          const SizedBox(height: 16),
          const Text(
            '专栏创建成功',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '「$_createdName」已创建，本文已加入该专栏',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(
                context,
                ColumnPickerResult(_selectedId, _createdName),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD1D1D6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('完成'),
            ),
          ),
        ],
      ),
    );
  }
}
