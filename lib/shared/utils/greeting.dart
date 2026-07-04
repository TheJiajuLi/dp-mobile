// 按当前小时分时段问候，首页/Notebook 首页共用，避免同一套分段逻辑抄两遍
String greetingText() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return '早上好';
  if (hour >= 12 && hour < 14) return '中午好';
  if (hour >= 14 && hour < 18) return '下午好';
  if (hour >= 18 && hour < 22) return '晚上好';
  return '夜深了';
}

String greetingSubtext() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return '新的一天，从容开始。';
  if (hour >= 12 && hour < 14) return '午后时光，慢慢来。';
  if (hour >= 14 && hour < 18) return '下午好，状态怎么样？';
  if (hour >= 18 && hour < 22) return '忙了一天，辛苦了。';
  return '早点睡吧。';
}
