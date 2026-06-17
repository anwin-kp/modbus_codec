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
      final expected = Crc16Modbus.bytes(frame.sublist(0, frame.length - 2));
      final got = frame.sublist(frame.length - 2);
      throw ModbusFrameException(
        'CRC check failed: expected '
        '0x${expected[0].toRadixString(16).padLeft(2, '0')}'
        '${expected[1].toRadixString(16).padLeft(2, '0')}, '
        'got '
        '0x${got[0].toRadixString(16).padLeft(2, '0')}'
        '${got[1].toRadixString(16).padLeft(2, '0')}.',
        frame,
      );
    }

    final slaveId = frame[0];
    final functionCode = frame[1];

    // Exception response: function code has the high (0x80) bit set.
    if ((functionCode & ModbusFunctionCode.errorMask) != 0) {
      if (frame.length < 5) {
        throw ModbusFrameException(
          'Exception response too short: expected at least 5 bytes '
          '(slaveId + errorFn + exceptionCode + 2-byte CRC), '
          'got ${frame.length}.',
          frame,
        );
      }
      throw ModbusDeviceException(
        slaveId: slaveId,
        functionCode: functionCode & ~ModbusFunctionCode.errorMask,
        exceptionCode: frame[2],
      );
    }

    // Payload sits between the 2-byte header and the 2-byte trailing CRC.
    final payload = frame.sublist(2, frame.length - 2);

    // Minimum frame sizes per function (header 2 + payload + CRC 2):
    // Read responses: 2 + 1 (byteCount) + ≥2 data + 2 = ≥7 bytes minimum.
    // Write-single/multiple echo: 2 + 4 payload + 2 = 8 bytes exactly.
    const writeSingleMin = 8;
    const writeMultipleMin = 8;

    switch (functionCode) {
      case ModbusFunctionCode.readHoldingRegisters:
      case ModbusFunctionCode.readInputRegisters:
        return _decodeReadRegisters(slaveId, functionCode, payload, frame);

      case ModbusFunctionCode.readCoils:
      case ModbusFunctionCode.readDiscreteInputs:
        return _decodeReadBits(slaveId, functionCode, payload, frame);

      case ModbusFunctionCode.writeSingleCoil:
      case ModbusFunctionCode.writeSingleRegister:
        if (frame.length < writeSingleMin) {
          throw ModbusFrameException(
            'Write-single response too short: expected at least '
            '$writeSingleMin bytes, got ${frame.length}.',
            frame,
          );
        }
        return _decodeWriteSingle(slaveId, functionCode, payload, frame);

      case ModbusFunctionCode.writeMultipleCoils:
      case ModbusFunctionCode.writeMultipleRegisters:
        if (frame.length < writeMultipleMin) {
          throw ModbusFrameException(
            'Write-multiple response too short: expected at least '
            '$writeMultipleMin bytes, got ${frame.length}.',
            frame,
          );
        }
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
    if (payload.isEmpty) {
      throw ModbusFrameException(
        'Register response payload is empty: missing byte-count field.',
        frame,
      );
    }
    final byteCount = payload[0];
    final data = payload.sublist(1);
    if (byteCount.isOdd) {
      throw ModbusFrameException(
        'Register byte count must be even (registers are 2 bytes each), '
        'got $byteCount.',
        frame,
      );
    }
    if (data.length != byteCount) {
      throw ModbusFrameException(
        'Register byte count mismatch: header says $byteCount bytes, '
        'got ${data.length}.',
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
    if (payload.isEmpty) {
      throw ModbusFrameException(
        'Bit response payload is empty: missing byte-count field.',
        frame,
      );
    }
    final byteCount = payload[0];
    if (byteCount == 0) {
      throw ModbusFrameException(
        'Bit response byte count must be at least 1, got 0.',
        frame,
      );
    }
    final data = payload.sublist(1);
    if (data.length != byteCount) {
      throw ModbusFrameException(
        'Bit byte count mismatch: header says $byteCount, '
        'got ${data.length} data bytes.',
        frame,
      );
    }
    // Expand every packed bit LSB-first. The Modbus response frame does not
    // carry the original request quantity, so we return all byteCount * 8 bits.
    // The caller, who knows what they requested, should slice to that length:
    //   final coils = response.values.sublist(0, requestedQuantity);
    final values = <bool>[];
    for (final byte in data) {
      for (var bit = 0; bit < 8; bit++) {
        values.add((byte & (1 << bit)) != 0);
      }
    }
    return ReadBitsResponse(
      slaveId: slaveId,
      functionCode: functionCode,
      packedBitCount: values.length, // always byteCount * 8
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
    final address = (payload[0] << 8) | payload[1];
    final value = (payload[2] << 8) | payload[3];
    if (functionCode == ModbusFunctionCode.writeSingleCoil &&
        value != ModbusFunctionCode.coilOn &&
        value != ModbusFunctionCode.coilOff) {
      throw ModbusFrameException(
        'FC 05 echo value must be 0xFF00 (ON) or 0x0000 (OFF), '
        'got 0x${value.toRadixString(16).padLeft(4, '0')}.',
        frame,
      );
    }
    return WriteSingleResponse(
      slaveId: slaveId,
      functionCode: functionCode,
      address: address,
      value: value,
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
    final startAddress = (payload[0] << 8) | payload[1];
    final quantity = (payload[2] << 8) | payload[3];
    final maxQty = functionCode == ModbusFunctionCode.writeMultipleCoils
        ? 1968
        : 123;
    if (quantity == 0 || quantity > maxQty) {
      throw ModbusFrameException(
        'Write-multiple echo quantity out of range: must be 1..$maxQty, '
        'got $quantity.',
        frame,
      );
    }
    return WriteMultipleResponse(
      slaveId: slaveId,
      functionCode: functionCode,
      startAddress: startAddress,
      quantity: quantity,
    );
  }
}
