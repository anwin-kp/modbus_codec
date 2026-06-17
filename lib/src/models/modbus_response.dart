/// Base type for every decoded Modbus response.
///
/// A [ModbusResponse] is the clean, structured result of decoding raw bytes
/// received from a device. Use `is` checks (or pattern matching) to narrow to
/// a concrete subtype:
///
/// ```dart
/// final response = ModbusDecoder.decode(rawBytes);
/// if (response is ReadRegistersResponse) {
///   final raw = response.registers; // List<int> of uint16 values
/// }
/// ```
sealed class ModbusResponse {
  /// The slave / unit id the response came from.
  final int slaveId;

  /// The Modbus function code of the response.
  final int functionCode;

  const ModbusResponse({required this.slaveId, required this.functionCode});
}

/// Decoded reply to a read of 16-bit registers (FC 03 holding, FC 04 input).
///
/// [registers] holds the raw unsigned 16-bit values exactly as transmitted
/// (big-endian on the wire, already combined here). Apply any signed / 32-bit
/// / scaling / ASCII interpretation yourself — see `ModbusConvert`.
final class ReadRegistersResponse extends ModbusResponse {
  /// The raw unsigned 16-bit register values, in order.
  final List<int> registers;

  /// Creates a register read response.
  const ReadRegistersResponse({
    required super.slaveId,
    required super.functionCode,
    required this.registers,
  });

  @override
  String toString() =>
      'ReadRegistersResponse(slaveId: $slaveId, registers: $registers)';
}

/// Decoded reply to a read of 1-bit values (FC 01 coils, FC 02 discrete inputs).
///
/// [values] contains exactly [requestedQuantity] booleans, LSB-first, trimmed
/// to the count originally requested. `values[0]` is the first coil/input
/// requested; there are no trailing padding bits.
final class ReadBitsResponse extends ModbusResponse {
  /// The number of coils / discrete inputs that were requested.
  ///
  /// Equals `values.length`. Carried here so callers can verify the response
  /// matches their request without retaining the original quantity separately.
  final int requestedQuantity;

  /// The expanded boolean values, in request order.
  ///
  /// Length is always [requestedQuantity] — padding bits from the final packed
  /// byte are stripped.
  final List<bool> values;

  /// Creates a bit (coil / discrete input) read response.
  const ReadBitsResponse({
    required super.slaveId,
    required super.functionCode,
    required this.requestedQuantity,
    required this.values,
  });

  @override
  String toString() =>
      'ReadBitsResponse(slaveId: $slaveId, requestedQuantity: $requestedQuantity, '
      'values: $values)';
}

/// Decoded echo reply to FC 05 (write single coil) or FC 06 (write single
/// register).
final class WriteSingleResponse extends ModbusResponse {
  /// The address that was written.
  final int address;

  /// The value echoed back by the device.
  ///
  /// For FC 06 this is the 16-bit register value. For FC 05 it is the raw coil
  /// value (`0xFF00` for ON, `0x0000` for OFF); use [coilState] for a boolean.
  final int value;

  /// Creates a single-write echo response.
  const WriteSingleResponse({
    required super.slaveId,
    required super.functionCode,
    required this.address,
    required this.value,
  });

  /// Interprets [value] as a coil state (`true` when `0xFF00`).
  bool get coilState => value == 0xFF00;

  @override
  String toString() => 'WriteSingleResponse(slaveId: $slaveId, '
      'fn: 0x${functionCode.toRadixString(16)}, address: $address, value: $value)';
}

/// Decoded reply to FC 15 (write multiple coils) or FC 16 (write multiple
/// registers).
final class WriteMultipleResponse extends ModbusResponse {
  /// The starting address that was written.
  final int startAddress;

  /// The number of coils / registers written.
  final int quantity;

  /// Creates a multiple-write response.
  const WriteMultipleResponse({
    required super.slaveId,
    required super.functionCode,
    required this.startAddress,
    required this.quantity,
  });

  @override
  String toString() => 'WriteMultipleResponse(slaveId: $slaveId, '
      'fn: 0x${functionCode.toRadixString(16)}, startAddress: $startAddress, '
      'quantity: $quantity)';
}
