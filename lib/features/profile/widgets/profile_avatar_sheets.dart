import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

const _primary = Color(0xFF6366F1);

void showAvatarOptions(
  BuildContext context, {
  required VoidCallback onPickGallery,
  required VoidCallback onPickCamera,
  required VoidCallback onAiAvatar,
}) {
  final l10n = AppLocalizations.of(context)!;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    // showModalBottomSheet 传 backgroundColor: Colors.transparent 时，
    // 弹层自带的 Material 会变成 MaterialType.transparency（没有颜色）。
    // 下面的 ListTile 找 Material 祖先画点击水波纹时，会往上找到这个
    // 透明 Material，而不是这层 Container——Container 不是 Material，
    // 水波纹就没有画布可画，Flutter 会打印"ListTile background color
    // or ink splashes may be invisible"警告。用 Material 包一层给
    // ListTile 一个真正带颜色的画布，而不是 Container
    //
    // 颜色用 scaffoldBackgroundColor 而不是 cardColor——底部导航栏
    // （main_shell.dart）用的就是 scaffoldBackgroundColor 这一套
    // （浅色 AppColors.bg / 深色 #1C1C1E），cardColor 在两个主题下都是
    // 另一个更浅/更亮的色号，弹层跟导航栏会撞出一条不统一的接缝
    builder: (ctx) => Material(
      color: Theme.of(ctx).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.selectFromAlbum),
              onTap: () {
                Navigator.pop(ctx);
                onPickGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.takePhoto),
              onTap: () {
                Navigator.pop(ctx);
                onPickCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined, color: _primary),
              title: const Text('AI 生成头像'),
              subtitle: const Text(
                '描述你想要的风格，小梦帮你生成',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onAiAvatar();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void showAiAvatarSheet(
  BuildContext context, {
  required Future<void> Function(String description) onGenerate,
}) {
  final descCtrl = TextEditingController();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_outlined,
                    size: 14,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'AI 生成头像',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                hintText: '描述你想要的风格（可选），如"极地风景，极光，简约"',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primary),
                ),
              ),
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ['极地风光', '几何抽象', '赛博朋克', '水彩插画', '星空宇宙'].map((t) {
                return GestureDetector(
                  onTap: () => descCtrl.text = t,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF555555)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await onGenerate(descCtrl.text.trim());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  '开始生成（约20秒）',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// 生成接口目前会因上游并发限流偶尔只成功1张而不是预期的多张——只有1张时
// 不套用选择网格（网格布局在只有1个格子时显得很空），改成大图+二选一
void showSingleAvatarConfirm(
  BuildContext context,
  String url, {
  required VoidCallback onRegenerate,
  required Future<void> Function(String url) onUse,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: Theme.of(ctx).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(url, width: 160, height: 160, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
          const Text(
            '使用这张头像？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onRegenerate();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: const BorderSide(color: Color(0xFFD0D0D0)),
                  ),
                  child: const Text('重新生成', style: TextStyle(color: Colors.grey)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await onUse(url);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '使用',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
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

void showAvatarPickerSheet(
  BuildContext context,
  List<String> urls, {
  required Future<void> Function(String url) onSelect,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: Theme.of(ctx).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_outlined, size: 14, color: _primary),
              ),
              const SizedBox(width: 8),
              const Text(
                '选择一个头像',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '点击即可设为头像',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          // 生成的头像数量不固定，多了就该在网格内部往下滚，而不是让整个
          // sheet 跟着无限拉长（甚至顶到状态栏）——所以这里用 maxHeight
          // 卡住网格区域的高度，GridView 保留正常的滚动手势
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: urls.length,
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  await onSelect(urls[i]);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    urls[i],
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) => progress == null
                        ? child
                        : Container(
                            color: Colors.grey[100],
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _primary,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
