import 'dart:convert';
import '../../../core/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../auth/auth_service.dart';
import '../widgets/settings_row.dart';

// 登录记录的 location 来自 IP 归属库，偶发返回繁体（如「羅湖區」）——按常见
// 地名字繁→简做一层轻量映射，界面统一简体。只覆盖地名高频字，够用即可
String _simplify(String s) {
  const map = {
    '羅': '罗',
    '錄': '录',
    '記': '记',
    '時': '时',
    '區': '区',
    '網': '网',
    '絡': '络',
    '裝': '装',
    '覽': '览',
    '瀏': '浏',
    '愛': '爱',
    '東': '东',
    '來': '来',
    '國': '国',
    '後': '后',
    '為': '为',
    '學': '学',
    '業': '业',
    '會': '会',
    '體': '体',
    '與': '与',
    '實': '实',
    '現': '现',
    '開': '开',
    '關': '关',
    '們': '们',
    '產': '产',
    '發': '发',
    '電': '电',
    '話': '话',
    '數': '数',
    '據': '据',
    '處': '处',
    '應': '应',
    '該': '该',
    '雲': '云',
    '務': '务',
    '龍': '龙',
    '讓': '让',
    '還': '还',
    '這': '这',
    '輸': '输',
    '顯': '显',
    '頁': '页',
    '邊': '边',
    '灣': '湾',
    '臺': '台',
    '縣': '县',
    '陽': '阳',
    '陝': '陕',
    '寧': '宁',
    '貴': '贵',
    '長': '长',
    '廣': '广',
  };
  return s.split('').map((c) => map[c] ?? c).join();
}

class LoginHistoryScreen extends ConsumerStatefulWidget {
  const LoginHistoryScreen({super.key});

  @override
  ConsumerState<LoginHistoryScreen> createState() => _LoginHistoryScreenState();
}

class _LoginHistoryScreenState extends ConsumerState<LoginHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = ref.read(currentUserProvider)?.id ?? '';
    final raw = prefs.getString('${userId}_login_history') ?? '[]';
    final list = List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => e as Map<String, dynamic>),
    );
    if (!mounted) return;
    setState(() {
      _history = list.reversed.toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      // AppBar 跟页面背景统一用 scaffoldBackgroundColor，不再用
      // cardColor——同一个"白色色块贴灰色背景"接缝问题，账号安全/隐私
      // 设置/关于页都已经改过，这里补齐
      appBar: AppBar(
        title: Text(l10n.loginHistory),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? Center(
              child: Text(
                l10n.noLoginHistoryYet,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          // 登录记录收进浮在页面背景上的圆角卡片，组内分割线区分——跟
          // 账号安全/隐私设置/关于页同一套视觉语言，不再是贴边到底的
          // 扁平列表。记录数本来就有限（本地存的登录历史），不需要
          // ListView.builder 的按需构建
          : ListView(
              children: [
                const SizedBox(height: 8),
                SettingsGroup(dividerIndent: 62, [
                  for (var i = 0; i < _history.length; i++)
                    _buildRow(context, l10n, _history[i], isNow: i == 0),
                ]),
              ],
            ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    AppLocalizations l10n,
    Map<String, dynamic> record, {
    required bool isNow,
  }) {
    final ts = record['time'] as int? ?? 0;
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isNow ? const Color(0xFFEEF0FF) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.phone_iphone,
          color: isNow ? AppColors.primary : Colors.grey,
          size: 20,
        ),
      ),
      title: Text(
        record['device'] as String? ?? 'iPhone',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _simplify(record['location'] as String? ?? l10n.unknownLocation),
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          Text(
            '${dt.year}-'
            '${dt.month.toString().padLeft(2, '0')}-'
            '${dt.day.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      trailing: isNow
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                l10n.currentDeviceLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }
}
