import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  int _fileCount = 0;
  int _totalBytes = 0;
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // ApiClient.get 内部吞掉了 DioException，不会抛异常——失败与否要看
    // res.success，不能只靠 try/catch。另外实测 GET /auth/files 返回的是
    // 裸数组 [...]，不是 {files: [...]}
    final res = await ref.read(apiClientProvider).get('/auth/files');
    if (!res.success || res.data == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final files = (res.data as List).cast<Map<String, dynamic>>();
    final total = files.fold<int>(
      0,
      (sum, f) => sum + ((f['size_bytes'] as num?)?.toInt() ?? 0),
    );
    if (!mounted) return;
    setState(() {
      _files = files;
      _fileCount = files.length;
      _totalBytes = total;
      _loading = false;
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    const maxBytes = 1024 * 1024 * 1024; // 1GB
    final usedPercent = _totalBytes / maxBytes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('云端存储'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8F8F8),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // 存储概览卡片
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cloud_outlined, color: Color(0xFF6366F1)),
                          const SizedBox(width: 8),
                          const Text(
                            '存储空间',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text(
                            '${_formatSize(_totalBytes)} / 1GB',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: usedPercent.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.grey[100],
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF6366F1)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_fileCount 个文件',
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                // 文件列表
                if (_files.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '文件列表',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    color: Colors.white,
                    child: Column(
                      children: _files.map((f) {
                        final name = f['filename'] as String? ?? '未知文件';
                        final size = (f['size_bytes'] as num?)?.toInt() ?? 0;
                        final ext = name.contains('.')
                            ? name.split('.').last.toLowerCase()
                            : '';
                        final icon =
                            const {
                              'jpg': Icons.image_outlined,
                              'jpeg': Icons.image_outlined,
                              'png': Icons.image_outlined,
                              'mp4': Icons.videocam_outlined,
                              'mp3': Icons.audio_file_outlined,
                              'pdf': Icons.picture_as_pdf,
                              'csv': Icons.table_chart_outlined,
                            }[ext] ??
                            Icons.insert_drive_file_outlined;

                        return ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF0FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(icon, color: const Color(0xFF6366F1), size: 20),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _formatSize(size),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ] else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('还没有上传文件', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
              ],
            ),
    );
  }
}
