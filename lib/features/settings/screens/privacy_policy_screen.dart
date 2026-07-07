import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/legal_doc_widgets.dart';

// 隐私政策全文——跟《极梦_隐私政策.pdf》（生效日期 2026-07-07，版本 1.0）
// 逐条对应，不是摘要或改写。以后政策文本更新时这里也要同步改
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
            effectiveDate: '2026 年 7 月 7 日',
            version: '1.0',
          ),
          const LegalCallout(
            '极梦深知隐私对您的重要性。本政策说明我们收集哪些信息、如何使用这些信息，以及您拥有哪些权利。我们不会将您的个人信息出售给任何第三方。',
          ),

          const LegalH2('一、信息控制者'),
          const LegalP(
            '极梦移动应用程序的个人信息控制者为极梦运营主体。如有隐私相关问题，请联系：privacy@dreamingpolar.com。',
          ),

          const LegalH2('二、我们收集的信息'),
          const LegalH3('2.1 您主动提供的信息'),
          const LegalBullets([
            '账号信息：用户名、邮箱地址、密码（加密存储）',
            '个人资料：头像、个人简介、性别、所在地（可选）',
            '创作内容：您发布的教程、Notebook、评论等内容',
            '通信内容：您与其他用户的私信内容',
            '支付信息：通过 Apple In-App Purchase 处理，极梦不存储您的支付卡信息',
          ]),
          const LegalH3('2.2 自动收集的信息'),
          const LegalBullets([
            '设备信息：设备型号、操作系统版本、设备标识符',
            '使用数据：功能使用频率、页面访问记录、搜索词',
            '日志数据：IP 地址、访问时间、错误日志',
            'IP 属地：基于 IP 地址推断的大致地理位置（省级精度）',
          ]),
          const LegalH3('2.3 我们不收集的信息'),
          const LegalBullets([
            '精确地理位置（GPS 坐标）',
            '通讯录、相册（仅在您主动上传头像/图片时访问，不持续读取）',
            '麦克风、摄像头（仅音视频发布功能启用时访问）',
            '其他 App 的使用数据',
          ]),

          const LegalH2('三、信息使用目的'),
          const LegalP('我们基于以下合法性基础处理您的个人信息：'),
          const LegalH3('合同履行'),
          const LegalBullets(['提供账号注册、内容发布、社交互动等核心服务', '处理会员订阅及极光创作者分成结算']),
          const LegalH3('合法利益'),
          const LegalBullets([
            '改善产品功能和用户体验',
            '平台安全维护和欺诈防范',
            '内容推荐算法优化（基于阅读行为）',
          ]),
          const LegalH3('法律义务'),
          const LegalBullets(['遵守中国《网络安全法》《个人信息保护法》等相关法规', '响应政府主管部门的合法信息请求']),
          const LegalH3('您的同意'),
          const LegalBullets(['发送推送通知（可随时在系统设置中关闭）', '使用小梦 AI 功能处理您的内容']),

          const LegalH2('四、信息共享'),
          const LegalH3('4.1 我们不会共享您信息的情形'),
          const LegalP('我们不向任何第三方出售、租赁或以其他商业目的共享您的个人信息。'),
          const LegalH3('4.2 必要的信息共享'),
          const LegalBullets([
            '云存储服务商（腾讯云 COS）：存储您上传的图片、文件等内容，仅用于数据存储',
            'AI 服务提供商：处理小梦 AI 请求，仅传输必要内容，不传输账号身份信息',
            'Apple：通过 App Store 处理订阅付款，极梦不获取支付卡详情',
            '法律要求：依法配合执法机关的合法信息请求，并在法律允许范围内提前通知您',
          ]),
          const LegalH3('4.3 业务变更'),
          const LegalP('如发生合并、收购或资产出售，我们将确保新主体承继本隐私政策的义务，并提前通知您。'),

          const LegalH2('五、数据存储与安全'),
          const LegalH3('5.1 存储位置'),
          const LegalP(
            '您的个人数据主要存储于腾讯云中国大陆数据中心。部分服务数据可能存储于香港数据中心。我们不向欧盟/英国境外传输欧盟/英国居民的个人数据，除非已采取适当保障措施。',
          ),
          const LegalH3('5.2 安全措施'),
          const LegalBullets([
            '传输加密：所有数据传输均采用 HTTPS/TLS 1.3 加密',
            '存储加密：敏感数据（密码等）采用行业标准加密算法存储',
            '访问控制：员工仅在必要时访问用户数据，并受保密协议约束',
            '安全审计：定期进行安全漏洞扫描和渗透测试',
          ]),
          const LegalH3('5.3 数据保留'),
          const LegalBullets([
            '账号数据：账号存续期间保留；注销后 30 天内删除',
            '日志数据：保留 180 天后自动删除',
            '内容数据：您删除内容后 30 天内从服务器删除',
            '法定保留：依法律要求须保留的数据按法定期限保留',
          ]),

          const LegalH2('六、您的权利'),
          const LegalP('依据《个人信息保护法》及 GDPR，您对个人信息享有以下权利：'),
          const LegalH3('查阅权'),
          const LegalP('您可在「设置 → 账号 → 我的数据」中查阅我们持有的您的个人信息。'),
          const LegalH3('更正权'),
          const LegalP('您可随时在个人资料页面更正不准确的信息。'),
          const LegalH3('删除权（被遗忘权）'),
          const LegalP('您可申请删除个人信息。部分信息因法律义务须保留，我们将告知保留原因。'),
          const LegalH3('可携带权'),
          const LegalP(
            '您可申请导出您发布的内容数据（JSON 格式）。请发送请求至：privacy@dreamingpolar.com。',
          ),
          const LegalH3('反对权'),
          const LegalP('您可在设置中关闭基于个人信息的内容推荐。'),
          const LegalH3('撤回同意'),
          const LegalP('您可随时在系统设置中关闭推送通知，撤回相关同意。撤回不影响撤回前的数据处理合法性。'),
          const LegalH3('投诉权'),
          const LegalP(
            '如认为我们处理您信息的方式违反法律规定，您有权向个人信息保护主管部门（中国）或信息专员办公室（ICO，英国）提出投诉。',
          ),

          const LegalH2('七、儿童隐私'),
          const LegalCallout('极梦不面向 16 周岁以下用户提供服务，不会故意收集未成年人个人信息。'),
          const LegalP(
            '如我们发现用户为 16 周岁以下，将立即删除相关账号和信息。家长如发现子女注册了极梦账号，请联系：privacy@dreamingpolar.com。',
          ),

          const LegalH2('八、Cookie 与追踪技术'),
          const LegalP('极梦移动应用不使用浏览器 Cookie。我们使用以下技术：'),
          const LegalBullets([
            '设备标识符：用于账号识别和安全验证',
            '本地存储：用于保存您的偏好设置（完全在设备本地）',
            '崩溃报告：用于收集匿名的应用崩溃信息以改善稳定性',
          ]),

          const LegalH2('九、第三方链接'),
          const LegalP(
            '平台内用户发布的内容可能包含第三方网站链接。我们不对第三方网站的隐私做法负责，建议您在访问前阅读其隐私政策。',
          ),

          const LegalH2('十、政策更新'),
          const LegalP(
            '我们可能不定期更新本隐私政策。重大变更将通过 App 内通知或推送消息告知您，并在更新后的政策生效前给予至少 7 天的审阅期。继续使用本平台即表示您接受更新后的政策。',
          ),

          const LegalH2('十一、联系我们'),
          const LegalP('如对本隐私政策有任何问题或需要行使上述权利，请通过以下方式联系我们：'),
          const LegalContactLine('隐私专项邮箱', 'privacy@dreamingpolar.com'),
          const LegalContactLine('一般支持', 'support@dreamingpolar.com'),
          const LegalContactLine('官方网站', 'https://dreamingpolar.com/privacy'),
          const LegalContactLine('App 内反馈', '设置 → 帮助与反馈'),
          const SizedBox(height: 10),
          const LegalPBold('我们承诺在收到请求后 15 个工作日内予以回复。'),

          const LegalFooter(),
        ],
      ),
    );
  }
}
