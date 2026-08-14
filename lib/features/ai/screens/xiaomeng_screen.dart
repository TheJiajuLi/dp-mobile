import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';

const _primary = AppColors.primary;

// 小梦对话——欢迎页。真实接口是 POST /auth/xmeng/conversations（新对话）
// 和 POST /auth/xmeng/conversations/:id/messages（继续对话），不是
// /auth/ai/chat；历史对话列表/详情/删除也都是真实的
// GET|DELETE /auth/xmeng/conversations(/:id)，这套后端本来就是完整的，
// 不是这次新加的
//
// 4个能力卡片和3个快捷问题都只是把文字"预填"进对话页的输入框，不会自动
// 发送——用户还要在对话页自己点一次发送。统一走这一条路径，不在欢迎页
// 自己再做一份"预填在本页输入框"的重复逻辑
class XiaomengScreen extends StatefulWidget {
  // HD 双栏嵌入用：embedded=true 隐藏顶部返回/历史按钮（HD 左栏自带历史+新对话）；
  // onOpenChat 非空时"发送/点提示"不再 push 新路由，而是回调给 HD 页面驱动右栏
  final bool embedded;
  final void Function(String? prefill)? onOpenChat;
  const XiaomengScreen({super.key, this.embedded = false, this.onOpenChat});

  @override
  State<XiaomengScreen> createState() => _XiaomengScreenState();
}

class _XiaomengScreenState extends State<XiaomengScreen> {
  final _inputCtrl = TextEditingController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _openChat({String? prefill}) {
    if (widget.onOpenChat != null) {
      widget.onOpenChat!(prefill);
      return;
    }
    context.push('/xiaomeng/chat', extra: {'initialMessage': prefill});
  }

  void _submitInput() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _openChat(prefill: text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.embedded) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios, size: 16),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '问问小梦',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  // 历史对话入口（之前欢迎页没有，得先退出去才能进历史）
                  GestureDetector(
                    onTap: () => context.push('/xiaomeng/history'),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        Icons.history_outlined,
                        size: 20,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20, thickness: 0.5),
            ],
            if (widget.embedded) const SizedBox(height: 16),
            Expanded(
              // 点空白处收起键盘
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 76,
                                height: 76,
                                decoration: const BoxDecoration(
                                  color: _primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Text(
                                    '梦',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              // 小梦是 AI，不是真实用户，没有 last_seen_at
                              // 这种在线状态数据——不接 online_status.dart
                              // 那套真实在线判定，就是个固定的"常驻在线"绿点
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).scaffoldBackgroundColor,
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '你好，我是小梦',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '博学的知识伙伴',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '数学·代码·人文·生活，随时问我',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      // 1.7 算出来的格子高度跟内容实际需要的高度只差几像素，
                      // 在真机字体度量下会被顶出来触发 "BOTTOM OVERFLOWED"——
                      // 调宽裕一点，不是玄学调数字，是给 32(图标)+8+文字两行+
                      // 上下 14*2 padding 留够空间
                      childAspectRatio: 1.5,
                      children: [
                        _capabilityCard(
                          isDark,
                          icon: Icons.functions,
                          iconColor: _primary,
                          iconBg: const Color(0xFFEEF0FF),
                          iconBgDark: const Color(0xFF20284A),
                          label: '数学推导',
                          subtitle: '公式·证明·计算',
                          prefill: '帮我推导：',
                        ),
                        _capabilityCard(
                          isDark,
                          icon: Icons.code,
                          iconColor: const Color(0xFF16A34A),
                          iconBg: const Color(0xFFDCFCE7),
                          iconBgDark: const Color(0xFF0F2A1A),
                          label: '代码辅助',
                          subtitle: 'Python·SQL·调试',
                          prefill: '帮我写代码实现：',
                        ),
                        _capabilityCard(
                          isDark,
                          icon: Icons.bar_chart,
                          iconColor: const Color(0xFFD97706),
                          iconBg: const Color(0xFFFEF3C7),
                          iconBgDark: const Color(0xFF2A1F00),
                          label: '数据分析',
                          subtitle: 'RFM·可视化·建模',
                          prefill: '帮我分析：',
                        ),
                        _capabilityCard(
                          isDark,
                          icon: Icons.chat_bubble_outline,
                          iconColor: const Color(0xFFEF4444),
                          iconBg: const Color(0xFFFEE2E2),
                          iconBgDark: const Color(0xFF2A0A0A),
                          label: '随便聊聊',
                          subtitle: '生活·娱乐·思考',
                          prefill: null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '试试这些',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 8),
                    _promptTile(
                      isDark,
                      icon: Icons.auto_awesome,
                      text: '用贝叶斯定理解释医学检验的误差',
                    ),
                    const SizedBox(height: 8),
                    _promptTile(
                      isDark,
                      icon: Icons.code,
                      text: '帮我写一个 RFM 客户分层的 Python 代码',
                    ),
                    const SizedBox(height: 8),
                    _promptTile(
                      isDark,
                      icon: Icons.functions,
                      text: '证明欧拉公式 e^(iπ) + 1 = 0',
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _buildInputBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _capabilityCard(
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required Color iconBgDark,
    required String label,
    required String subtitle,
    required String? prefill,
  }) {
    return GestureDetector(
      onTap: () => _openChat(prefill: prefill),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark ? iconBgDark : iconBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promptTile(
    bool isDark, {
    required IconData icon,
    required String text,
  }) {
    return GestureDetector(
      onTap: () => _openChat(prefill: text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: _primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    // 底部栏之前用 cardColor，跟 Scaffold 自己的 scaffoldBackgroundColor
    // 不是一个颜色，页面和底部栏之间有接缝——按老规矩统一成
    // scaffoldBackgroundColor。输入框内部的胶囊之前吃的是全局主题
    // inputDecorationTheme.fillColor，跟底部栏原来的 cardColor 太接近，
    // 灰蒙蒙糊在一起看不清——换成好友页搜索框同款、明显更深一档的胶囊底
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFE8E8ED),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _inputCtrl,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitInput(),
                    decoration: const InputDecoration(
                      hintText: '问小梦任何问题...',
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _submitInput,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: _primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, size: 17, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
