import '../../shared/models/user_model.dart';

// 会员权限判断统一入口——原来 Pro 相关的权限检查散在各个页面各写一份
// （运行 Notebook/小梦AI/发布音视频等），这里收成一处，新加一项权益的
// 判断逻辑只用改一个地方
class MembershipUtils {
  static bool isPro(String? membership) =>
      membership == 'pro' || membership == 'pro_max';

  static bool isProMax(String? membership) => membership == 'pro_max';

  static bool isFounding(UserModel? user) => user?.isFoundingCreator == true;

  // 各项具体权限——目前都是"Pro 及以上"同一档，先按现有会员页
  // （subscription_screen.dart）列出的权益划线，以后哪项要单独区分
  // Pro/Pro Max 再拆
  static bool canRunNotebook(String? m) => isPro(m);

  static bool canUseXmeng(String? m) => isPro(m);

  static bool canUploadMedia(String? m) => isPro(m);

  static bool canPublishMedia(String? m) => isPro(m);

  static bool canExportPdf(String? m) => isPro(m);

  static bool canDownloadFile(String? m) => isPro(m);

  static bool canSendCodeInChat(String? m) => isPro(m);

  static bool canSendMediaInChat(String? m) => isPro(m);

  // 存储配额（GB）——跟后端 auth.controller.ts 的 quotaMap 保持一致
  // （free 200MB 用 0 表示，展示层不会真的拿这个数字当"0GB"渲染）
  static int storageGB(String? m) {
    if (isProMax(m)) return 20;
    if (isPro(m)) return 5;
    return 0;
  }

  // 统一的升级提示文案
  static String upgradeHint(String feature) => '$feature 需要 Pro 会员';
}
