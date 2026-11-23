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
  /// [frame] must be one complete RTU frame, including the 2 trailing CRC
  /// bytes. Over BLE a response is often split across several notifications;
  /// join them first with [ModbusFrameAssembler] (or [expectedLength]).
  ///
  /// By default the trailing CRC is validated; pass [validateCrc] `false` to
  /// skip the check (e.g. RTU-over-TCP gateways that already guarantee
  /// integrity, or during testing). The 2 CRC bytes must still be present.
  /// Native Modbus TCP frames (MBAP header, no CRC) are not supported.
  ///
  /// Throws:
  ///  * [ModbusDeviceException] if the device returned an exception response.
  ///  * [ModbusFrameException] if the frame is malformed or fails CRC.
  static ModbusResponse decode(List<int> frame, {bool validateCrc = true}) {
    if (frame.length < 5) {
      throw ModbusFrameException(
        'Frame too short: expected at least 5 bytes, got ${frame.length}.',
        frame,
      );
    }

    _checkBytes(frame);

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
      if (frame.length != 5) {
        throw ModbusFrameException(
          'Exception response must be exactly 5 bytes, got ${frame.length}.',
          frame,
        );
      }
      if (functionCode == ModbusFunctionCode.errorMask) {
        throw ModbusFrameException(
          'Invalid exception response function code 0x80 (function 0).',
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

    // Write echoes are always 8 bytes (header 2 + payload 4 + CRC 2); the
    // per-function decoders enforce this via the 4-byte payload check.
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

  /// Returns the total length in bytes (CRC included) of the response frame
  /// that starts with [partial], or `null` if more bytes are needed to tell.
  ///
  /// Use this to reassemble a response that arrives in pieces, e.g. split
  /// across BLE notifications: keep appending bytes until
  /// `buffer.length >= expectedLength(buffer)!`. [ModbusFrameAssembler] does
  /// this for you.
  ///
  /// Needs 2 bytes for exception and write responses, 3 for read responses.
  ///
  /// Throws [ModbusFrameException] if the function code is not supported, so
  /// the length can never be known.
  static int? expectedLength(List<int> partial) {
    if (partial.length < 2) return null;
    _checkBytes(partial.sublist(0, partial.length < 3 ? partial.length : 3));
    final functionCode = partial[1];
    if ((functionCode & ModbusFunctionCode.errorMask) != 0) return 5;
    switch (functionCode) {
      case ModbusFunctionCode.readCoils:
      case ModbusFunctionCode.readDiscreteInputs:
      case ModbusFunctionCode.readHoldingRegisters:
      case ModbusFunctionCode.readInputRegisters:
        if (partial.length < 3) return null;
        return 5 + partial[2]; // slave + fc + byteCount + data + CRC(2)
      case ModbusFunctionCode.writeSingleCoil:
      case ModbusFunctionCode.writeSingleRegister:
      case ModbusFunctionCode.writeMultipleCoils:
      case ModbusFunctionCode.writeMultipleRegisters:
        return 8;
      default:
        throw ModbusFrameException(
          'Unsupported function code: 0x${functionCode.toRadixString(16)}; '
          'cannot determine frame length.',
          partial,
        );
    }
  }

  /// Every element of a byte frame must be an unsigned byte. Without this,
  /// out-of-range values pass the CRC check (which masks to 8 bits) and
  /// produce impossible register values.
  static void _checkBytes(List<int> frame) {
    for (var i = 0; i < frame.length; i++) {
      final b = frame[i];
      if (b < 0 || b > 0xFF) {
        throw ModbusFrameException(
          'Frame byte at index $i is $b; every byte must be in range 0..255.',
          frame,
        );
      }
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
    if (byteCount == 0) {
      throw ModbusFrameException(
        'Register byte count must be at least 2, got 0.',
        frame,
      );
    }
    // Spec max: 125 registers × 2 bytes = 250.
    if (byteCount > 250) {
      throw ModbusFrameException(
        'Register byte count exceeds spec maximum of 250 (125 registers × 2), '
        'got $byteCount.',
        frame,
      );
    }
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
    // Spec max: ceil(2000 / 8) = 250 bytes.
    if (byteCount > 250) {
      throw ModbusFrameException(
        'Bit response byte count exceeds spec maximum of 250 '
        '(2000 coils / 8), got $byteCount.',
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
      values: values, // length is always byteCount * 8
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
    final maxQty =
        functionCode == ModbusFunctionCode.writeMultipleCoils ? 1968 : 123;
    if (quantity == 0 || quantity > maxQty) {
      throw ModbusFrameException(
        'Write-multiple echo quantity out of range: must be 1..$maxQty, '
        'got $quantity.',
        frame,
      );
    }
    if (startAddress + quantity - 1 > 0xFFFF) {
      throw ModbusFrameException(
        'Write-multiple echo address range overflows: '
        'startAddress ($startAddress) + quantity ($quantity) - 1 = '
        '${startAddress + quantity - 1}, exceeds 0xFFFF.',
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
