import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _primary = Color(0xFF6366F1);

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem(this.question, this.answer);
}

// 内容跟这几个真实存在的功能一一对应（发布/专栏/会员/Notebook/极光计划/
// 账号安全），不是随手编的通用套话——哪天这些功能的具体规则变了，这里
// 也要跟着改，不能放着不管
const _faqItems = [
  _FaqItem(
    '如何发布一篇教程？',
    '在底部导航栏点击中间的"+"按钮进入发布页，填写标题、摘要，用积木式内容块添加文字/代码/图片等内容，编辑完成后点击"发布"即可。也可以先"存草稿"，之后在个人主页的教程列表里继续编辑。',
  ),
  _FaqItem(
    '如何创建专栏？',
    '在"创作者中心"或个人主页的"专栏"标签页里点击"新建专栏"，填写专栏名称和简介。创建后可以在专栏详情页把已发布的教程收录进去。',
  ),
  _FaqItem(
    '教程和专栏能不能编辑或删除？',
    '教程可以在发布页重新打开编辑并保存；专栏名称/简介可以在专栏详情页里点击"编辑"。删除功能正在开发中，暂不支持。',
  ),
  _FaqItem(
    '会员（Pro/Pro Max）有什么区别？',
    '两档会员在存储空间、AI 辅助次数等权益上有区别，具体对比详见"设置 → 会员权益说明"页面，价格以该页面实时显示为准。',
  ),
  _FaqItem(
    '订阅是自动续费的吗？如何取消？',
    '会员订阅通过 Apple App Store 处理，按你选择的周期自动续费。可以随时在 iPhone 的"设置 → App Store → 订阅"里取消，取消后当前订阅周期结束前仍可继续使用会员权益。',
  ),
  _FaqItem(
    '小梦 AI 是什么？',
    '小梦是内置的 AI 辅助功能，可以帮你生成标题、摘要，以及在发布教程和编辑资料时生成封面图/头像。生成结果仅供参考，发布前建议自行核实内容准确性。',
  ),
  _FaqItem(
    'Notebook 是什么，和教程有什么区别？',
    'Notebook 是可以直接运行代码块的交互式文档（类似 Jupyter Notebook），适合边写代码边记录思路；教程是面向阅读的图文/代码混排内容，两者在个人主页分别是独立的标签页。',
  ),
  _FaqItem(
    '极光创作者计划是什么？',
    '极光创作者计划面向持续产出优质内容的创作者，提供收益分成等权益，具体参与条件和分成规则详见"创作者中心 → 极光创作者计划"页面说明。',
  ),
  _FaqItem(
    '忘记密码怎么办？',
    '如果还能正常登录，可以在"设置 → 账号与安全 → 修改密码"里修改；如果无法登录，请通过下方"联系我们"里的邮箱联系我们协助处理。',
  ),
  _FaqItem(
    '注销账号会发生什么？',
    '注销是不可恢复的操作，账号数据会在 30 天内从服务器删除（法律要求保留的数据除外）。可以在"设置 → 账号与安全 → 注销账号"里发起，操作前会有二次确认。',
  ),
  _FaqItem(
    '我的个人主页可以设置成不公开吗？',
    '可以，在"设置 → 隐私"里关闭"公开主页"后，其他用户访问你的主页时只能看到基础信息（头像/用户名等），看不到你发布的内容和收藏。',
  ),
];

class FaqListScreen extends StatefulWidget {
  final String? initialQuery;
  const FaqListScreen({super.key, this.initialQuery});

  @override
  State<FaqListScreen> createState() => _FaqListScreenState();
}

class _FaqListScreenState extends State<FaqListScreen> {
  late final TextEditingController _searchCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery?.trim() ?? '';
    _searchCtrl = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_FaqItem> get _filtered {
    if (_query.isEmpty) return _faqItems;
    final q = _query.toLowerCase();
    return _faqItems
        .where(
          (f) =>
              f.question.toLowerCase().contains(q) ||
              f.answer.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('常见问题'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: widget.initialQuery == null,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索常见问题...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
            ),
          ),
          Expanded(
            // 点空白处收起键盘
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: results.isEmpty
                  ? const Center(
                      child: Text(
                        '没有找到相关问题',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        // 所有问题收进一张大圆角卡片，组内用分割线区分，不再是
                        // 一条一条独立的小卡片
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isDark
                                ? null
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < results.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                    height: 0.5,
                                    thickness: 0.5,
                                    indent: 14,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                _FaqTile(item: results[i]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final _FaqItem item;
  const _FaqTile({required this.item});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 单条不再是独立卡片——外层把所有问题收进一张大圆角卡，这里只负责一行
    // 可展开的问答
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.question,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.remove : Icons.add,
                  size: 18,
                  color: _primary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Text(
              widget.item.answer,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark ? Colors.white70 : const Color(0xFF555555),
              ),
            ),
          ),
      ],
    );
  }
}
