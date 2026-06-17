import 'package:modbus_codec/modbus_codec.dart';
import 'package:test/test.dart';

void main() {
  group('ModbusConvert.toSigned16', () {
    test('leaves positive values unchanged', () {
      expect(ModbusConvert.toSigned16(100), equals(100));
      expect(ModbusConvert.toSigned16(0x7FFF), equals(32767));
    });

    test('interprets the high half as negative', () {
      expect(ModbusConvert.toSigned16(0xFFFF), equals(-1));
      expect(ModbusConvert.toSigned16(65436), equals(-100));
      expect(ModbusConvert.toSigned16(0x8000), equals(-32768));
    });
  });

  group('ModbusConvert.toSigned32', () {
    test('handles negative 32-bit values', () {
      expect(ModbusConvert.toSigned32(0xFFFFFFFF), equals(-1));
      expect(ModbusConvert.toSigned32(0x80000000), equals(-2147483648));
    });
  });

  group('ModbusConvert.combine32', () {
    test('high word first', () {
      expect(
        ModbusConvert.combine32(high: 0x1234, low: 0x5678),
        equals(0x12345678),
      );
    });

    test('low word first (word-swapped)', () {
      expect(
        ModbusConvert.combine32(
          high: 0x1234,
          low: 0x5678,
          order: ModbusWordOrder.lowWordFirst,
        ),
        equals(0x56781234),
      );
    });

    test('combine32At reads a pair from a register list', () {
      final regs = [0x0000, 0x1234, 0x5678];
      expect(ModbusConvert.combine32At(regs, 1), equals(0x12345678));
    });

    test('combine32At throws when the pair runs past the end', () {
      expect(
        () => ModbusConvert.combine32At([0x0001], 0),
        throwsRangeError,
      );
    });
  });

  group('ModbusConvert.scale', () {
    test('divides by the fixed-point factor', () {
      expect(ModbusConvert.scale(670, factor: 100), closeTo(6.70, 1e-9));
      expect(ModbusConvert.scale(523, factor: 100), closeTo(5.23, 1e-9));
    });

    test('rejects a zero factor', () {
      expect(() => ModbusConvert.scale(1, factor: 0), throwsArgumentError);
    });
  });

  group('ModbusConvert ASCII', () {
    test('decodes two characters per register, high byte first', () {
      // "My" = 0x4D, 0x79 -> register 0x4D79.
      final regs = [0x4D79, 0x506F, 0x6F6C]; // My Po ol
      expect(ModbusConvert.asciiFromRegisters(regs), equals('MyPool'));
    });

    test('skips NUL padding by default', () {
      final regs = [0x4D79, 0x0000];
      expect(ModbusConvert.asciiFromRegisters(regs), equals('My'));
    });

    test('round-trips text through encode/decode', () {
      const text = 'Pump1';
      final regs = ModbusConvert.asciiToRegisters(text);
      expect(ModbusConvert.asciiFromRegisters(regs), equals(text));
    });

    test('pads encoded registers to a fixed width', () {
      final regs = ModbusConvert.asciiToRegisters('Hi', padToRegisters: 4);
      expect(regs.length, equals(4));
      expect(regs[0], equals(0x4869)); // "Hi"
      expect(regs.sublist(1), everyElement(equals(0x0000)));
    });
  });

  group('ModbusConvert.bit', () {
    test('reads individual bit positions (LSB = 0)', () {
      expect(ModbusConvert.bit(0x05, 0), isTrue);
      expect(ModbusConvert.bit(0x05, 1), isFalse);
      expect(ModbusConvert.bit(0x05, 2), isTrue);
    });
  });
}
