import 'dart:ui';

Size initialWindowSize(List<String> arguments) {
  final pattern = RegExp(r'^--window-size=(\d+)x(\d+)$');
  for (final argument in arguments) {
    final match = pattern.firstMatch(argument);
    if (match == null) continue;
    final width = double.parse(match.group(1)!).clamp(680, 2400).toDouble();
    final height = double.parse(match.group(2)!).clamp(540, 1600).toDouble();
    return Size(width, height);
  }
  return const Size(980, 720);
}
