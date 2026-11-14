// Tells when an ESP32 is restarting over and over, so the app can say so once instead of reporting every
// unplug and replug. Two signs, either is enough:
//  - the USB port drops and comes back again within a few seconds (the ESP32-S3's own USB restarts with the chip);
//  - the boot ROM keeps printing "rst:0x…" lines, or "invalid header" (a brand-new board with nothing in flash).
// It does no I/O: the USB link feeds it port drops and serial text (usb_link_windows.dart).

/// Why the board keeps restarting.
enum BootLoopReason {
  /// Nothing (or nothing valid) in flash: the ROM prints "invalid header" and tries again. A brand-new board does this.
  empty,

  /// The sketch crashes or resets the chip as soon as it starts.
  crash,
}

class BootLoopDetector {
  BootLoopDetector({
    this.window = const Duration(seconds: 8),
    this.quiet = const Duration(seconds: 12),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// Restarts are counted over this long.
  final Duration window;

  /// The loop is over once the board has been quiet (no drop, no boot message) for this long.
  final Duration quiet;
  final DateTime Function() _now;

  final _drops = <DateTime>[];
  final _boots = <DateTime>[];
  final _blank = <DateTime>[];
  DateTime? _lastSign;
  DateTime? _lastBlank;
  String _partial = '';

  /// True from the moment a loop is seen until the board has been quiet for [quiet].
  bool looping = false;
  BootLoopReason reason = BootLoopReason.crash;

  static final _rst = RegExp(r'\brst:0x[0-9a-fA-F]+');

  /// The USB port went away (the board restarted, or was unplugged). Returns the reason if this starts a loop.
  BootLoopReason? onDrop() {
    final now = _now();
    _drops.add(now);
    _lastSign = now;
    _prune(now);
    return _drops.length >= 2 ? _start(now) : null;
  }

  /// Text from the board's serial port. Returns the reason if this starts a loop.
  BootLoopReason? onText(String text) {
    final now = _now();
    final all = _partial + text;
    final lines = all.split('\n');
    _partial = lines.removeLast();
    if (_partial.length > 400) _partial = _partial.substring(_partial.length - 400);
    BootLoopReason? started;
    for (final line in lines) {
      final blank = line.contains('invalid header');
      if (blank) {
        _blank.add(now);
        _lastBlank = now;
      }
      if (_rst.hasMatch(line)) _boots.add(now);
      if (blank || _rst.hasMatch(line)) _lastSign = now;
    }
    _prune(now);
    if (_boots.length >= 3 || _blank.length >= 2) started = _start(now);
    return started;
  }

  /// Call now and then. True when a loop has just ended (the board stayed up and quiet).
  bool settle() {
    final last = _lastSign;
    if (!looping || last == null) return false;
    if (_now().difference(last) < quiet) return false;
    reset();
    return true;
  }

  /// Forget everything (after a successful upload, or when the board is disconnected).
  void reset() {
    looping = false;
    _drops.clear();
    _boots.clear();
    _blank.clear();
    _partial = '';
    _lastSign = null;
    _lastBlank = null;
  }

  BootLoopReason? _start(DateTime now) {
    final last = _lastBlank;
    reason = last != null && now.difference(last) <= window ? BootLoopReason.empty : BootLoopReason.crash;
    if (looping) return null; // already reported
    looping = true;
    return reason;
  }

  void _prune(DateTime now) {
    bool old(DateTime t) => now.difference(t) > window;
    _drops.removeWhere(old);
    _boots.removeWhere(old);
    _blank.removeWhere(old);
  }
}
