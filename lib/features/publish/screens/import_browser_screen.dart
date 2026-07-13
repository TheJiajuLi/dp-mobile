import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

// 内置浏览器导入——URL 直接抓取（/auth/import/url）在知乎/公众号这类
// 反爬平台经常吃闭门羹（403），这个是给这种情况用的备选方案：用户在
// 这个内嵌浏览器里自己登录/翻到想导入的文章页，点"导入"，直接把当前
// 页面已经渲染好的完整 DOM（document.documentElement.outerHTML）发给
// 后端解析——不再依赖服务器自己发请求抓页面，天然绕开反爬。
//
// 实测确认（2026-07-13）后端 /auth/import/html 只吃 {html, source_url}
// 两个字段，不接受 title/cover_image/platform——它固定用通用的
// extractBlocks 解析，不会走知乎专用的 parseZhihuContent（那套只在
// /auth/import/url 里根据自动探测的 platform 触发），所以这里不用再
// 费劲用知乎专属的 querySelector('.Post-Title')/('.Post-RichText') 去
// 精确抠内容——抓整页 HTML 直接扔给后端，后端自己按 article > main >
// 常见正文容器 > body 的顺序找正文，效果一样，代码还更简单
class ImportBrowserScreen extends ConsumerStatefulWidget {
  const ImportBrowserScreen({super.key});

  @override
  ConsumerState<ImportBrowserScreen> createState() =>
      _ImportBrowserScreenState();
}

// 起始页几个快捷入口——跟 _showUrlInput 底部弹窗里的快捷链接是同一份
const _quickLinks = [
  ('知乎', 'https://www.zhihu.com', '专业问答'),
  ('微信公众号', 'https://mp.weixin.qq.com', '公众号文章'),
  ('掘金', 'https://juejin.cn', '技术社区'),
  ('CSDN', 'https://www.csdn.net', '技术博客'),
];

class _ImportBrowserScreenState extends ConsumerState<ImportBrowserScreen> {
  InAppWebViewController? _webCtrl;
  // 起始页不再直接打开知乎——about:blank + onWebViewCreated 里
  // loadData 一个中性的"选择文章来源"引导页，用户自己点想去的平台，
  // 不替用户做选择
  String _currentUrl = '';
  bool _importing = false;
  // 导入横幅是否可点——不能只看 _currentUrl 是否非空：知乎是 SPA 路由，
  // onLoadStop 的 url 参数在这种客户端跳转下经常拿不到准确值，
  // _currentUrl 可能一直显示"没更新"，但 WebView 其实早就换了内容。
  // 只要真的发生过一次有效导航（不管后续 URL 显示准不准）就该允许点
  bool _hasNavigated = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0A0F)
          : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: isDark ? const Color(0xFF111118) : const Color(0xFFF5F5F5),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        color: isDark
                            ? const Color(0xFFAAA0A0)
                            : Colors.grey[600],
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _showUrlInput,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF17171F)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : const Color(0xFFEBEBEB),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _currentUrl.isEmpty
                                      ? Icons.search
                                      : Icons.lock,
                                  size: 12,
                                  color: _currentUrl.isEmpty
                                      ? Colors.grey[400]
                                      : const Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    _currentUrl.isEmpty
                                        ? '输入网址或选择下方来源'
                                        : _urlHost(_currentUrl),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _currentUrl.isEmpty
                                          ? Colors.grey[400]
                                          : (isDark
                                                ? const Color(0xFFE0E2F0)
                                                : const Color(0xFF555555)),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_outlined),
                        onPressed: () => _webCtrl?.reload(),
                        color: isDark
                            ? const Color(0xFFAAA0A0)
                            : Colors.grey[600],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    // 还没发生过任何一次有效导航时点了也是抓引导页自己
                    // 的 HTML，没有意义，禁掉——判断依据是 _hasNavigated
                    // 不是 _currentUrl.isEmpty，后者在知乎这类 SPA 路由
                    // 站点上经常拿不到准确值，两者不是一回事
                    onTap: (_importing || !_hasNavigated) ? null : _doImport,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: (_importing || !_hasNavigated)
                            ? Colors.grey[400]
                            : const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _importing
                                ? Icons.hourglass_empty
                                : Icons.auto_awesome,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _importing
                                  ? '正在提取文章内容...'
                                  : !_hasNavigated
                                  ? '先选择或输入文章来源'
                                  : '导入当前页面的文章',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (!_importing)
                            const Icon(
                              Icons.download_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri('about:blank')),
                initialSettings: InAppWebViewSettings(
                  userAgent:
                      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
                      'AppleWebKit/605.1.15 (KHTML, like Gecko) '
                      'Version/17.0 Mobile/15E148 Safari/604.1',
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  allowsInlineMediaPlayback: true,
                ),
                onWebViewCreated: (ctrl) {
                  _webCtrl = ctrl;
                  ctrl.loadData(
                    data: _guideHtml,
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  );
                },
                // 单靠 onLoadStop 的 url 参数不可靠——知乎是 SPA 路由，
                // 客户端跳转经常不触发一次干净的"整页加载完成"事件，
                // 或者事件触发了但参数拿到的还是旧 URL。四路一起盯：
                // 1) onLoadStop 主动用 ctrl.getUrl() 查一遍，不信参数
                // 2) onUpdateVisitedHistory 专门抓 SPA 的 pushState 跳转
                // 3) shouldOverrideUrlLoading 拦截跳转的最早时机，同时
                //    顺手拦掉"在App内打开"这种 zhihu://等 scheme 跳转
                //    （不拦的话知乎会试图拉起知乎App，内置浏览器直接被晾在原地）
                // 4) onLoadStart 加载一开始就更新，不用等加载完
                onLoadStart: (ctrl, url) => _updateUrl(url?.toString()),
                onLoadStop: (ctrl, url) async {
                  final u = await ctrl.getUrl();
                  _updateUrl(u?.toString());
                },
                onUpdateVisitedHistory: (ctrl, url, isReload) async {
                  final u = await ctrl.getUrl();
                  _updateUrl(u?.toString());
                },
                shouldOverrideUrlLoading: (ctrl, action) async {
                  final u = action.request.url?.toString() ?? '';
                  // "在App内打开"拦截——不让它跳去 zhihu://weixin:// 这类
                  // App scheme，内置浏览器留在原地，不然知乎会试图拉起App
                  if (u.startsWith('zhihu://') ||
                      u.startsWith('snssdk') ||
                      u.startsWith('weixin://')) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  _updateUrl(u);
                  return NavigationActionPolicy.ALLOW;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // about:blank/空字符串不算真的"导航到了一个页面"，_currentUrl 留空
  // 继续显示引导态；其它任何非空 URL 都视为一次有效导航，_hasNavigated
  // 一旦置 true 就不会再变回 false（用户就算导航回引导页也已经证明过
  // WebView 是好的，没必要再让导入横幅灰回去）
  void _updateUrl(String? url) {
    final u = url ?? '';
    if (u.isEmpty || u.startsWith('about:')) return;
    if (!mounted) return;
    setState(() {
      _currentUrl = u;
      _hasNavigated = true;
    });
  }

  String _urlHost(String url) {
    if (url.isEmpty) return '';
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  // 只是给"已经确认真实存在的" /auth/import/html 顺带带一个 platform
  // 字段——实测确认（2026-07-13）后端这个接口目前固定回 platform:
  // 'paste'，不会因为传了这个字段就切到知乎专用解析器（那套只在
  // /auth/import/url 里根据服务端自己探测的 URL 触发）。传了不会更准，
  // 但也无害，后端以后如果把这个接口也接上按 platform 分流解析，前端
  // 不用再改一次
  String _detectPlatform(String url) {
    if (url.contains('zhihu.com')) return 'zhihu';
    if (url.contains('mp.weixin.qq.com')) return 'wechat';
    return 'general';
  }

  void _showUrlInput() {
    final ctrl = TextEditingController(text: _currentUrl);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF17171F) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        decoration: const InputDecoration(
                          hintText: '输入网址...',
                          prefixIcon: Icon(Icons.search, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                        ),
                        onSubmitted: (url) {
                          Navigator.pop(sheetCtx);
                          _loadUrl(url);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _loadUrl(ctrl.text);
                      },
                      child: const Text('前往'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: _quickLinks
                      .map(
                        (l) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _quickLink(sheetCtx, l.$1, l.$2, isDark),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _quickLink(
    BuildContext sheetCtx,
    String label,
    String url,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(sheetCtx);
        _loadUrl(url);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111118) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFFE0E2F0) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }

  // 不是合法 URL 就当搜索词——用百度不用谷歌：主要用户群体在国内，
  // 谷歌在很多网络环境下直接打不开，搜索兜底选一个真的能用的
  void _loadUrl(String url) {
    var finalUrl = url.trim();
    if (finalUrl.isEmpty) return;
    if (!finalUrl.startsWith('http')) {
      finalUrl = 'https://www.baidu.com/s?wd=${Uri.encodeComponent(finalUrl)}';
    }
    _webCtrl?.loadUrl(urlRequest: URLRequest(url: WebUri(finalUrl)));
  }

  Future<void> _doImport() async {
    final ctrl = _webCtrl;
    if (ctrl == null) return;
    setState(() => _importing = true);

    try {
      final html = await ctrl.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      if (html == null || html.toString().trim().isEmpty) {
        _showError('提取失败，请重试');
        return;
      }

      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/import/html',
            data: {
              'html': html.toString(),
              'source_url': _currentUrl,
              'platform': _detectPlatform(_currentUrl),
            },
          );

      if (!res.success || res.data == null) {
        _showError(res.message ?? '解析失败');
        return;
      }

      if (mounted) Navigator.pop(context, res.data);
    } catch (e) {
      _showError('提取失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFEF4444)),
    );
  }
}

// 起始引导页——纯静态 HTML，通过 loadData 塞进 WebView，不是真的网络
// 请求。链接是普通 <a href>，点了就是正常的页面内导航，不需要额外的
// JS bridge
const _guideHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body {
    font-family: -apple-system, sans-serif;
    background: #FAFAF8;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    margin: 0;
    padding: 20px;
    box-sizing: border-box;
  }
  .title {
    font-size: 18px;
    font-weight: 600;
    color: #1A1A1A;
    margin-bottom: 8px;
    text-align: center;
  }
  .sub {
    font-size: 14px;
    color: #AAA;
    margin-bottom: 32px;
    text-align: center;
    line-height: 1.6;
  }
  .links {
    display: flex;
    flex-direction: column;
    gap: 10px;
    width: 100%;
    max-width: 300px;
  }
  a {
    display: flex;
    align-items: center;
    padding: 14px 16px;
    background: white;
    border-radius: 12px;
    border: 0.5px solid #EBEBEB;
    text-decoration: none;
    color: #1A1A1A;
    font-size: 15px;
    font-weight: 500;
  }
  .badge {
    margin-left: auto;
    font-size: 11px;
    color: #AAA;
  }
</style>
</head>
<body>
  <div class="title">选择文章来源</div>
  <div class="sub">
    在浏览器里找到你想导入的文章<br>
    点击上方紫色横幅即可导入
  </div>
  <div class="links">
    <a href="https://www.zhihu.com">知乎<span class="badge">专业问答</span></a>
    <a href="https://mp.weixin.qq.com">微信公众号<span class="badge">公众号文章</span></a>
    <a href="https://juejin.cn">掘金<span class="badge">技术社区</span></a>
    <a href="https://www.csdn.net">CSDN<span class="badge">技术博客</span></a>
  </div>
</body>
</html>
''';
