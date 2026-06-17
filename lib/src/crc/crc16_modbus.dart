/// CRC-16/MODBUS checksum.
///
/// Implements the standard Modbus RTU CRC: polynomial `0xA001` (reflected
/// `0x8005`), initial value `0xFFFF`, no final XOR, input and output
/// reflected. This is the checksum appended to every Modbus RTU frame.
///
/// The on-the-wire byte order for an RTU frame is **low byte first, then high
/// byte** (little-endian), which is what [bytes] returns.
abstract final class Crc16Modbus {
  /// Computes the raw 16-bit CRC value over [data].
  static int compute(List<int> data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      crc ^= byte & 0xFF;
      for (var bit = 0; bit < 8; bit++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// Computes the CRC over [data] and returns it as the 2 bytes appended to a
  /// Modbus RTU frame, in transmission order: `[lowByte, highByte]`.
  static List<int> bytes(List<int> data) {
    final crc = compute(data);
    return [crc & 0xFF, (crc >> 8) & 0xFF];
  }

  /// Returns `true` if [frame] (a complete RTU frame whose last two bytes are
  /// the CRC) carries a valid checksum.
  ///
  /// Returns `false` for frames shorter than 3 bytes.
  static bool isValid(List<int> frame) {
    if (frame.length < 3) return false;
    final payload = frame.sublist(0, frame.length - 2);
    final expected = bytes(payload);
    return frame[frame.length - 2] == expected[0] &&
        frame[frame.length - 1] == expected[1];
  }
}
