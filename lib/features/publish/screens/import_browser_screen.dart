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

class _ImportBrowserScreenState extends ConsumerState<ImportBrowserScreen> {
  InAppWebViewController? _webCtrl;
  String _currentUrl = 'https://www.zhihu.com';
  bool _importing = false;

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
              color: isDark
                  ? const Color(0xFF111118)
                  : const Color(0xFFF5F5F5),
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
                              const Icon(
                                Icons.lock,
                                size: 12,
                                color: Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  _urlHost(_currentUrl),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? const Color(0xFFE0E2F0)
                                        : const Color(0xFF555555),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
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
                    onTap: _importing ? null : _doImport,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: _importing
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
                              _importing ? '正在提取文章内容...' : '看到想导入的文章了？点这里',
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
                initialUrlRequest: URLRequest(
                  url: WebUri(_currentUrl),
                ),
                initialSettings: InAppWebViewSettings(
                  userAgent:
                      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
                      'AppleWebKit/605.1.15 (KHTML, like Gecko) '
                      'Version/17.0 Mobile/15E148 Safari/604.1',
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  allowsInlineMediaPlayback: true,
                ),
                onWebViewCreated: (ctrl) => _webCtrl = ctrl,
                onLoadStop: (ctrl, url) {
                  if (!mounted) return;
                  setState(() => _currentUrl = url?.toString() ?? _currentUrl);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _urlHost(String url) {
    if (url.isEmpty) return 'zhihu.com';
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
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
            data: {'html': html.toString(), 'source_url': _currentUrl},
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
