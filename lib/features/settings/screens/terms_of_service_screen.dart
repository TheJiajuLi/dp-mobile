import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/legal_doc_widgets.dart';

// 用户服务协议全文——跟《极梦_用户服务协议.pdf》（生效日期 2026-07-07，
// 版本 1.0）逐条对应，不是摘要或改写。以后协议文本更新时这里也要同步改
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('用户服务协议'),
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
            title: '用户服务协议',
            subtitle: 'Terms of Service · 极梦（Dreaming Polar）',
            effectiveDate: '2026 年 7 月 7 日',
            version: '1.0',
          ),

          const LegalH2('一、总则与接受条款'),
          const LegalP(
            '欢迎使用极梦（Dreaming Polar）内容创作平台（以下简称「极梦」或「本平台」）。本协议由您与极梦运营主体（以下简称「我们」）共同缔结，具有合同效力。',
          ),
          const LegalCallout(
            '重要提示：请您在使用极梦前仔细阅读本协议全部条款。注册账号、点击「同意」按钮或以任何方式使用本平台，即表示您已充分阅读、理解并接受本协议。',
          ),
          const LegalP(
            '本协议适用于极梦移动应用程序（iOS/Android）及相关服务。若您不同意本协议任何条款，请立即停止使用本平台。',
          ),

          const LegalH2('二、账号注册与管理'),
          const LegalH3('2.1 注册资格'),
          const LegalBullets([
            '您须年满 16 周岁（或所在地区法定最低年龄）方可注册使用本平台。',
            '若您未满 18 周岁，须在监护人同意并监督下使用本平台。',
            '您须保证注册信息真实、准确、完整，并在信息变更时及时更新。',
          ]),
          const LegalH3('2.2 账号安全'),
          const LegalBullets([
            '您应妥善保管账号密码，不得转让、出售或共享账号。',
            '因账号保管不当导致的损失由您自行承担。',
            '如发现账号被盗用，请立即联系我们：support@dreamingpolar.com。',
          ]),
          const LegalH3('2.3 账号注销'),
          const LegalP(
            '您可随时在「设置 → 账号 → 注销账号」申请注销。注销后，您的账号数据将在 30 天内从我们服务器删除（法律要求保留的数据除外）。',
          ),

          const LegalH2('三、平台服务'),
          const LegalH3('3.1 核心服务'),
          const LegalP('极梦为用户提供以下服务：'),
          const LegalBullets([
            '知识内容创作与发布（教程、Notebook、专栏等）',
            '内容阅读、搜索与收藏',
            '用户社交互动（评论、点赞、关注、私信）',
            'AI 创作辅助（小梦 AI）',
            '极光创作者计划及收益分成',
          ]),
          const LegalH3('3.2 会员服务'),
          const LegalP(
            '极梦提供免费版及 Pro/Pro Max 付费会员服务。付费会员费用按所选周期（月付/年付）收取，自动续订。您可随时在 Apple App Store 订阅管理中取消续订。',
          ),
          const LegalH3('3.3 服务变更'),
          const LegalP('我们保留在合理通知后修改、暂停或终止部分服务的权利。重大变更将提前 7 天通过 App 内通知告知用户。'),

          const LegalH2('四、用户行为规范'),
          const LegalH3('4.1 您承诺不得'),
          const LegalNumbered([
            '发布违反中国法律法规、侵犯他人权益的内容',
            '发布虚假信息、诈骗或误导性内容',
            '侵犯他人著作权、商标权或其他知识产权',
            '发布色情、暴力、仇恨或歧视性内容',
            '以任何方式骚扰、威胁或伤害其他用户',
            '利用技术手段干扰、破坏平台正常运行',
            '未经授权抓取、爬取平台内容或数据',
            '创建虚假账号、刷数据或实施其他欺骗行为',
          ]),
          const LegalH3('4.2 内容规范'),
          const LegalP('您发布的内容须符合以下要求：'),
          const LegalBullets([
            '内容为您原创或已获得合法授权',
            '引用他人内容须注明来源',
            'AI 辅助生成内容须经过实质性修改和验证',
            '代码内容不得包含恶意程序或漏洞利用代码',
          ]),
          const LegalH3('4.3 违规处理'),
          const LegalP(
            '违反上述规范的行为，我们将根据严重程度采取内容删除、功能限制、账号封禁等措施，情节严重者将依法追究法律责任。',
          ),

          const LegalH2('五、内容版权'),
          const LegalH3('5.1 用户内容授权'),
          const LegalP(
            '您对自己发布的内容保留著作权。发布内容即表示您授予极梦在全球范围内、免费的、非独家的许可，用于展示、分发、推广您的内容。此授权仅限于平台运营所必需的范围。',
          ),
          const LegalH3('5.2 平台内容'),
          const LegalP('极梦平台自有内容（界面设计、品牌标识、技术系统等）受著作权法保护，未经书面许可不得复制或使用。'),
          const LegalH3('5.3 侵权处理'),
          const LegalP(
            '如您认为平台内容侵犯您的知识产权，请发送侵权通知至：legal@dreamingpolar.com，我们将在 3 个工作日内处理。',
          ),

          const LegalH2('六、极光创作者计划'),
          const LegalP(
            '极光创作者计划的参与条件、收益分成比例、结算规则等详见平台内「极光创作者计划」专项说明。我们保留依据市场情况调整分成政策的权利，重大调整将提前 30 天通知。',
          ),

          const LegalH2('七、免责声明'),
          const LegalH3('7.1 服务可用性'),
          const LegalP(
            '我们将尽力保证服务稳定，但不对以下情况承担责任：不可抗力、第三方服务故障、用户设备问题、网络中断等导致的服务不可用。',
          ),
          const LegalH3('7.2 内容准确性'),
          const LegalP(
            '平台内用户发布的内容仅代表创作者个人观点，极梦不对其准确性、完整性承担责任。涉及医疗、法律、金融等专业内容，请以专业机构意见为准。',
          ),
          const LegalH3('7.3 AI 生成内容'),
          const LegalP('小梦 AI 生成的内容可能存在错误或不准确之处，用户在发布或应用 AI 辅助内容前应自行核实。'),

          const LegalH2('八、争议解决'),
          const LegalP(
            '本协议受中华人民共和国法律管辖。因本协议引起的争议，双方应首先通过友好协商解决；协商不成的，提交极梦注册地有管辖权的人民法院诉讼解决。',
          ),

          const LegalH2('九、协议修改'),
          const LegalP(
            '我们保留修改本协议的权利。修改后的协议将在 App 内公告，重大修改将通过推送通知告知。继续使用本平台即视为接受修改后的协议。',
          ),

          const LegalH2('十、联系我们'),
          const LegalP('如对本协议有任何疑问，请通过以下方式联系我们：'),
          const LegalContactLine('电子邮件', 'support@dreamingpolar.com'),
          const LegalContactLine('官方网站', 'https://dreamingpolar.com'),
          const LegalContactLine('App 内反馈', '设置 → 帮助与反馈'),

          const LegalFooter(),
        ],
      ),
    );
  }
}
