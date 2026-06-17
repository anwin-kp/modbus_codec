import '../constants/function_codes.dart';

/// Thrown when a frame cannot be parsed because it is malformed.
///
/// This indicates a transport or framing problem (truncated bytes, a CRC
/// mismatch, an inconsistent byte count) — not a device-reported error. For a
/// device-reported error (exception response) see [ModbusDeviceException].
class ModbusFrameException implements Exception {
  /// A human-readable description of why the frame is invalid.
  final String message;

  /// The raw bytes that failed to parse, when available.
  final List<int>? frame;

  /// Creates a frame exception with [message] and the offending [frame].
  const ModbusFrameException(this.message, [this.frame]);

  @override
  String toString() => 'ModbusFrameException: $message';
}

/// Thrown when the device returns a Modbus exception (error) response.
///
/// The device understood the frame but refused or could not fulfil it. The
/// [functionCode] is the original request's function code (the `0x80` error
/// bit is already stripped), and [exceptionCode] is one of
/// [ModbusExceptionCode].
class ModbusDeviceException implements Exception {
  /// The slave / unit id that produced the error.
  final int slaveId;

  /// The original function code (error bit stripped).
  final int functionCode;

  /// The device-supplied exception code, see [ModbusExceptionCode].
  final int exceptionCode;

  /// Creates a device exception.
  const ModbusDeviceException({
    required this.slaveId,
    required this.functionCode,
    required this.exceptionCode,
  });

  /// A human-readable description of [exceptionCode].
  String get description => ModbusExceptionCode.describe(exceptionCode);

  @override
  String toString() =>
      'ModbusDeviceException(slaveId: $slaveId, fn: 0x${functionCode.toRadixString(16)}, '
      'code: 0x${exceptionCode.toRadixString(16)}): $description';
}
