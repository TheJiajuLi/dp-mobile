import 'package:flutter/material.dart';

// iPad（宽度>=600）判定的唯一入口——全项目要判断"是不是平板布局"都用这一个
// 方法，断点数值只在这一处维护，不要在各个页面里各自写 600 这个数字
class Responsive {
  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 600;
  }
}
