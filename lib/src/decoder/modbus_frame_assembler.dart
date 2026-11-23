import '../models/modbus_exception.dart';
import 'modbus_decoder.dart';

/// Reassembles complete Modbus RTU response frames from chunks of bytes.
///
/// BLE notifications are limited by the connection MTU (often 20 bytes), so a
/// response to a larger read arrives in several pieces. Feed every piece to
/// [add]; it returns each frame as soon as all of its bytes have arrived:
///
/// ```dart
/// final assembler = ModbusFrameAssembler();
///
/// characteristic.onValueReceived.listen((chunk) {
///   for (final frame in assembler.add(chunk)) {
///     final response = ModbusDecoder.decode(frame);
///     // ...
///   }
/// });
/// ```
///
/// If a response never completes (e.g. the device stopped mid-frame), call
/// [reset] from your request timeout so the next response starts cleanly.
class ModbusFrameAssembler {
  final List<int> _buffer = [];

  /// Creates an empty assembler.
  ModbusFrameAssembler();

  /// Number of bytes received so far that do not yet form a complete frame.
  int get bufferedLength => _buffer.length;

  /// Whether part of a frame is waiting for more bytes.
  bool get hasPartialFrame => _buffer.isNotEmpty;

  /// Appends [chunk] and returns every frame that is now complete, in order.
  ///
  /// Returns an empty list while a frame is still incomplete. Bytes left over
  /// after a complete frame are kept as the start of the next one.
  ///
  /// Throws [ModbusFrameException] if the buffered bytes cannot be the start
  /// of a supported response (unknown function code, or a value outside
  /// 0..255). The buffer is cleared before throwing, so the assembler is ready
  /// for the next response.
  List<List<int>> add(List<int> chunk) {
    _buffer.addAll(chunk);
    final frames = <List<int>>[];
    while (true) {
      final int? length;
      try {
        length = ModbusDecoder.expectedLength(_buffer);
      } on ModbusFrameException {
        _buffer.clear();
        rethrow;
      }
      if (length == null || _buffer.length < length) break;
      frames.add(List<int>.of(_buffer.getRange(0, length)));
      _buffer.removeRange(0, length);
    }
    return frames;
  }

  /// Discards any partially received frame.
  void reset() => _buffer.clear();
}
