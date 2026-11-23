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

    test('combine32 with high word bit-15 set produces correct unsigned result',
        () {
      // 0x8000_0001 — high word has bit 15 set; << 16 would overflow on JS.
      expect(
        ModbusConvert.combine32(high: 0x8000, low: 0x0001),
        equals(0x80000001),
      );
      expect(
        ModbusConvert.combine32(high: 0xFFFF, low: 0xFFFF),
        equals(0xFFFFFFFF),
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

    test('combine32At throws a clear RangeError on empty list', () {
      expect(
        () => ModbusConvert.combine32At([], 0),
        throwsA(
          isA<RangeError>().having(
            (e) => e.message,
            'message',
            contains('at least 2'),
          ),
        ),
      );
    });

    test('combine32At throws a clear RangeError on single-element list', () {
      expect(
        () => ModbusConvert.combine32At([0x0001], 0),
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

    test('rejects double.infinity as factor', () {
      expect(
        () => ModbusConvert.scale(100, factor: double.infinity),
        throwsArgumentError,
      );
    });

    test('rejects double.nan as factor', () {
      expect(
        () => ModbusConvert.scale(100, factor: double.nan),
        throwsArgumentError,
      );
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

    test(
        'throws ArgumentError when padToRegisters is smaller than encoded length',
        () {
      expect(
        () => ModbusConvert.asciiToRegisters('Hello', padToRegisters: 1),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('does not fit'),
          ),
        ),
      );
    });

    test('throws ArgumentError when padToRegisters is negative', () {
      expect(
        () => ModbusConvert.asciiToRegisters('Hi', padToRegisters: -1),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('non-negative'),
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

    test('rejects position < 0', () {
      expect(() => ModbusConvert.bit(0xFF, -1), throwsArgumentError);
    });

    test('rejects position > 31', () {
      expect(() => ModbusConvert.bit(0xFF, 32), throwsArgumentError);
    });

    test('accepts position 31 (boundary)', () {
      expect(ModbusConvert.bit(0x80000000, 31), isTrue);
      expect(ModbusConvert.bit(0x7FFFFFFF, 31), isFalse);
    });
  });

  group('ModbusConvert.scale overflow', () {
    test('rejects factor so small that result overflows to infinity', () {
      // (2^53 - 1) / 1e-300 = infinity. 2^53 - 1 is the largest int that is
      // exact on both the VM and the web, so this test compiles for dart2js.
      expect(
        () => ModbusConvert.scale(9007199254740991, factor: 1e-300),
        throwsArgumentError,
      );
    });

    test('normal large raw value with reasonable factor does not throw', () {
      expect(ModbusConvert.scale(65535, factor: 1), equals(65535.0));
    });
  });

  group('ModbusConvert.fromSigned16', () {
    test('converts negatives to two\'s complement', () {
      expect(ModbusConvert.fromSigned16(-5), equals(65531));
      expect(ModbusConvert.fromSigned16(-32768), equals(0x8000));
      expect(ModbusConvert.fromSigned16(32767), equals(0x7FFF));
      expect(ModbusConvert.fromSigned16(0), equals(0));
    });

    test('round-trips with toSigned16', () {
      for (final v in [-32768, -1, 0, 1, 12345, 32767]) {
        expect(
            ModbusConvert.toSigned16(ModbusConvert.fromSigned16(v)), equals(v));
      }
    });

    test('rejects values outside int16', () {
      expect(() => ModbusConvert.fromSigned16(32768), throwsArgumentError);
      expect(() => ModbusConvert.fromSigned16(-32769), throwsArgumentError);
    });
  });

  group('ModbusConvert.swapBytes16', () {
    test('swaps the two bytes', () {
      expect(ModbusConvert.swapBytes16(0x1234), equals(0x3412));
      expect(ModbusConvert.swapBytes16(0xFF00), equals(0x00FF));
      expect(ModbusConvert.swapBytes16(0x0000), equals(0x0000));
    });
  });

  group('ModbusConvert.split32', () {
    test('splits high word first by default', () {
      expect(ModbusConvert.split32(0x12345678), equals([0x1234, 0x5678]));
    });

    test('splits low word first when asked', () {
      expect(
          ModbusConvert.split32(0x12345678,
              order: ModbusWordOrder.lowWordFirst),
          equals([0x5678, 0x1234]));
    });

    test('handles the top bit (web-safe)', () {
      expect(ModbusConvert.split32(0xFFFFFFFF), equals([0xFFFF, 0xFFFF]));
      expect(ModbusConvert.split32(0x80000000), equals([0x8000, 0x0000]));
    });

    test('writes negatives as two\'s complement', () {
      expect(ModbusConvert.split32(-1), equals([0xFFFF, 0xFFFF]));
      expect(ModbusConvert.split32(-2147483648), equals([0x8000, 0x0000]));
    });

    test('round-trips with combine32', () {
      for (final order in ModbusWordOrder.values) {
        final regs = ModbusConvert.split32(0xDEADBEEF, order: order);
        expect(
            ModbusConvert.combine32(high: regs[0], low: regs[1], order: order),
            equals(0xDEADBEEF));
      }
    });

    test('rejects values that do not fit in 32 bits', () {
      expect(() => ModbusConvert.split32(0x100000000), throwsArgumentError);
      expect(() => ModbusConvert.split32(-2147483649), throwsArgumentError);
    });
  });

  group('ModbusConvert float32', () {
    test('decodes a known float (123.456 = 0x42F6E979)', () {
      expect(ModbusConvert.toFloat32(high: 0x42F6, low: 0xE979),
          closeTo(123.456, 1e-4));
    });

    test('decodes low word first', () {
      expect(
          ModbusConvert.toFloat32(
              high: 0xE979, low: 0x42F6, order: ModbusWordOrder.lowWordFirst),
          closeTo(123.456, 1e-4));
    });

    test('decodes negatives, zero and 1.0', () {
      expect(ModbusConvert.toFloat32(high: 0xBF80, low: 0x0000), equals(-1.0));
      expect(ModbusConvert.toFloat32(high: 0x3F80, low: 0x0000), equals(1.0));
      expect(ModbusConvert.toFloat32(high: 0x0000, low: 0x0000), equals(0.0));
    });

    test('decodes NaN and infinity', () {
      expect(ModbusConvert.toFloat32(high: 0x7FC0, low: 0x0000).isNaN, isTrue);
      expect(ModbusConvert.toFloat32(high: 0x7F80, low: 0x0000),
          equals(double.infinity));
    });

    test('float32At reads a pair from a register list', () {
      expect(ModbusConvert.float32At([0, 0x42F6, 0xE979], 1),
          closeTo(123.456, 1e-4));
      expect(() => ModbusConvert.float32At([0x42F6], 0), throwsRangeError);
    });

    test('fromFloat32 encodes to registers', () {
      expect(ModbusConvert.fromFloat32(1.0), equals([0x3F80, 0x0000]));
      expect(ModbusConvert.fromFloat32(-1.0), equals([0xBF80, 0x0000]));
      expect(
          ModbusConvert.fromFloat32(1.0, order: ModbusWordOrder.lowWordFirst),
          equals([0x0000, 0x3F80]));
    });

    test('round-trips through fromFloat32 and float32At', () {
      for (final order in ModbusWordOrder.values) {
        for (final v in [0.0, 1.5, -273.15, 6.7, 1e10]) {
          final regs = ModbusConvert.fromFloat32(v, order: order);
          expect(ModbusConvert.float32At(regs, 0, order: order),
              closeTo(v, v.abs() * 1e-6));
        }
      }
    });
  });
}
