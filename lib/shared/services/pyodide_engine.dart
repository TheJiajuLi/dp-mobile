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
result = pd.read_sql_query("""$sql""", conn)
conn.close()
result
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
