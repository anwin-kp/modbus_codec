import '../constants/function_codes.dart';
import '../crc/crc16_modbus.dart';
import '../models/modbus_exception.dart';
import '../models/modbus_response.dart';

/// Decodes raw Modbus RTU response bytes into structured [ModbusResponse]s.
///
/// This is the receive path: hand it the bytes that arrived from the device
/// (e.g. from a BLE characteristic notification) and get back clean, typed
/// data. The decoder never interprets the *meaning* of registers — it returns
/// raw 16-bit values and expanded booleans. Apply scaling, sign, 32-bit
/// combination or ASCII decoding yourself via `ModbusConvert`.
abstract final class ModbusDecoder {
  /// Decodes a complete RTU response [frame].
  ///
  /// By default the trailing CRC is validated; pass [validateCrc] `false` for
  /// transports that already guarantee integrity (e.g. Modbus TCP wrapped
  /// payloads) or during testing.
  ///
  /// Throws:
  ///  * [ModbusDeviceException] if the device returned an exception response.
  ///  * [ModbusFrameException] if the frame is malformed or fails CRC.
  static ModbusResponse decode(List<int> frame, {bool validateCrc = true}) {
    if (frame.length < 4) {
      throw ModbusFrameException(
        'Frame too short: expected at least 4 bytes, got ${frame.length}.',
        frame,
      );
    }

    if (validateCrc && !Crc16Modbus.isValid(frame)) {
      throw ModbusFrameException('CRC check failed.', frame);
    }

    final slaveId = frame[0];
    final functionCode = frame[1];

    // Exception response: function code has the high (0x80) bit set.
    if ((functionCode & ModbusFunctionCode.errorMask) != 0) {
      throw ModbusDeviceException(
        slaveId: slaveId,
        functionCode: functionCode & ~ModbusFunctionCode.errorMask,
        exceptionCode: frame[2],
      );
    }

    // Payload sits between the 2-byte header and the 2-byte trailing CRC.
    final payload = frame.sublist(2, frame.length - 2);

    switch (functionCode) {
      case ModbusFunctionCode.readHoldingRegisters:
      case ModbusFunctionCode.readInputRegisters:
        return _decodeReadRegisters(slaveId, functionCode, payload, frame);

      case ModbusFunctionCode.readCoils:
      case ModbusFunctionCode.readDiscreteInputs:
        return _decodeReadBits(slaveId, functionCode, payload, frame);

      case ModbusFunctionCode.writeSingleCoil:
      case ModbusFunctionCode.writeSingleRegister:
        return _decodeWriteSingle(slaveId, functionCode, payload, frame);

      case ModbusFunctionCode.writeMultipleCoils:
      case ModbusFunctionCode.writeMultipleRegisters:
        return _decodeWriteMultiple(slaveId, functionCode, payload, frame);

      default:
        throw ModbusFrameException(
          'Unsupported function code: 0x${functionCode.toRadixString(16)}.',
          frame,
        );
    }
  }

  // --- per-function decoders ----------------------------------------------

  static ReadRegistersResponse _decodeReadRegisters(
    int slaveId,
    int functionCode,
    List<int> payload,
    List<int> frame,
  ) {
    // payload: [byteCount][data...]
    final byteCount = payload[0];
    final data = payload.sublist(1);
    if (data.length != byteCount || byteCount.isOdd) {
      throw ModbusFrameException(
        'Register byte count mismatch: header says $byteCount, '
        'got ${data.length} data bytes.',
        frame,
      );
    }
    final registers = <int>[];
    for (var i = 0; i + 1 < data.length; i += 2) {
      registers.add((data[i] << 8) | data[i + 1]); // big-endian
    }
    return ReadRegistersResponse(
      slaveId: slaveId,
      functionCode: functionCode,
      registers: registers,
    );
  }

  static ReadBitsResponse _decodeReadBits(
    int slaveId,
    int functionCode,
    List<int> payload,
    List<int> frame,
  ) {
    // payload: [byteCount][packed bits...]
    final byteCount = payload[0];
    final data = payload.sublist(1);
    if (data.length != byteCount) {
      throw ModbusFrameException(
        'Bit byte count mismatch: header says $byteCount, '
        'got ${data.length} data bytes.',
        frame,
      );
    }
    final values = <bool>[];
    for (final byte in data) {
      for (var bit = 0; bit < 8; bit++) {
        values.add((byte & (1 << bit)) != 0); // LSB first
      }
    }
    return ReadBitsResponse(
      slaveId: slaveId,
      functionCode: functionCode,
      values: values,
    );
  }

  static WriteSingleResponse _decodeWriteSingle(
    int slaveId,
    int functionCode,
    List<int> payload,
    List<int> frame,
  ) {
    // payload: [addrHi][addrLo][valHi][valLo]
    if (payload.length != 4) {
      throw ModbusFrameException(
        'Write-single response expects 4 payload bytes, got ${payload.length}.',
        frame,
      );
    }
    return WriteSingleResponse(
      slaveId: slaveId,
      functionCode: functionCode,
      address: (payload[0] << 8) | payload[1],
      value: (payload[2] << 8) | payload[3],
    );
  }

  static WriteMultipleResponse _decodeWriteMultiple(
    int slaveId,
    int functionCode,
    List<int> payload,
    List<int> frame,
  ) {
    // payload: [addrHi][addrLo][qtyHi][qtyLo]
    if (payload.length != 4) {
      throw ModbusFrameException(
        'Write-multiple response expects 4 payload bytes, got ${payload.length}.',
        frame,
      );
    }
    return WriteMultipleResponse(
      slaveId: slaveId,
      functionCode: functionCode,
      startAddress: (payload[0] << 8) | payload[1],
      quantity: (payload[2] << 8) | payload[3],
    );
  }
}
