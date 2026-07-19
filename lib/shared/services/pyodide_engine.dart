import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';

// 复用 notebook_editor_screen.dart 里已经跑通的那套 Pyodide 引擎——同一个
// compiler.js，同一个隐藏 WebView 承载方式，同一个"整页共用一个
// onRunResult handler，靠传回来的 id 在 _pendingRuns 这个 Map 里路由结果"
// 的写法。发布页和教程详情页（可运行代码块）都要跑代码，与其各写一份
// 几乎一样的 WebView/JS桥接代码，抽成这一个共享类。
//
// 2026-07-15 起改成 App 级单例（见下面 pyodideEngineProvider）——之前
// Notebook/发布页/教程详情页三处各自持有一份独立实例，各自的隐藏
// WebView 都要重新拉一次 compiler.js+Pyodide（几秒到十几秒），且教程
// 详情页更夸张：一篇文章有几个可运行代码块，TutorialCodeBlock 就建几个
// 独立实例。改成全局共享一个实例、一个隐藏 WebView，挂在 main.dart 的
// MaterialApp.builder 里，App 启动就开始预热，真正打开这几个页面时
// Pyodide 大概率已经就绪。全局共享意味着 Python 解释器的全局命名空间
// 是跨页面共用的——Notebook 内部同一个 notebook 的多个 cell 之间本来就
// 依赖这个共享状态（后面的 cell 用前面 cell 产出的变量），这不是新引入
// 的风险；唯一的新情况是"看完一个教程的代码块后打开 Notebook"这种跨
// 页面场景，理论上会带着上一个页面遗留的全局变量，但不会崩溃，语义上
// 跟真实 Jupyter kernel 没重启是一回事
class PyodideEngine {
  InAppWebViewController? _webCtrl;
  bool webReady = false;
  // R 内核（webR/WASM）——跟 Pyodide 在同一个隐藏 WebView 里并行预热。
  // webRReady=已就绪可跑；webRFailed=初始化失败（比如这个 WebView 环境不支持
  // webR 的 channel），此时 R 走 fail-open 回落到 comingSoon 提示，不硬报错
  bool webRReady = false;
  bool webRFailed = false;
  // R 内核状态（供 UI 小指示用）：0=加载中 / 1=就绪 / 2=不可用。跟上面两个 bool
  // 同步更新，但这个是可监听的，R Cell 头部能实时反映
  final ValueNotifier<int> rStatus = ValueNotifier(0);
  final Map<String, Completer<String>> _pendingRuns = {};
  final VoidCallback? onReady;

  PyodideEngine({this.onReady});

  static const _compilerHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width">
</head>
<body>
<script type="module">
import { compile } from
  'https://dreamingpolar.com/components/compiler/compiler.js';

window.runCode = async (code, lang) => {
  try {
    const outputs = await compile(code, lang);
    return JSON.stringify(outputs);
  } catch(e) {
    return JSON.stringify([{
      type: 'error',
      content: String(e)
    }]);
  }
};

setTimeout(() => {
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('compilerReady');
  }
}, 1000);

// ── R 内核（webR / WASM）——跟 Pyodide 并行预热，仿 window.runCode 的模式 ──
// 这个 initialData 页面拿不到 COOP/COEP 头（没有 crossOriginIsolated），
// SharedArrayBuffer 不可用，所以用 PostMessage channel（webR 唯一不依赖 SAB /
// service worker 的通道）。init 失败就 callHandler('rFailed') 让 Flutter 侧
// fail-open 回落 comingSoon
let webR = null, webRReadyFlag = false;
(async () => {
  try {
    const mod = await import('https://webr.r-wasm.org/latest/webr.mjs');
    const chan = (mod.ChannelType && mod.ChannelType.PostMessage != null)
      ? mod.ChannelType.PostMessage : 3;
    webR = new mod.WebR({ channelType: chan });
    await webR.init();
    webRReadyFlag = true;
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('rReady');
    }
  } catch(e) {
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('rFailed', String(e));
    }
  }
})();

// 跑一段 R 代码：captureR 收 stdout/stderr + 图形（grDevices canvas 设备），
// 图形 ImageBitmap 画进 canvas 转 base64 PNG。统一返回 [{type,content}]
window.runR = async (code) => {
  if (!webR || !webRReadyFlag) {
    return JSON.stringify([{type:'error', content:'R kernel not ready'}]);
  }
  const shelter = await new webR.Shelter();
  try {
    const cap = await shelter.captureR(code, {
      withAutoprint: true,
      captureStreams: true,
      captureConditions: false,
      captureGraphics: { width: 504, height: 504 }
    });
    const outputs = [];
    const text = (cap.output || [])
      .filter(o => o.type === 'stdout' || o.type === 'stderr')
      .map(o => o.data).join('\\n');
    if (text.trim()) outputs.push({type:'text', content: text});
    for (const img of (cap.images || [])) {
      try {
        const c = document.createElement('canvas');
        c.width = img.width; c.height = img.height;
        c.getContext('2d').drawImage(img, 0, 0);
        outputs.push({type:'image', content: c.toDataURL('image/png').split(',')[1]});
      } catch(_) {}
    }
    if (outputs.length === 0) outputs.push({type:'text', content:''});
    return JSON.stringify(outputs);
  } catch(e) {
    return JSON.stringify([{type:'error', content: String(e)}]);
  } finally {
    try { shelter.purge(); } catch(_) {}
  }
};
</script>
</body>
</html>
''';

  // 只给出一个 1x1 大小的 WebView 本体，不在这里套 Positioned——调用方
  // 有的是在自己的 Stack 里把它藏到屏幕外（发布页那种整页 Stack 布局），
  // 有的只是塞进一个 Column 当不可见的最后一个子节点（教程详情页每个
  // 代码块自带一份引擎），Positioned 只能直接放在 Stack 下面，写死在
  // 这里会导致后一种用法直接报错
  Widget buildHiddenWebView() {
    return SizedBox(
      width: 1,
      height: 1,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: _compilerHtml,
          baseUrl: WebUri('https://dreamingpolar.com'),
        ),
        onWebViewCreated: (ctrl) {
          _webCtrl = ctrl;
          ctrl.addJavaScriptHandler(
            handlerName: 'compilerReady',
            callback: (args) {
              webReady = true;
              onReady?.call();
            },
          );
          ctrl.addJavaScriptHandler(
            handlerName: 'onRunResult',
            callback: (args) {
              final id = args.isNotEmpty ? args[0].toString() : '';
              final result = args.length > 1 ? args[1].toString() : '[]';
              _pendingRuns[id]?.complete(result);
            },
          );
          ctrl.addJavaScriptHandler(
            handlerName: 'rReady',
            callback: (args) {
              webRReady = true;
              rStatus.value = 1;
            },
          );
          ctrl.addJavaScriptHandler(
            handlerName: 'rFailed',
            callback: (args) {
              webRFailed = true;
              rStatus.value = 2;
            },
          );
        },
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
      ),
    );
  }

  // compiler.js 的 compile() 实际只吃 python，SQL 这个"语言"是客户端自己
  // 文本拼出来的 python 脚本，不是 compile() 真的认识一个叫 sql 的语言
  String _wrapSql(String sql) =>
      '''
import sqlite3, pandas as pd, io
conn = sqlite3.connect(':memory:')
try:
    df.to_sql('df', conn, if_exists='replace', index=False)
except Exception:
    pass
# 多语句：按分号拆开分别执行（read_sql_query 一次只吃一条）——CREATE/INSERT 等
# 走 execute+commit，SELECT/WITH/PRAGMA 走 read_sql_query，展示最后一条查询结果
_stmts = [s.strip() for s in """$sql""".split(';') if s.strip()]
result = None
for _s in _stmts:
    _u = _s.lstrip().upper()
    if _u.startswith('SELECT') or _u.startswith('WITH') or _u.startswith('PRAGMA'):
        result = pd.read_sql_query(_s, conn)
    else:
        conn.execute(_s)
        conn.commit()
conn.close()
result if result is not None else print("✓ 执行完成")
''';

  // 中文输入法/键盘智能标点常把 ' " - : ; 变成全角/弯版本，直接丢进
  // Python/JS 会语法错。运行前静默替换回 ASCII 等价物（编辑器里已禁用智能
  // 标点，这里是二次兜底：粘贴进来的、历史存下来的弯引号也一并救回）
  String _sanitizeCode(String code) => code
      .replaceAll('‘', "'") // ‘ 弯单引号
      .replaceAll('’', "'") // ’
      .replaceAll('“', '"') // “ 弯双引号
      .replaceAll('”', '"') // ”
      .replaceAll('—', '--') // — 破折号
      .replaceAll('：', ':') // ： 全角冒号
      .replaceAll('；', ';'); // ； 全角分号

  Future<List<Map<String, dynamic>>> run(
    String id,
    String code,
    String language,
    AppLocalizations l10n, {
    // Notebook 的 cell 可能首次 import pandas/matplotlib 这类重量级包，
    // 冷加载经常超过 30 秒，调用方可以按场景传更宽的超时——默认值维持
    // 原来这个类的 30 秒，不动其它调用方的既有行为
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // 运行前清理中文输入法/智能标点带进来的全角标点——弯引号/破折号/全角
    // 冒号分号会让 Python 直接语法错，静默替换成 ASCII 等价物
    code = _sanitizeCode(code);
    if (language == 'html' || language == 'markdown') {
      return [
        {'type': 'info', 'content': l10n.unsupportedCellType},
      ];
    }
    if (language == 'javascript') {
      return runJavaScript(code);
    }

    if (_webCtrl == null) {
      return [
        {'type': 'error', 'content': l10n.envInitializing},
      ];
    }
    // compiler.js 首次要拉 Pyodide，可能需要几秒到十几秒——耐心等最多
    // 60 秒，而不是直接判失败，这是"运行完成（无输出）"假阳性问题的
    // 根因之一，不能在这里重蹈覆辙
    if (!webReady) {
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (webReady) break;
      }
      if (!webReady) {
        return [
          {'type': 'error', 'content': l10n.loadTimeoutRestart},
        ];
      }
    }

    final effectiveCode = language == 'sql' ? _wrapSql(code) : code;

    try {
      final completer = Completer<String>();
      _pendingRuns[id] = completer;

      await _webCtrl!.evaluateJavascript(
        source:
            '''
(async () => {
  try {
    if (typeof window.runCode !== 'function') {
      window.flutter_inappwebview.callHandler(
        'onRunResult', ${jsonEncode(id)},
        JSON.stringify([{type:'error', content:'compiler not ready'}])
      );
      return;
    }
    const outputs = await window.runCode(${jsonEncode(effectiveCode)}, "python");
    window.flutter_inappwebview.callHandler(
      'onRunResult', ${jsonEncode(id)}, outputs
    );
  } catch(e) {
    window.flutter_inappwebview.callHandler(
      'onRunResult', ${jsonEncode(id)},
      JSON.stringify([{type:'error', content: String(e)}])
    );
  }
})();
''',
      );

      final raw = await completer.future.timeout(
        timeout,
        onTimeout: () => jsonEncode([
          {'type': 'error', 'content': l10n.execTimeout},
        ]),
      );

      dynamic parsed;
      try {
        parsed = jsonDecode(raw);
      } catch (_) {
        return [
          {'type': 'text', 'content': raw},
        ];
      }
      final outputs = parsed is List ? parsed : [parsed];
      return outputs
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } finally {
      _pendingRuns.remove(id);
    }
  }

  // 跑 R（webR）——跟 run() 同一套异步范式：evaluateJavascript 调 window.runR，
  // 结果经 onRunResult handler + Completer 按 id 回来。webR 未就绪就等（首次要拉
  // R WASM+包，给足 90 秒）；初始化失败 fail-open 回落 comingSoon 提示
  Future<List<Map<String, dynamic>>> runR(
    String id,
    String code,
    AppLocalizations l10n, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    code = _sanitizeCode(code);
    if (_webCtrl == null || webRFailed) {
      return [
        {'type': 'info', 'content': l10n.langSupportComingSoon('R')},
      ];
    }
    if (!webRReady) {
      for (var i = 0; i < 90; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (webRReady || webRFailed) break;
      }
      if (webRFailed) {
        return [
          {'type': 'info', 'content': l10n.langSupportComingSoon('R')},
        ];
      }
      if (!webRReady) {
        return [
          {'type': 'error', 'content': l10n.loadTimeoutRestart},
        ];
      }
    }
    try {
      final completer = Completer<String>();
      _pendingRuns[id] = completer;
      await _webCtrl!.evaluateJavascript(
        source:
            '''
(async () => {
  try {
    if (typeof window.runR !== 'function') {
      window.flutter_inappwebview.callHandler(
        'onRunResult', ${jsonEncode(id)},
        JSON.stringify([{type:'error', content:'R kernel not ready'}])
      );
      return;
    }
    const outputs = await window.runR(${jsonEncode(code)});
    window.flutter_inappwebview.callHandler(
      'onRunResult', ${jsonEncode(id)}, outputs
    );
  } catch(e) {
    window.flutter_inappwebview.callHandler(
      'onRunResult', ${jsonEncode(id)},
      JSON.stringify([{type:'error', content: String(e)}])
    );
  }
})();
''',
      );
      final raw = await completer.future.timeout(
        timeout,
        onTimeout: () => jsonEncode([
          {'type': 'error', 'content': l10n.execTimeout},
        ]),
      );
      dynamic parsed;
      try {
        parsed = jsonDecode(raw);
      } catch (_) {
        return [
          {'type': 'text', 'content': raw},
        ];
      }
      final outputs = parsed is List ? parsed : [parsed];
      return outputs
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } finally {
      _pendingRuns.remove(id);
    }
  }

  // 跟 Notebook _runJavaScript 同款：捕获 console.log 输出，返回值统一走
  // JSON.stringify，避免不同平台 evaluateJavascript 对返回对象编组不一致
  Future<List<Map<String, dynamic>>> runJavaScript(String code) async {
    if (_webCtrl == null) return [];
    code = _sanitizeCode(code); // JS 直接调这里的路径也要清弯引号（幂等）
    try {
      final wrappedCode =
          '''
(function() {
  const logs = [];
  const _log = console.log;
  console.log = (...args) => {
    logs.push(args.map(a =>
      typeof a === 'object' ? JSON.stringify(a) : String(a)
    ).join(' '));
    _log(...args);
  };
  try {
    $code
    console.log = _log;
    return JSON.stringify({ok: true, output: logs.join('\\n')});
  } catch(e) {
    console.log = _log;
    return JSON.stringify({ok: false, error: e.message});
  }
})()
''';
      final result = await _webCtrl!.evaluateJavascript(source: wrappedCode);
      if (result == null) {
        return [
          {'type': 'text', 'content': ''},
        ];
      }
      final map = jsonDecode(result.toString()) as Map;
      if (map['ok'] == true) {
        return [
          {'type': 'text', 'content': (map['output'] as String?) ?? ''},
        ];
      }
      return [
        {
          'type': 'error',
          'content': map['error']?.toString() ?? 'unknown error',
        },
      ];
    } catch (e) {
      return [
        {'type': 'error', 'content': '$e'},
      ];
    }
  }
}

// App 级单例——整个 App 生命周期只有这一个实例、一个隐藏 WebView，
// 挂载点见 main.dart（MaterialApp.builder 里）
final pyodideEngineProvider = Provider<PyodideEngine>((ref) => PyodideEngine());
