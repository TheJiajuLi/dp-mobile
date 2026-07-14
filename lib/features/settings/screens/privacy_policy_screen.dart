import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/legal_doc_widgets.dart';

// 隐私政策全文——运营主体为上海既白观海科技有限公司，2026-07-14 更新，
// 版本 1.0。以后政策文本更新时这里也要同步改
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('隐私政策'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        children: [
          const LegalDocHeader(
            title: '隐私政策',
            subtitle: 'Privacy Policy · 极梦（Dreaming Polar）',
            effectiveDate: '2026 年 7 月 14 日',
            version: '1.0',
          ),
          const LegalCallout(
            '上海既白观海科技有限公司（以下简称「我们」）深知个人信息对您的重要性，将按照法律法规要求采取相应安全保护措施，保护您的个人信息。',
          ),

          const LegalH2('一、我们收集的信息'),
          const LegalH3('1.1 您主动提供的信息'),
          const LegalBullets([
            '注册信息：邮箱地址、用户名、密码',
            '个人资料：头像、简介、职业、兴趣标签',
            '创作内容：文章、Notebook、评论、回复',
            '支付信息：通过 Apple App Store 处理，我们不直接收集您的支付卡信息',
          ]),
          const LegalH3('1.2 自动收集的信息'),
          const LegalBullets([
            '设备信息：设备型号、操作系统版本',
            '使用数据：浏览记录、搜索历史、点赞收藏等行为数据',
            '日志信息：访问时间、IP 地址、崩溃报告',
          ]),

          const LegalH2('二、我们如何使用您的信息'),
          const LegalBullets([
            '提供、维护和改善极梦服务',
            '个性化内容推荐',
            '发送服务通知和更新',
            '保障平台安全，防止欺诈',
            '分析使用情况以优化产品体验',
            '处理订阅和会员权益',
          ]),

          const LegalH2('三、信息共享'),
          const LegalP('我们不会向第三方出售您的个人信息。以下情况除外：'),
          const LegalBullets([
            '经您明确同意',
            '法律法规要求',
            '保护用户或公众安全的必要情况',
            '与服务提供商共享（仅限提供服务所需）：\n   - Apple（App Store 支付验证）\n   - 腾讯云（数据存储）\n   - Firebase（崩溃分析）',
          ]),

          const LegalH2('四、数据存储与安全'),
          const LegalBullets([
            '您的数据存储于中国境内的服务器',
            '我们采用加密传输（HTTPS/TLS）保护数据传输安全',
            '我们定期进行安全评估和审计',
            '账号密码采用加密存储，我们无法获取您的明文密码',
          ]),

          const LegalH2('五、您的权利'),
          const LegalP('您有权：'),
          const LegalBullets([
            '访问您的个人信息',
            '更正不准确的信息',
            '删除您的账号及相关数据',
            '导出您的内容数据',
            '撤回对非必要信息的授权',
          ]),
          const LegalP('如需行使上述权利，请联系：support@dreamingpolar.com'),

          const LegalH2('六、未成年人保护'),
          const LegalCallout('极梦不面向 13 岁以下未成年人。如发现 13 岁以下用户注册，我们将立即删除相关账号和数据。'),

          const LegalH2('七、Cookie 和类似技术'),
          const LegalP('我们使用 Cookie 和类似技术记录您的登录状态和偏好设置。您可以在设备设置中管理这些权限。'),

          const LegalH2('八、隐私政策的变更'),
          const LegalP('我们可能会更新本隐私政策。重大变更将通过 App 内通知或邮件告知。继续使用极梦即表示您同意更新后的政策。'),

          const LegalH2('九、联系我们'),
          const LegalP('上海既白观海科技有限公司'),
          const LegalContactLine('邮箱', 'support@dreamingpolar.com'),
          const LegalContactLine('网址', 'https://dreamingpolar.com'),

          const LegalFooter(),
        ],
      ),
    );
  }
}
