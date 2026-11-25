Duration? parseScoreDuration(String? value) {
  final parts = value?.trim().split(':');
  if (parts == null ||
      parts.isEmpty ||
      parts.length > 3 ||
      parts.any((part) => !RegExp(r'^\d{1,5}$').hasMatch(part))) {
    return null;
  }
  final numbers = parts.map(int.parse).toList();
  if (numbers.skip(1).any((number) => number >= 60)) return null;
  final seconds = numbers.length == 1
      ? numbers.single * 60
      : numbers.fold(0, (total, number) => total * 60 + number);
  return seconds > 0 ? Duration(seconds: seconds) : null;
}

String formatProgramDuration(Duration duration) {
  final minutes = duration.inMinutes % 60;
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return duration.inHours == 0
      ? '$minutes:$seconds'
      : '${duration.inHours}:${minutes.toString().padLeft(2, '0')}:$seconds';
}
