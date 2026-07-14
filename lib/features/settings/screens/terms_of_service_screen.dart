import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/legal_doc_widgets.dart';

// 用户服务协议全文——运营主体为上海既白观海科技有限公司，2026-07-14
// 更新，版本 1.0。以后协议文本更新时这里也要同步改
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
            effectiveDate: '2026 年 7 月 14 日',
            version: '1.0',
          ),
          const LegalP(
            '欢迎使用极梦（Dreaming Polar）。本协议由您与上海既白观海科技有限公司（以下简称「极梦」或「我们」）签订。使用极梦服务即表示您同意本协议。',
          ),

          const LegalH2('一、服务说明'),
          const LegalP('极梦是一个面向知识创作者和知识爱好者的内容社区，提供：'),
          const LegalBullets([
            '知识内容创作与发布',
            'Notebook 编程与数据分析',
            'AI 辅助创作工具（小梦）',
            '会员订阅服务',
          ]),

          const LegalH2('二、账号注册'),
          const LegalBullets([
            '您需要年满 13 岁才能注册使用极梦',
            '您应提供真实、准确的注册信息',
            '您有责任保管账号安全，不得将账号转让或出借他人',
            '如发现账号被盗用，请立即联系 support@dreamingpolar.com',
          ]),

          const LegalH2('三、用户行为规范'),
          const LegalP('您在极梦发布的内容不得：'),
          const LegalNumbered([
            '违反中华人民共和国相关法律法规',
            '侵犯他人知识产权',
            '发布虚假、误导性信息',
            '发布色情、暴力、歧视性内容',
            '进行未经授权的商业广告推广',
            '骚扰、威胁其他用户',
            '抄袭他人内容',
          ]),
          const LegalP('违反上述规范，我们有权删除内容、封禁账号，情节严重的将追究法律责任。'),

          const LegalH2('四、内容版权'),
          const LegalBullets([
            '您发布的原创内容，版权归您所有',
            '您授予极梦在平台内展示、传播您内容的权利',
            '极梦不会将您的内容用于平台运营以外的商业目的',
            '您保证发布的内容不侵犯任何第三方权益',
          ]),

          const LegalH2('五、会员服务'),
          const LegalH3('套餐与价格'),
          const LegalBullets([
            '极梦 PRO：¥38/月 或 ¥348/年',
            '极梦 PRO MAX：¥68/月',
            '7 天免费试用（新用户首次订阅）',
          ]),
          const LegalH3('订阅说明'),
          const LegalBullets([
            '订阅通过 Apple App Store 处理',
            '订阅将在到期前 24 小时自动续订',
            '可在 App Store 账户设置中随时关闭自动续订',
            '关闭后当前订阅周期结束前仍可使用',
          ]),
          const LegalH3('退款政策'),
          const LegalBullets(['退款申请请通过 Apple App Store 提交', '极梦不直接处理退款']),

          const LegalH2('六、极光创作者计划'),
          const LegalP('满足以下条件可自动获得极光创作者资格：'),
          const LegalBullets(['发布文章 ≥ 10 篇', '累计获赞/收藏 ≥ 100', '粉丝数 ≥ 50']),
          const LegalP('极光创作者享有：'),
          const LegalBullets(['免费 PRO MAX 会员权益', '流量分成资格', '金色创作者标识']),
          const LegalP('每月满足活跃条件（6 项任意 3 项）自动续期。'),

          const LegalH2('七、流量分成'),
          const LegalBullets([
            '分成池：每月从会员收入中提取 15-20% 作为创作者基金',
            '结算日：每月 1 日结算上月收益',
            '提现门槛：满 ¥50 可申请提现',
            '手续费：平台收取 10%',
            '到账时间：1-3 个工作日',
            '支持微信/支付宝/银行卡收款',
          ]),

          const LegalH2('八、免责声明'),
          const LegalBullets([
            '极梦不对用户发布内容的真实性负责',
            '极梦不对因不可抗力导致的服务中断承担责任',
            '极梦不对用户间交易或纠纷负责',
          ]),

          const LegalH2('九、协议变更'),
          const LegalP('我们可能更新本协议。重大变更将提前 30 天通知用户。继续使用即表示同意更新后的协议。'),

          const LegalH2('十、争议解决'),
          const LegalP(
            '本协议受中华人民共和国法律管辖。如发生争议，双方应友好协商解决。协商不成的，提交上海市有管辖权的人民法院诉讼解决。',
          ),

          const LegalH2('十一、联系我们'),
          const LegalP('上海既白观海科技有限公司'),
          const LegalContactLine('邮箱', 'support@dreamingpolar.com'),
          const LegalContactLine('网址', 'https://dreamingpolar.com'),

          const LegalFooter(),
        ],
      ),
    );
  }
}
