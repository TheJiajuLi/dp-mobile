import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../auth/auth_service.dart';

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
      appBar: AppBar(
        title: Text(l10n.loginHistory),
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? Center(
              child: Text(l10n.noLoginHistoryYet, style: const TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (ctx, i) {
                final record = _history[i];
                final ts = record['time'] as int? ?? 0;
                final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
                final isNow = i == 0;
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
                      color: isNow ? const Color(0xFF6366F1) : Colors.grey,
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
                        record['location'] as String? ?? l10n.unknownLocation,
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF0FF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            l10n.currentDeviceLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : null,
                );
              },
            ),
    );
  }
}
