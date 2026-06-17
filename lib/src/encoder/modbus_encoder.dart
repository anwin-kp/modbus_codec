import '../constants/function_codes.dart';
import '../crc/crc16_modbus.dart';

/// Encodes Modbus RTU request frames from high-level intent.
///
/// Every method returns a complete RTU frame as a `List<int>` ready to send
/// over the transport (BLE characteristic write, serial port, TCP socket,
/// etc.):
///
/// ```
/// [slaveId] [functionCode] [ ...payload... ] [crcLow] [crcHigh]
/// ```
///
/// Addresses and quantities are encoded big-endian (high byte first), as
/// required by Modbus. The trailing CRC-16/MODBUS is little-endian, also per
/// spec. You provide meaningful values; this class produces the raw bytes.
abstract final class ModbusEncoder {
  /// Encodes FC 01 — Read Coils.
  ///
  /// Reads [quantity] coils (1–2000) starting at [startAddress] from [slaveId].
  static List<int> readCoils({
    required int slaveId,
    required int startAddress,
    required int quantity,
  }) =>
      _readRequest(
        slaveId: slaveId,
        functionCode: ModbusFunctionCode.readCoils,
        startAddress: startAddress,
        quantity: quantity,
        maxQuantity: 2000,
      );

  /// Encodes FC 02 — Read Discrete Inputs.
  ///
  /// Reads [quantity] discrete inputs (1–2000) starting at [startAddress].
  static List<int> readDiscreteInputs({
    required int slaveId,
    required int startAddress,
    required int quantity,
  }) =>
      _readRequest(
        slaveId: slaveId,
        functionCode: ModbusFunctionCode.readDiscreteInputs,
        startAddress: startAddress,
        quantity: quantity,
        maxQuantity: 2000,
      );

  /// Encodes FC 03 — Read Holding Registers.
  ///
  /// Reads [quantity] registers (1–125) starting at [startAddress].
  static List<int> readHoldingRegisters({
    required int slaveId,
    required int startAddress,
    required int quantity,
  }) =>
      _readRequest(
        slaveId: slaveId,
        functionCode: ModbusFunctionCode.readHoldingRegisters,
        startAddress: startAddress,
        quantity: quantity,
        maxQuantity: 125,
      );

  /// Encodes FC 04 — Read Input Registers.
  ///
  /// Reads [quantity] registers (1–125) starting at [startAddress].
  static List<int> readInputRegisters({
    required int slaveId,
    required int startAddress,
    required int quantity,
  }) =>
      _readRequest(
        slaveId: slaveId,
        functionCode: ModbusFunctionCode.readInputRegisters,
        startAddress: startAddress,
        quantity: quantity,
        maxQuantity: 125,
      );

  /// Encodes FC 05 — Write Single Coil.
  ///
  /// [value] `true` turns the coil ON (`0xFF00`), `false` OFF (`0x0000`).
  ///
  /// **Broadcast note:** `slaveId` 0 is a valid broadcast address per the
  /// Modbus spec, but devices must not send a response to broadcast writes.
  /// Do not call `ModbusDecoder.decode` after a broadcast request.
  static List<int> writeSingleCoil({
    required int slaveId,
    required int address,
    required bool value,
  }) {
    _checkSlaveId(slaveId);
    _checkAddress(address);
    final coilValue =
        value ? ModbusFunctionCode.coilOn : ModbusFunctionCode.coilOff;
    return _frame([
      slaveId,
      ModbusFunctionCode.writeSingleCoil,
      ..._u16(address),
      ..._u16(coilValue),
    ]);
  }

  /// Encodes FC 06 — Write Single Holding Register.
  ///
  /// [value] is the raw 16-bit value to write (0–65535). Pre-scale any
  /// engineering value before calling — e.g. `pH 6.70 -> 670`.
  ///
  /// **Broadcast note:** `slaveId` 0 is a valid broadcast address per the
  /// Modbus spec, but devices must not send a response to broadcast writes.
  /// Do not call `ModbusDecoder.decode` after a broadcast request.
  static List<int> writeSingleRegister({
    required int slaveId,
    required int address,
    required int value,
  }) {
    _checkSlaveId(slaveId);
    _checkAddress(address);
    _checkU16(value, 'value', index: null);
    return _frame([
      slaveId,
      ModbusFunctionCode.writeSingleRegister,
      ..._u16(address),
      ..._u16(value),
    ]);
  }

  /// Encodes FC 15 (0x0F) — Write Multiple Coils.
  ///
  /// [values] must contain 1–1968 entries.
  ///
  /// **Broadcast note:** `slaveId` 0 is a valid broadcast address per the
  /// Modbus spec, but devices must not send a response to broadcast writes.
  /// Do not call `ModbusDecoder.decode` after a broadcast request.
  static List<int> writeMultipleCoils({
    required int slaveId,
    required int startAddress,
    required List<bool> values,
  }) {
    _checkSlaveId(slaveId);
    _checkAddress(startAddress);
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', 'must not be empty');
    }
    if (values.length > 1968) {
      throw ArgumentError.value(
        values.length,
        'values',
        'exceeds the Modbus limit of 1968 coils per FC 15 write '
            '(got ${values.length})',
      );
    }
    final byteCount = (values.length + 7) ~/ 8;
    final packed = List<int>.filled(byteCount, 0);
    for (var i = 0; i < values.length; i++) {
      if (values[i]) {
        packed[i ~/ 8] |= 1 << (i % 8);
      }
    }
    return _frame([
      slaveId,
      ModbusFunctionCode.writeMultipleCoils,
      ..._u16(startAddress),
      ..._u16(values.length),
      byteCount,
      ...packed,
    ]);
  }

  /// Encodes FC 16 (0x10) — Write Multiple Holding Registers.
  ///
  /// Each entry of [values] is a raw 16-bit value (0–65535). [values] must
  /// contain 1–123 entries.
  ///
  /// **Broadcast note:** `slaveId` 0 is a valid broadcast address per the
  /// Modbus spec, but devices must not send a response to broadcast writes.
  /// Do not call `ModbusDecoder.decode` after a broadcast request.
  static List<int> writeMultipleRegisters({
    required int slaveId,
    required int startAddress,
    required List<int> values,
  }) {
    _checkSlaveId(slaveId);
    _checkAddress(startAddress);
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', 'must not be empty');
    }
    if (values.length > 123) {
      throw ArgumentError.value(
        values.length,
        'values',
        'exceeds the Modbus limit of 123 registers per FC 16 write '
            '(got ${values.length})',
      );
    }
    final data = <int>[];
    for (var i = 0; i < values.length; i++) {
      _checkU16(values[i], 'values', index: i);
      data.addAll(_u16(values[i]));
    }
    return _frame([
      slaveId,
      ModbusFunctionCode.writeMultipleRegisters,
      ..._u16(startAddress),
      ..._u16(values.length),
      values.length * 2,
      ...data,
    ]);
  }

  // --- internals -----------------------------------------------------------

  static List<int> _readRequest({
    required int slaveId,
    required int functionCode,
    required int startAddress,
    required int quantity,
    required int maxQuantity,
  }) {
    _checkSlaveId(slaveId);
    _checkAddress(startAddress);
    if (quantity <= 0 || quantity > maxQuantity) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'must be in range 1..$maxQuantity (got $quantity)',
      );
    }
    return _frame([
      slaveId,
      functionCode,
      ..._u16(startAddress),
      ..._u16(quantity),
    ]);
  }

  /// Splits a 16-bit value into `[high, low]` (big-endian).
  static List<int> _u16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

  /// Appends the CRC and returns the complete frame.
  static List<int> _frame(List<int> pdu) => [...pdu, ...Crc16Modbus.bytes(pdu)];

  static void _checkSlaveId(int slaveId) {
    if (slaveId < 0 || slaveId > 247) {
      throw ArgumentError.value(
        slaveId,
        'slaveId',
        'must be in range 0..247 (got $slaveId)',
      );
    }
  }

  static void _checkAddress(int address) {
    if (address < 0 || address > 0xFFFF) {
      throw ArgumentError.value(
        address,
        'address',
        'must be in range 0x0000..0xFFFF (got $address)',
      );
    }
  }

  static void _checkU16(int value, String name, {required int? index}) {
    if (value < 0 || value > 0xFFFF) {
      final label = index != null ? '$name[$index]' : name;
      throw ArgumentError.value(
        value,
        label,
        'must be in range 0..65535 (got $value)',
      );
    }
  }
}
