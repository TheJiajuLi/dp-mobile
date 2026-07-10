import 'package:flutter/widgets.dart';

/// @ 提及的纯逻辑：不持有任何 controller / focusNode，全部操作外部传入的
/// [TextEditingController]。这样评论输入框可以继续用它自己那份 _commentCtrl，
/// 提交 / 回复 / 焦点逻辑一行都不用改。
class MentionQuery {
  /// 记录最近一次 [detect] 命中的 @ 位置（@ 符号本身的下标）。
  /// -1 表示当前不在 @ 输入态。[insert] 依赖它把 @查询词替换成 @用户名。
  int _atPosition = -1;

  /// 根据当前光标位置判断是否正处于 @ 输入态。
  /// 返回 @ 后面到光标之间的查询词（可能为空字符串，表示刚敲下 @）；
  /// 不在 @ 输入态时返回 null。
  String? detect(TextEditingController ctrl) {
    final sel = ctrl.selection;
    // 多选 / 无光标时不触发
    if (!sel.isValid || !sel.isCollapsed) {
      _atPosition = -1;
      return null;
    }
    final cursor = sel.baseOffset;
    if (cursor < 0 || cursor > ctrl.text.length) {
      _atPosition = -1;
      return null;
    }

    // 只看光标之前的文本，往前找最近的一个 @
    final before = ctrl.text.substring(0, cursor);
    final atIdx = before.lastIndexOf('@');
    if (atIdx < 0) {
      _atPosition = -1;
      return null;
    }

    // @ 前面必须是行首或空白，避免把 email 之类的 a@b 也当成提及
    if (atIdx > 0) {
      final prev = before[atIdx - 1];
      if (prev.trim().isNotEmpty) {
        _atPosition = -1;
        return null;
      }
    }

    // @ 和光标之间一旦出现空白/换行，视为提及已结束
    final query = before.substring(atIdx + 1);
    if (query.contains(RegExp(r'\s'))) {
      _atPosition = -1;
      return null;
    }

    _atPosition = atIdx;
    return query;
  }

  /// 选中某个用户后，把「@查询词」整段替换为「@用户名 」（末尾补一个空格，
  /// 顺手结束提及态），并把光标移到用户名后面。直接写回外部 controller。
  void insert(TextEditingController ctrl, String username) {
    if (_atPosition < 0) return;
    final sel = ctrl.selection;
    final cursor = sel.isValid && sel.isCollapsed
        ? sel.baseOffset
        : ctrl.text.length;
    if (_atPosition > cursor || cursor > ctrl.text.length) {
      _atPosition = -1;
      return;
    }

    final before = ctrl.text.substring(0, _atPosition);
    final after = ctrl.text.substring(cursor);
    final insertText = '@$username ';
    final newText = '$before$insertText$after';

    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: before.length + insertText.length,
      ),
    );
    _atPosition = -1;
  }

  /// 手动复位（比如提交后），避免残留的 @ 位置在下一轮误触发。
  void reset() => _atPosition = -1;
}
