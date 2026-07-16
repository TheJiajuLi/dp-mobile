import 'package:shared_preferences/shared_preferences.dart';

// 创作设置里「AI 偏好语言」(creator_ai_lang: zh / en / zh-en) 落地到小梦的
// 实际回答语言：所有生成式 AI 调用（极索问答 / 帮我写 / 解释代码 / 解释公式）
// 发请求前，把这段语言指令拼在 prompt 最前，让回答语言跟着设置走。不改后端，
// 只在前端拼提示；每次调用即读即用 SharedPreferences，改了设置不用重启 App。
// 三个值都给显式指令（含默认中文）——这样即使 base prompt 里不再写死"中文"，
// 语言也始终有唯一确定的来源，不靠模型猜
Future<String> aiLangHint() async {
  final prefs = await SharedPreferences.getInstance();
  switch (prefs.getString('creator_ai_lang') ?? 'zh') {
    case 'en':
      return '[Please respond in English.]\n';
    case 'zh-en':
      return '[请用中英混合：专业术语保留英文，其余用中文。]\n';
    default: // zh
      return '[请用简体中文。]\n';
  }
}
