import 'package:modbus_codec/modbus_codec.dart';
import 'package:test/test.dart';

/// Helper: appends a valid CRC to a PDU so the decoder accepts it.
List<int> withCrc(List<int> pdu) => [...pdu, ...Crc16Modbus.bytes(pdu)];

void main() {
  group('ModbusDecoder', () {
    test('decodes a holding-registers response into raw uint16 values', () {
      // slave 1, FC 03, byte count 4, regs [0x029E (670), 0x020B (523)].
      final frame = withCrc([0x01, 0x03, 0x04, 0x02, 0x9E, 0x02, 0x0B]);
      final response = ModbusDecoder.decode(frame);

      expect(response, isA<ReadRegistersResponse>());
      response as ReadRegistersResponse;
      expect(response.slaveId, equals(1));
      expect(response.functionCode,
          equals(ModbusFunctionCode.readHoldingRegisters));
      expect(response.registers, equals([670, 523]));
    });

    test('decodes input registers (FC 04) the same way', () {
      final frame = withCrc([0x01, 0x04, 0x02, 0xFF, 0xFF]);
      final response = ModbusDecoder.decode(frame) as ReadRegistersResponse;
      expect(
          response.functionCode, equals(ModbusFunctionCode.readInputRegisters));
      expect(response.registers, equals([0xFFFF]));
    });

    test('expands coils LSB-first into booleans and trims padding', () {
      // byte 0x05 = 0b00000101 -> coil0 true, coil1 false, coil2 true,
      // bits 3-7 are zero padding and should be trimmed.
      final frame = withCrc([0x01, 0x01, 0x01, 0x05]);
      final response = ModbusDecoder.decode(frame) as ReadBitsResponse;
      expect(response.values.take(3), equals([true, false, true]));
      // Trailing zero padding trimmed: length should be 3, not 8.
      expect(response.values.length, equals(3));
      expect(response.requestedQuantity, equals(3));
    });

    test('does not trim trailing true bits (real coil values)', () {
      // byte 0xFF = all 8 coils ON — none are padding, length stays 8.
      final frame = withCrc([0x01, 0x01, 0x01, 0xFF]);
      final response = ModbusDecoder.decode(frame) as ReadBitsResponse;
      expect(response.values.length, equals(8));
      expect(response.values, everyElement(isTrue));
    });

    test('coil response with multiple bytes exposes all bits of non-final bytes',
        () {
      // 9 coils: 2 bytes. byte0 = 0xFF (coils 0-7 all ON), byte1 = 0x01 (coil 8 ON, rest padding).
      final frame = withCrc([0x01, 0x01, 0x02, 0xFF, 0x01]);
      final response = ModbusDecoder.decode(frame) as ReadBitsResponse;
      // First 8 all true, 9th true, trailing zeros trimmed.
      expect(response.values.length, equals(9));
      expect(response.values.sublist(0, 8), everyElement(isTrue));
      expect(response.values[8], isTrue);
    });

    test('decodes a write-single echo response', () {
      final frame = withCrc([0x01, 0x06, 0x00, 0x28, 0x02, 0x37]);
      final response = ModbusDecoder.decode(frame) as WriteSingleResponse;
      expect(response.address, equals(40));
      expect(response.value, equals(567));
    });

    test('decodes a write-multiple response', () {
      final frame = withCrc([0x01, 0x10, 0x01, 0x00, 0x00, 0x02]);
      final response = ModbusDecoder.decode(frame) as WriteMultipleResponse;
      expect(response.startAddress, equals(0x0100));
      expect(response.quantity, equals(2));
    });

    test('throws ModbusDeviceException on an exception response', () {
      // FC 03 error = 0x83, exception code 0x02 (illegal data address).
      final frame = withCrc([0x01, 0x83, 0x02]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(
          isA<ModbusDeviceException>()
              .having((e) => e.functionCode, 'functionCode', 0x03)
              .having((e) => e.exceptionCode, 'exceptionCode', 0x02),
        ),
      );
    });

    test('throws ModbusFrameException on bad CRC', () {
      final frame = [0x01, 0x03, 0x02, 0x00, 0x01, 0x00, 0x00];
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    test('CRC error message includes expected and actual CRC bytes', () {
      final frame = [0x01, 0x03, 0x02, 0x00, 0x01, 0x00, 0x00];
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(
          isA<ModbusFrameException>().having(
            (e) => e.message,
            'message',
            allOf(contains('expected'), contains('got')),
          ),
        ),
      );
    });

    test('skips CRC validation when validateCrc is false', () {
      final frame = [0x01, 0x03, 0x02, 0x00, 0x01, 0x00, 0x00];
      final response = ModbusDecoder.decode(frame, validateCrc: false)
          as ReadRegistersResponse;
      expect(response.registers, equals([1]));
    });

    test('throws on a byte-count mismatch', () {
      // Header claims 4 data bytes but only 2 are present.
      final frame = withCrc([0x01, 0x03, 0x04, 0x00, 0x01]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    test('throws on odd register byte count', () {
      // byte count = 3 (odd) — registers are always 2 bytes each.
      final frame = withCrc([0x01, 0x03, 0x03, 0x00, 0x01, 0x00]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(
          isA<ModbusFrameException>().having(
            (e) => e.message,
            'message',
            contains('even'),
          ),
        ),
      );
    });

    test('throws on an unsupported function code', () {
      final frame = withCrc([0x01, 0x63, 0x00, 0x00]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    test('throws on a frame that is too short', () {
      expect(
        () => ModbusDecoder.decode([0x01, 0x03]),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    test('throws ModbusFrameException (not IndexError) on empty register payload',
        () {
      final frame = withCrc([0x01, 0x03]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    test('throws ModbusFrameException (not IndexError) on empty bit payload',
        () {
      final frame = withCrc([0x01, 0x01]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    test(
        'throws ModbusFrameException (not IndexError) on truncated exception response',
        () {
      final frame = withCrc([0x01, 0x83]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    // --- bit response: byteCount = 0 -----------------------------------------

    test('throws ModbusFrameException when bit response byteCount is 0', () {
      // byteCount=0 is a malformed response — no coil data.
      final frame = withCrc([0x01, 0x01, 0x00]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    // --- FC 05 coil echo validation ------------------------------------------

    test('decodes FC 05 coil echo with value 0xFF00 (ON)', () {
      final frame = withCrc([0x01, 0x05, 0x00, 0x05, 0xFF, 0x00]);
      final response = ModbusDecoder.decode(frame) as WriteSingleResponse;
      expect(response.coilState, isTrue);
    });

    test('decodes FC 05 coil echo with value 0x0000 (OFF)', () {
      final frame = withCrc([0x01, 0x05, 0x00, 0x05, 0x00, 0x00]);
      final response = ModbusDecoder.decode(frame) as WriteSingleResponse;
      expect(response.coilState, isFalse);
    });

    test('throws ModbusFrameException for illegal FC 05 echo value', () {
      // value 0x0100 is not a valid Modbus coil echo value.
      final frame = withCrc([0x01, 0x05, 0x00, 0x05, 0x01, 0x00]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(
          isA<ModbusFrameException>().having(
            (e) => e.message,
            'message',
            allOf(contains('0xFF00'), contains('0x0000')),
          ),
        ),
      );
    });

    // --- WriteMultipleResponse quantity validation ---------------------------

    test('throws ModbusFrameException when write-multiple echo quantity is 0',
        () {
      // FC 16 echo with quantity = 0.
      final frame = withCrc([0x01, 0x10, 0x00, 0x00, 0x00, 0x00]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    test(
        'throws ModbusFrameException when write-multiple echo quantity exceeds spec limit',
        () {
      // FC 16 echo with quantity = 200 (> 123 max for registers).
      final frame = withCrc([0x01, 0x10, 0x00, 0x00, 0x00, 0xC8]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });

    test(
        'throws ModbusFrameException when FC 15 write-multiple echo coil quantity exceeds spec limit',
        () {
      // FC 15 echo with quantity = 2000 (> 1968 max for coils).
      final frame = withCrc([0x01, 0x0F, 0x00, 0x00, 0x07, 0xD0]);
      expect(
        () => ModbusDecoder.decode(frame),
        throwsA(isA<ModbusFrameException>()),
      );
    });
  });

  group('round-trip', () {
    test('encoded write echo decodes back to the same address/value', () {
      final request = ModbusEncoder.writeSingleRegister(
        slaveId: 1,
        address: 40,
        value: 567,
      );
      // A compliant device echoes the request verbatim for FC 06.
      final response = ModbusDecoder.decode(request) as WriteSingleResponse;
      expect(response.address, equals(40));
      expect(response.value, equals(567));
    });

    test('encoded coil write round-trips through decoder', () {
      final request = ModbusEncoder.writeSingleCoil(
        slaveId: 1,
        address: 5,
        value: true,
      );
      final response = ModbusDecoder.decode(request) as WriteSingleResponse;
      expect(response.coilState, isTrue);
    });
  });
}
