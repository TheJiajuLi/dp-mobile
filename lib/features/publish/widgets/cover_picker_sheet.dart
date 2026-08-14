import 'dart:async';
import '../../../core/theme/app_colors.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/xmeng_image_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/widgets/app_toast.dart';

const _primary = AppColors.primary;

Future<void> pickCoverImage(
  BuildContext context,
  WidgetRef ref, {
  required void Function(String url, String? fileId) onUploaded,
}) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1200,
    maxHeight: 600,
    imageQuality: 85,
  );
  if (file == null) return;
  final bytes = await file.readAsBytes();
  try {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: 'cover.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/files/upload', data: formData);
    if (!res.success || res.data == null) return;
    final map = res.data as Map;
    final url = map['url'] as String?;
    if (url != null && context.mounted) onUploaded(url, map['id'] as String?);
  } catch (e) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      showAppToast(context, l10n.saveFailedWithReason('$e'));
    }
  }
}

Future<void> showCoverOptions(
  BuildContext context, {
  required VoidCallback onPickGallery,
  required VoidCallback onAiGenerate,
}) async {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
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
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 20,
                color: Colors.grey,
              ),
            ),
            title: const Text('从相册选择'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.pop(ctx);
              onPickGallery();
            },
          ),
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: _primary,
              ),
            ),
            title: const Text('小梦帮我生成封面'),
            subtitle: const Text('根据标题和标签自动生成', style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.pop(ctx);
              onAiGenerate();
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> aiGenerateCover(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required List<String> tags,
  required String summary,
  required void Function(String url, String? fileId) onCoverSelected,
}) async {
  // AI 封面生成是 Pro 权益——非 Pro 弹会员 Sheet
  if (!requirePro(context, ref, feature: 'AI 生成封面')) return;
  if (title.trim().isEmpty) {
    showAppToast(context, '请先填写标题，小梦才能生成封面');
    return;
  }

  // dialog 是否还在显示——避免网络异常提前抛出、或用户手动划走弹窗后，
  // 结果回来时再 pop 一次把发布页本身也顶掉（那次真实故障就是这么触发的）
  var dialogShowing = true;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AiGeneratingCoverDialog(),
  );

  try {
    final urls = await ref
        .read(xmengImageServiceProvider)
        .generateCover(
          title: title.trim(),
          tags: tags,
          summary: summary.trim(),
        );

    if (context.mounted && dialogShowing) {
      dialogShowing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;

    if (urls.isEmpty) {
      showAppToast(context, '生成失败，请重试');
      return;
    }

    showCoverPickerSheet(
      context,
      ref,
      urls,
      onSelect: onCoverSelected,
      onRegenerate: () => aiGenerateCover(
        context,
        ref,
        title: title,
        tags: tags,
        summary: summary,
        onCoverSelected: onCoverSelected,
      ),
    );
  } catch (e) {
    if (context.mounted && dialogShowing) {
      dialogShowing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (context.mounted) {
      showAppToast(context, '生成失败，请稍后重试');
    }
  }
}

// 生成接口现在只返回上游临时URL（24小时后失效，不落COS）——选中哪张
// 之前是直接把这个临时URL存进 _coverImageUrl，教程发布后过一段时间
// 封面图就会失效变成 broken image。选中时要转存成永久URL再回填，另外
// 没被选中的临时URL就放着过期，不用管。
//
// 转存本来是调 POST /auth/xmeng/confirm-image，让后端自己去抓这个临时
// URL——但后端对这个接口做了域名白名单校验（只认生成接口配置的那个
// 域名，防SSRF），而候选图的临时URL实际来自上游模型服务商自己的CDN，
// 域名对不上白名单，一律被拒（400 "url来源不合法"）。改成客户端自己
// 下载这张图的字节，再走已经在用、没有域名限制的通用上传接口
// POST /auth/files/upload（跟"从相册选择"封面用的是同一个接口），从
// 根上绕开这个域名不匹配的问题，不需要动后端
void showCoverPickerSheet(
  BuildContext context,
  WidgetRef ref,
  List<String> urls, {
  required void Function(String url, String? fileId) onSelect,
  required VoidCallback onRegenerate,
}) {
  // 必须声明在 StatefulBuilder 的 builder 函数外面——builder 每次
  // setSheetState 都会重新执行一遍，声明在里面的话每次 rebuild 都会被
  // 重新初始化成 null，"正在确认第几张"这个状态就保不住
  int? confirmingIndex;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        Future<void> confirmAndSelect(int i) async {
          if (confirmingIndex != null) return;
          setSheetState(() => confirmingIndex = i);
          try {
            // 临时URL来自上游模型服务商自己的CDN，不是我们后端的域名——
            // 客户端直接下载字节，不经后端转发抓取，就不会撞上后端那边
            // 给 confirm-image 接口做的域名白名单校验
            final imageBytes = await Dio().get<List<int>>(
              urls[i],
              options: Options(responseType: ResponseType.bytes),
            );
            final bytes = imageBytes.data;
            if (bytes == null || bytes.isEmpty) {
              throw Exception('封面图下载失败');
            }
            final formData = FormData.fromMap({
              'file': MultipartFile.fromBytes(
                bytes,
                filename:
                    'ai_cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
                contentType: DioMediaType('image', 'jpeg'),
              ),
            });
            final res = await ref
                .read(apiClientProvider)
                .post('/auth/files/upload', data: formData);
            if (!context.mounted) return;
            String? permanentUrl;
            String? fileId;
            if (res.success && res.data is Map) {
              permanentUrl = (res.data as Map)['url'] as String?;
              fileId = (res.data as Map)['id'] as String?;
            }
            if (permanentUrl == null || permanentUrl.isEmpty) {
              setSheetState(() => confirmingIndex = null);
              showAppToast(context, res.message ?? '保存失败，请重试');
              return;
            }
            onSelect(permanentUrl, fileId);
            Navigator.pop(ctx);
            showAppToast(context, '封面已应用', ok: true);
          } catch (e) {
            if (!context.mounted) return;
            setSheetState(() => confirmingIndex = null);
            showAppToast(context, '保存失败，请重试');
          }
        }

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
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
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_outlined,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '选择一张封面',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '点击即可应用',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 16 / 9,
                ),
                itemCount: urls.length,
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () => confirmAndSelect(i),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          urls[i],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          loadingBuilder: (ctx, child, progress) =>
                              progress == null
                              ? child
                              : Container(
                                  color: Colors.grey[100],
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[100],
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      if (confirmingIndex == i)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onRegenerate();
                  },
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    '重新生成',
                    style: TextStyle(color: AppColors.primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// AI封面生成等待弹窗——带计时+轮换提示语，让用户知道是在正常等待而不是
// 卡死。纯展示，不碰 aiGenerateCover 里那套 dialogShowing 防重复pop逻辑
class AiGeneratingCoverDialog extends StatefulWidget {
  const AiGeneratingCoverDialog({super.key});

  @override
  State<AiGeneratingCoverDialog> createState() =>
      _AiGeneratingCoverDialogState();
}

class _AiGeneratingCoverDialogState extends State<AiGeneratingCoverDialog> {
  int _seconds = 0;
  Timer? _timer;

  static const _tips = [
    '小梦正在理解你的标题...',
    '正在构思视觉风格...',
    '图像生成中，请稍候...',
    '即将完成，再等一下...',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _tip {
    if (_seconds < 5) return _tips[0];
    if (_seconds < 15) return _tips[1];
    if (_seconds < 35) return _tips[2];
    return _tips[3];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C22) : const Color(0xFFFAFAF8);
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    final faint = isDark ? Colors.white38 : const Color(0xFFBBBBBB);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 44),
      child: Container(
        // 米白底 + 大留白 + 柔和落影，把弹窗从页面里"托"起来一层
        padding: const EdgeInsets.fromLTRB(28, 34, 28, 30),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          border: isDark
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 0.5,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 环形进度 + 中心紫色渐变小梦星标，做出层次
            SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: const AlwaysStoppedAnimation(_primary),
                      backgroundColor: _primary.withValues(alpha: 0.12),
                    ),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _primary.withValues(alpha: isDark ? 0.28 : 0.14),
                          const Color(
                            0xFF8B5CF6,
                          ).withValues(alpha: isDark ? 0.28 : 0.12),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 20,
                      color: _primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              _tip,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ink,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '已等待 $_seconds 秒',
              style: TextStyle(fontSize: 12.5, color: muted),
            ),
            const SizedBox(height: 5),
            Text(
              '封面生成通常需要 20–60 秒',
              style: TextStyle(fontSize: 11.5, color: faint),
            ),
          ],
        ),
      ),
    );
  }
}
