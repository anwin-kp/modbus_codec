/// Byte/word order used when combining two 16-bit registers into a 32-bit value.
///
/// Modbus itself only defines 16-bit registers; how a 32-bit value spans two
/// registers is device-specific, so you must pick the order your device uses.
enum ModbusWordOrder {
  /// Most-significant word first: `value = (reg[0] << 16) | reg[1]`.
  /// Also known as "big-endian" word order (ABCD).
  highWordFirst,

  /// Least-significant word first: `value = (reg[1] << 16) | reg[0]`.
  /// Also known as "little-endian" word order / word-swapped (CDAB).
  lowWordFirst,
}

/// Pure conversion helpers for interpreting raw Modbus register values.
///
/// The decoder returns registers as raw unsigned 16-bit integers. Real
/// devices encode richer meaning on top of those words — signed numbers,
/// 32-bit numbers spanning two registers, fixed-point scaling, packed ASCII.
/// These helpers turn raw values into usable data; you decide which to apply,
/// because only your device's register map knows what each register means.
abstract final class ModbusConvert {
  /// Interprets an unsigned 16-bit [value] as a signed 16-bit integer
  /// (two's complement), giving a result in the range -32768..32767.
  static int toSigned16(int value) {
    final v = value & 0xFFFF;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  /// Interprets an unsigned 32-bit [value] as a signed 32-bit integer
  /// (two's complement).
  static int toSigned32(int value) {
    final v = value & 0xFFFFFFFF;
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  /// Combines two raw 16-bit registers, [high] and [low], into one unsigned
  /// 32-bit value using the given [order].
  ///
  /// The arguments are named for the [ModbusWordOrder.highWordFirst] case;
  /// pass the two registers in the order they appear in the response and
  /// choose [order] to match your device.
  static int combine32({
    required int high,
    required int low,
    ModbusWordOrder order = ModbusWordOrder.highWordFirst,
  }) {
    final h = high & 0xFFFF;
    final l = low & 0xFFFF;
    return order == ModbusWordOrder.highWordFirst
        ? (h << 16) | l
        : (l << 16) | h;
  }

  /// Combines a pair of consecutive registers at [index] and `index + 1` in
  /// [registers] into a 32-bit value. Convenience wrapper over [combine32].
  static int combine32At(
    List<int> registers,
    int index, {
    ModbusWordOrder order = ModbusWordOrder.highWordFirst,
  }) {
    if (index < 0 || index + 1 >= registers.length) {
      throw RangeError.range(index, 0, registers.length - 2, 'index');
    }
    return combine32(
      high: registers[index],
      low: registers[index + 1],
      order: order,
    );
  }

  /// Applies a fixed-point scale: returns `raw / factor`.
  ///
  /// Many devices store engineering values as integers — e.g. pH 6.70 stored
  /// as `670` with a [factor] of `100`. Pass the same factor the device uses.
  static double scale(int raw, {required num factor}) {
    if (factor == 0) {
      throw ArgumentError.value(factor, 'factor', 'must not be zero');
    }
    return raw / factor;
  }

  /// Decodes packed ASCII text from [registers], where each register holds two
  /// characters: the high byte first, then the low byte.
  ///
  /// Non-printable bytes (outside 0x20..0x7E) are skipped by default, which
  /// drops `NUL` padding and control bytes. Set [keepNonPrintable] `true` to
  /// retain every byte.
  static String asciiFromRegisters(
    List<int> registers, {
    bool keepNonPrintable = false,
  }) {
    final codes = <int>[];
    for (final reg in registers) {
      final hi = (reg >> 8) & 0xFF;
      final lo = reg & 0xFF;
      for (final code in [hi, lo]) {
        if (keepNonPrintable || (code >= 0x20 && code <= 0x7E)) {
          codes.add(code);
        }
      }
    }
    return String.fromCharCodes(codes);
  }

  /// Encodes [text] into packed-ASCII registers (two chars per register, high
  /// byte first) suitable for a write request.
  ///
  /// When [text] has an odd length the final register's low byte is `0x00`
  /// padding. Pass [padToRegisters] to NUL-pad the result up to a fixed number
  /// of registers (useful for fixed-width string fields).
  static List<int> asciiToRegisters(String text, {int? padToRegisters}) {
    final codes = text.codeUnits;
    final registers = <int>[];
    for (var i = 0; i < codes.length; i += 2) {
      final hi = codes[i] & 0xFF;
      final lo = (i + 1 < codes.length) ? codes[i + 1] & 0xFF : 0x00;
      registers.add((hi << 8) | lo);
    }
    if (padToRegisters != null) {
      while (registers.length < padToRegisters) {
        registers.add(0x0000);
      }
    }
    return registers;
  }

  /// Returns the value of a single bit at [position] (0 = LSB) within [value].
  static bool bit(int value, int position) => (value & (1 << position)) != 0;
}
