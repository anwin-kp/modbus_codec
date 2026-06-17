import 'package:modbus_codec/modbus_codec.dart';
import 'package:test/test.dart';

void main() {
  group('Crc16Modbus', () {
    test('computes the canonical "123456789" check value 0x4B37', () {
      // The standard CRC-16/MODBUS check value for the ASCII string
      // "123456789" is 0x4B37.
      final data = '123456789'.codeUnits;
      expect(Crc16Modbus.compute(data), equals(0x4B37));
    });

    test('returns CRC bytes in transmission order (low, high)', () {
      // Known frame: slave 1, FC 04, byte count 2, data 0xFFFF -> CRC 0x80B8,
      // transmitted low byte first as [0xB8, 0x80].
      final payload = [0x01, 0x04, 0x02, 0xFF, 0xFF];
      expect(Crc16Modbus.compute(payload), equals(0x80B8));
      expect(Crc16Modbus.bytes(payload), equals([0xB8, 0x80]));
    });

    test('validates a frame with a correct trailing CRC', () {
      final frame = [0x01, 0x04, 0x02, 0xFF, 0xFF, 0xB8, 0x80];
      expect(Crc16Modbus.isValid(frame), isTrue);
    });

    test('rejects a frame with a corrupted CRC', () {
      final frame = [0x01, 0x04, 0x02, 0xFF, 0xFF, 0x00, 0x00];
      expect(Crc16Modbus.isValid(frame), isFalse);
    });

    test('rejects frames shorter than 3 bytes', () {
      expect(Crc16Modbus.isValid([0x01, 0x02]), isFalse);
    });
  });
}
