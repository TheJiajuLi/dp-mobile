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

  factory ApiResponse.error(String message, {int? statusCode}) =>
      ApiResponse(success: false, message: message, statusCode: statusCode);
}
