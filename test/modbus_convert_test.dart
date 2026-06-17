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

    test('masks values larger than 16 bits before interpreting', () {
      // 0x1FFFF masked to 0xFFFF = -1
      expect(ModbusConvert.toSigned16(0x1FFFF), equals(-1));
    });
  });

  group('ModbusConvert.toSigned32', () {
    test('handles negative 32-bit values', () {
      expect(ModbusConvert.toSigned32(0xFFFFFFFF), equals(-1));
      expect(ModbusConvert.toSigned32(0x80000000), equals(-2147483648));
    });

    test('masks values larger than 32 bits before interpreting', () {
      expect(ModbusConvert.toSigned32(0x1FFFFFFFF), equals(-1));
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

    test('combine32At throws for negative index', () {
      expect(
        () => ModbusConvert.combine32At([0x0001, 0x0002], -1),
        throwsRangeError,
      );
    });

    test('combine32At throws when index is the last element (no room for pair)',
        () {
      final regs = [0x0001, 0x0002, 0x0003];
      expect(
        () => ModbusConvert.combine32At(regs, 2),
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

    test('rejects a negative factor', () {
      expect(() => ModbusConvert.scale(100, factor: -10), throwsArgumentError);
    });

    test('works with a fractional factor', () {
      expect(ModbusConvert.scale(5, factor: 0.5), closeTo(10.0, 1e-9));
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

    test('rejects non-ASCII characters in asciiToRegisters', () {
      expect(
        () => ModbusConvert.asciiToRegisters('café'),
        throwsArgumentError,
      );
    });

    test('rejects emoji in asciiToRegisters', () {
      expect(
        () => ModbusConvert.asciiToRegisters('Hi 🙂'),
        throwsArgumentError,
      );
    });

    test('rejects control characters (below 0x20) in asciiToRegisters', () {
      expect(
        () => ModbusConvert.asciiToRegisters('line\nbreak'),
        throwsArgumentError,
      );
    });

    test('error message includes the offending character position', () {
      expect(
        () => ModbusConvert.asciiToRegisters('Hi!é'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            contains('[3]'),
          ),
        ),
      );
    });

    test('asciiFromRegisters with all non-printable bytes returns empty string',
        () {
      final regs = [0x0001, 0x001F]; // all below 0x20
      expect(ModbusConvert.asciiFromRegisters(regs), equals(''));
    });
  });

  group('ModbusConvert.bit', () {
    test('reads individual bit positions (LSB = 0)', () {
      expect(ModbusConvert.bit(0x05, 0), isTrue);
      expect(ModbusConvert.bit(0x05, 1), isFalse);
      expect(ModbusConvert.bit(0x05, 2), isTrue);
    });

    test('reads high bits correctly', () {
      expect(ModbusConvert.bit(0x8000, 15), isTrue);
      expect(ModbusConvert.bit(0x8000, 14), isFalse);
    });
  });
}
