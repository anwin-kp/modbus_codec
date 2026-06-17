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

    test('expands coils LSB-first into booleans', () {
      // byte 0x05 = 0b00000101 -> coil0 true, coil1 false, coil2 true.
      final frame = withCrc([0x01, 0x01, 0x01, 0x05]);
      final response = ModbusDecoder.decode(frame) as ReadBitsResponse;
      expect(response.values.take(3), equals([true, false, true]));
      expect(response.values.length, equals(8));
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
      // Valid header but no payload bytes — would previously crash with IndexError.
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
      // Exception frame missing the exception code byte — only 4 bytes with CRC.
      final frame = withCrc([0x01, 0x83]);
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
  });
}
