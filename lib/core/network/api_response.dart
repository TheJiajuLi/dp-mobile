class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int? statusCode;

  const ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.statusCode,
  });

  factory ApiResponse.success(T data, {int? statusCode}) =>
      ApiResponse(success: true, data: data, statusCode: statusCode);

  // data 在失败时之前一直被丢弃——后端很多错误响应会带一个结构化的
  // {message, code} 之类的 body（比如陌生人消息限制的 STRANGER_LIMIT/
  // TEXT_ONLY_LIMIT），调用方想按 code 精确识别错误类型时，之前只能靠
  // 匹配 message 文案这种脆弱的办法（message 换一个字都会失配）。这里
  // 把原始响应体透传出来，调用方能读就读，不读也不影响现有代码
  factory ApiResponse.error(String message, {int? statusCode, T? data}) =>
      ApiResponse(
        success: false,
        message: message,
        statusCode: statusCode,
        data: data,
      );
}
