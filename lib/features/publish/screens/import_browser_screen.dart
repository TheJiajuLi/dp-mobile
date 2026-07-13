import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 内置浏览器导入——URL 直接抓取（/auth/import/url）在知乎/公众号这类
// 反爬平台经常吃闭门羹（403），这个是给这种情况用的备选方案：用户在
// 这个内嵌浏览器里自己登录/翻到想导入的文章页，点"导入"。
//
// 现在**不再把原始 HTML 发给后端**——直接在页面里注入一段 JS，就地把已经
// 渲染好的 DOM 抠成结构化 blocks（知乎走 .Post-RichText 精准解析：标题/
// 段落/行内公式 ztext-math/独立公式块/代码/图片/列表都分门别类；其它站点
// 走 article>main>常见容器的通用 fallback），JSON.stringify 后回传，Flutter
// jsonDecode 直接拿去发布页用，整条链路不经后端、也绕开了反爬。
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
              // WebView 原生初始化到 loadData 引导页跑完这段空档，安卓/iOS
              // 底层默认背景是纯黑，看起来像"闪一下黑屏"——WebView 本身设
              // transparentBackground，外面套一层跟 Scaffold 同色的
              // Container 兜底，这段空档也是页面背景色，不再露黑
              child: Container(
                color: isDark
                    ? const Color(0xFF0A0A0F)
                    : const Color(0xFFF5F5F5),
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
                    transparentBackground: true,
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
                      // 之前用默认 OutlineInputBorder——一圈实心描边+
                      // 聚焦时整圈变紫，跟这个页面其它地方（顶部网址栏/
                      // 快捷链接都是"填充色胶囊、不描边"）不是一套语言，
                      // 显得像个没改过样式的原生Material控件。改成同一套
                      // 填充胶囊，只在聚焦时给一圈很淡的品牌色提示，不是
                      // 一整圈实描边
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? const Color(0xFFE0E2F0)
                              : const Color(0xFF1A1A1A),
                        ),
                        decoration: InputDecoration(
                          hintText: '输入网址...',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 18,
                            color: Colors.grey[400],
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF111118)
                              : const Color(0xFFF5F5F5),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: const Color(
                                0xFF6366F1,
                              ).withValues(alpha: 0.25),
                              width: 1,
                            ),
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
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6366F1),
                      ),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _loadUrl(ctrl.text);
                      },
                      child: const Text(
                        '前往',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
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

  // 在页面里注入 JS 就地把 DOM 抠成结构化 blocks 回传，不经后端。
  // 注意：图片 block 的 URL 写在 imageUrl 字段（EditorBlock.fromJson 和
  // 编辑器渲染都读 imageUrl，不是 content），顺带也塞一份到 content 兜底
  Future<void> _doImport() async {
    final ctrl = _webCtrl;
    if (ctrl == null) return;
    setState(() => _importing = true);

    try {
      final result = await ctrl.evaluateJavascript(
        source: r'''
(function() {
  const url = window.location.href;
  const hostname = window.location.hostname;

  // 代码块 language 归一化——先按别名映射，再用白名单兜底，任何不认识的
  // 值都降级到 python，跟 block_card.dart 的 _codeLanguages 保持一致，避免
  // 导入后编辑器里语言下拉 value 匹配不到 item 崩溃
  const langMap = {
    'text': 'python', 'plaintext': 'plaintext',
    'js': 'javascript', 'ts': 'typescript',
    'py': 'python', 'rb': 'python',
    'sh': 'bash', 'shell': 'bash', 'zsh': 'bash',
    'yml': 'yaml',
  };
  const validLangs = [
    'python', 'javascript', 'typescript', 'jsx', 'tsx', 'sql', 'html', 'css',
    'json', 'yaml', 'bash', 'shell', 'markdown', 'dart', 'java', 'kotlin',
    'swift', 'rust', 'go', 'r', 'cpp', 'c', 'plaintext',
  ];
  function normLang(raw) {
    const low = (raw || 'python').toLowerCase();
    const mapped = langMap[low] || low;
    return validLangs.includes(mapped) ? mapped : 'python';
  }

  // ── 知乎文章 ──
  // 触发条件放宽成"知乎域名 + 存在 .Post-RichText 正文容器"——原来强绑
  // h1.Post-Title，专栏/回答/新版页面标题类名不同就会漏掉、掉进通用
  // fallback 把公式搞坏。标题选择器同时多路兜底
  if (hostname.includes('zhihu.com') && document.querySelector('.Post-RichText')) {
    const title = document.querySelector('h1.Post-Title')?.innerText?.trim()
      || document.querySelector('h1.QuestionHeader-title')?.innerText?.trim()
      || document.querySelector('.Post-Title')?.innerText?.trim()
      || document.querySelector('h1')?.innerText?.trim()
      || document.title.replace(/\s*[-_|].*$/, '').trim()
      || '';

    const coverEl = document.querySelector('.Post-Header img[src*="zhimg.com"]');
    const coverImage = coverEl ? coverEl.src.split('?')[0] : null;

    const container = document.querySelector('.Post-RichText');
    if (!container) {
      return JSON.stringify({ error: '未找到文章正文，请确认已打开文章详情页' });
    }

    const blocks = [];
    let idCounter = 0;
    const genId = () => 'b' + (++idCounter) + '_' + Date.now();

    // 提取混合内容（文字 + 行内 LaTeX）
    function extractMixed(el) {
      let text = '';
      el.childNodes.forEach(node => {
        if (node.nodeType === 3) {
          text += node.textContent || '';
        } else if (node.nodeType === 1) {
          const cls = node.className || '';
          if (cls.includes('ztext-math')) {
            const tex = node.getAttribute('data-tex') || '';
            if (tex) text += ' $' + tex + '$ ';
          } else if (cls.includes('RichContent-EntityWord')) {
            node.querySelectorAll('svg').forEach(s => s.remove());
            text += node.textContent || '';
          } else {
            text += extractMixed(node);
          }
        }
      });
      return text;
    }

    function processEl(el) {
      const tag = el.tagName?.toLowerCase();
      if (!tag) return;
      if (tag === 'hr') return;

      if (tag === 'h2' || tag === 'h3') {
        const content = extractMixed(el).trim();
        if (content) {
          blocks.push({ id: genId(), type: 'heading', content: content, level: tag === 'h2' ? 2 : 3 });
        }
        return;
      }

      if (tag === 'ul' || tag === 'ol') {
        el.querySelectorAll('li').forEach(li => {
          const content = extractMixed(li).trim();
          if (content) blocks.push({ id: genId(), type: 'text', content: '• ' + content });
        });
        return;
      }

      if (tag === 'li') {
        const content = extractMixed(el).trim();
        if (content) blocks.push({ id: genId(), type: 'text', content: '• ' + content });
        return;
      }

      if (tag === 'figure') {
        const img = el.querySelector('img.zh-lightbox-thumb, img');
        if (img) {
          const src = img.getAttribute('data-original') || img.src || '';
          if (src && src.includes('zhimg.com')) {
            blocks.push({ id: genId(), type: 'image', content: src, imageUrl: src });
          }
        }
        return;
      }

      if (tag === 'img') {
        const src = el.getAttribute('data-original') || el.src || '';
        if (src && src.includes('zhimg.com')) {
          blocks.push({ id: genId(), type: 'image', content: src, imageUrl: src });
        }
        return;
      }

      if (tag === 'pre') {
        const codeEl = el.querySelector('code');
        const code = (codeEl || el).innerText.trim();
        if (code) {
          const langClass = (codeEl?.className || '');
          const langMatch = langClass.match(/language-(\w+)/);
          blocks.push({ id: genId(), type: 'code', content: code, language: normLang(langMatch ? langMatch[1] : 'python') });
        }
        return;
      }

      if (tag === 'p') {
        const children = Array.from(el.children).filter(c => c.tagName !== 'SCRIPT');
        const onlyMath = children.length === 1 && children[0].className?.includes('ztext-math');
        const hasOtherText = el.childNodes && Array.from(el.childNodes).some(n => n.nodeType === 3 && n.textContent.trim());

        if (onlyMath && !hasOtherText) {
          const tex = children[0].getAttribute('data-tex') || '';
          if (tex.trim()) blocks.push({ id: genId(), type: 'latex', content: tex.trim() });
          return;
        }

        const content = extractMixed(el).trim();
        if (content) blocks.push({ id: genId(), type: 'text', content: content });
        return;
      }

      if (tag === 'div' || tag === 'section') {
        Array.from(el.children).forEach(processEl);
        return;
      }
    }

    Array.from(container.children).forEach(processEl);

    const firstText = blocks.find(b => b.type === 'text');
    const summary = firstText ? firstText.content.slice(0, 120) : '';

    return JSON.stringify({
      title, summary, blocks,
      cover_image: coverImage,
      source_url: url,
      platform: 'zhihu',
      block_count: blocks.length
    });
  }

  // ── 其它平台通用提取 ──
  // 通用版混合内容提取：跟知乎 extractMixed 一样用 textContent（不用
  // innerText——innerText 会按渲染布局把 KaTeX 公式的字形逐个拆成一行，
  // 就是"一个字符一行"乱码的根因），并优先读公式元素的 data-tex 源码
  // 输出 $...$，跳过 SVG / katex 字形容器避免把渲染字形重复吐出来
  function extractMixedGeneral(el) {
    let text = '';
    el.childNodes.forEach(node => {
      if (node.nodeType === 3) {
        text += node.textContent || '';
      } else if (node.nodeType === 1) {
        const tag = node.tagName ? node.tagName.toLowerCase() : '';
        // SVG / script / style 放最前跳过——SVG 的 className 不是普通
        // 字符串，先拦掉免得后面 .includes 抛错；MathJax 的
        // <script type="math/tex"> 例外，要取里面的源码
        if (tag === 'svg' || tag === 'script' || tag === 'style') {
          if (tag === 'script' && (node.type || '').includes('math/tex')) {
            const tex = node.textContent || '';
            if (tex.trim()) text += ' $' + tex.trim() + '$ ';
          }
          return;
        }
        const cls = typeof node.className === 'string' ? node.className : '';
        // 带 data-tex 的公式元素（KaTeX/知乎 ztext-math/通用）直接取源码
        if (node.hasAttribute('data-tex')) {
          const tex = node.getAttribute('data-tex');
          if (tex) text += ' $' + tex + '$ ';
          return;
        }
        if (cls.includes('ztext-math')) {
          const tex = node.getAttribute('data-tex') || '';
          if (tex) text += ' $' + tex + '$ ';
          return;
        }
        // KaTeX/MathJax 渲染容器：源码在带 data-tex 的祖先上已取过，整棵
        // 子树跳过，不然会把渲染字形一个个吐出来
        if (cls.includes('katex') || cls.includes('MathJax') || cls.includes('mjx-')) {
          return;
        }
        text += extractMixedGeneral(node);
      }
    });
    return text;
  }

  const container = document.querySelector('article')
    || document.querySelector('main')
    || document.querySelector('.content, #content, .article')
    || document.body;

  const title = document.querySelector('h1')?.innerText?.trim() || document.title || '';

  const blocks = [];
  let id = 0;

  container.querySelectorAll('h1,h2,h3,p,pre,li,img,figure').forEach(el => {
    const tag = el.tagName.toLowerCase();
    // 跳过嵌套在 pre 里的非 pre 元素
    if (el.closest('pre') && tag !== 'pre') return;

    if (tag === 'h1' || tag === 'h2' || tag === 'h3') {
      const content = extractMixedGeneral(el).trim();
      if (content) {
        blocks.push({ id: 'g' + (++id), type: 'heading', content: content, level: parseInt(tag[1]) });
      }
    } else if (tag === 'pre') {
      // 代码保留 innerText——要的就是它按行渲染的换行
      const code = el.innerText.trim();
      if (code) blocks.push({ id: 'g' + (++id), type: 'code', content: code, language: 'python' });
    } else if (tag === 'p') {
      // 独立公式段落（只有一个公式元素、没有其它正文）→ latex block
      const mathEl = el.querySelector('[data-tex]');
      const allChildren = Array.from(el.children).filter(c => c.tagName !== 'SCRIPT');
      if (mathEl && allChildren.length === 1 &&
          !el.textContent.trim().replace(mathEl.textContent, '').trim()) {
        const tex = mathEl.getAttribute('data-tex') || '';
        if (tex.trim()) {
          blocks.push({ id: 'g' + (++id), type: 'latex', content: tex.trim() });
          return;
        }
      }
      const content = extractMixedGeneral(el).trim();
      if (content.length > 5) {
        blocks.push({ id: 'g' + (++id), type: 'text', content: content });
      }
    } else if (tag === 'li') {
      const content = extractMixedGeneral(el).trim();
      if (content) blocks.push({ id: 'g' + (++id), type: 'text', content: '• ' + content });
    } else if (tag === 'img') {
      const src = el.src || '';
      if (src.startsWith('http')) {
        blocks.push({ id: 'g' + (++id), type: 'image', content: src, imageUrl: src });
      }
    }
  });

  const summary = blocks.find(b => b.type === 'text')?.content.slice(0, 120) || '';

  return JSON.stringify({
    title, summary, blocks,
    cover_image: null,
    source_url: url,
    platform: 'general',
    block_count: blocks.length
  });
})()
''',
      );

      if (result == null) {
        _showError('提取失败，请重试');
        return;
      }

      final data = jsonDecode(result.toString()) as Map<String, dynamic>;

      if (data['error'] != null) {
        _showError(data['error'] as String);
        return;
      }

      if ((data['blocks'] as List?)?.isEmpty ?? true) {
        _showError('没提取到内容，请确认已打开文章详情页');
        return;
      }

      // 不再调后端接口，直接把结构化 blocks 返回给发布页
      if (mounted) Navigator.pop(context, data);
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
