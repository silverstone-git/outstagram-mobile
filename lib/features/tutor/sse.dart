import 'dart:convert';

/// One Server-Sent Event: `event:` name and the JSON `data:` payload.
class SseEvent {
  const SseEvent(this.event, this.data);
  final String event;
  final Map<String, dynamic> data;
}

/// Splits a byte stream into SSE events (blank-line separated blocks). Multi-line `data:` fields are
/// joined with `\n`; `\r\n` line ends are accepted; blocks without an event name or JSON data are skipped.
Stream<SseEvent> decodeSse(Stream<List<int>> bytes) async* {
  var buf = '';
  await for (final chunk in bytes.cast<List<int>>().transform(utf8.decoder)) {
    buf += chunk.replaceAll('\r\n', '\n');
    int i;
    while ((i = buf.indexOf('\n\n')) >= 0) {
      final block = buf.substring(0, i);
      buf = buf.substring(i + 2);
      final ev = _parse(block);
      if (ev != null) yield ev;
    }
  }
  final tail = _parse(buf.trim());
  if (tail != null) yield tail;
}

SseEvent? _parse(String block) {
  String? event;
  final data = <String>[];
  for (final line in block.split('\n')) {
    if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).startsWith(' ') ? line.substring(6) : line.substring(5));
    }
  }
  if (event == null || data.isEmpty) return null;
  try {
    final decoded = jsonDecode(data.join('\n'));
    return SseEvent(event, decoded is Map ? Map<String, dynamic>.from(decoded) : {'value': decoded});
  } on FormatException {
    return null;
  }
}
