import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import '../constants/app_constants.dart';
import 'api_response.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  final Dio dio;
  final _storage = const FlutterSecureStorage();

  ApiClient()
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 如果调用方已显式设置了 Authorization，不覆盖
          if (options.headers.containsKey('Authorization')) {
            return handler.next(options);
          }
          final userId = await _storage.read(key: AppConstants.keyCurrentUserId);
          if (userId != null && userId.isNotEmpty) {
            final token = await _storage.read(key: AppConstants.keyToken(userId));
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
      ),
    );
    dio.interceptors.add(
      PrettyDioLogger(
        requestBody: true,
        responseBody: true,
        compact: true,
        maxWidth: 120,
        logPrint: (obj) {
          final str = obj.toString();
          // 截断 base64 图片数据，避免日志被一大坨 base64 刷屏
          final truncated = str.replaceAllMapped(
            RegExp(r'(data:image/[^;]+;base64,)[A-Za-z0-9+/=]{50,}'),
            (m) => '${m.group(1)}[base64 截断...]',
          );
          debugPrint(truncated);
        },
      ),
    );
  }

  Future<ApiResponse<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final res = await dio.get(path, queryParameters: queryParameters);
      return ApiResponse.success(res.data, statusCode: res.statusCode);
    } on DioException catch (e) {
      return ApiResponse.error(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<ApiResponse<dynamic>> post(String path, {dynamic data}) async {
    try {
      final res = await dio.post(path, data: data);
      return ApiResponse.success(res.data, statusCode: res.statusCode);
    } on DioException catch (e) {
      return ApiResponse.error(_message(e), statusCode: e.response?.statusCode);
    }
  }

  // 显式传入 token，不依赖拦截器读取本地存储
  // 用于登录流程中 userId 尚未落盘、拦截器还找不到 token 的场景
  Future<ApiResponse<dynamic>> getWithToken(String path, {required String token}) async {
    try {
      final res = await dio.get(
        path,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ApiResponse.success(res.data, statusCode: res.statusCode);
    } on DioException catch (e) {
      return ApiResponse.error(_message(e), statusCode: e.response?.statusCode);
    }
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '网络连接超时';
      case DioExceptionType.connectionError:
        return '网络连接失败';
      default:
        return e.message ?? '请求失败';
    }
  }
}
