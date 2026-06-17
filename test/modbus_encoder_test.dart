import 'package:modbus_codec/modbus_codec.dart';
import 'package:test/test.dart';

void main() {
  group('ModbusEncoder', () {
    test('readHoldingRegisters builds a valid frame', () {
      // slave 1, FC 03, start 0x0000, qty 10 -> CRC 0xCDC5 (bytes C5 CD).
      final frame = ModbusEncoder.readHoldingRegisters(
        slaveId: 1,
        startAddress: 0,
        quantity: 10,
      );
      expect(frame, equals([0x01, 0x03, 0x00, 0x00, 0x00, 0x0A, 0xC5, 0xCD]));
      expect(Crc16Modbus.isValid(frame), isTrue);
    });

    test('readCoils uses function code 0x01 and is big-endian', () {
      final frame = ModbusEncoder.readCoils(
        slaveId: 1,
        startAddress: 0x0013,
        quantity: 0x0025,
      );
      expect(frame.sublist(0, 6), equals([0x01, 0x01, 0x00, 0x13, 0x00, 0x25]));
      expect(Crc16Modbus.isValid(frame), isTrue);
    });

    test('writeSingleRegister encodes the raw value big-endian', () {
      final frame = ModbusEncoder.writeSingleRegister(
        slaveId: 1,
        address: 40,
        value: 567,
      );
      // 567 = 0x0237, address 40 = 0x0028.
      expect(frame.sublist(0, 6), equals([0x01, 0x06, 0x00, 0x28, 0x02, 0x37]));
      expect(Crc16Modbus.isValid(frame), isTrue);
    });

    test('writeSingleCoil maps true/false to 0xFF00 / 0x0000', () {
      final on =
          ModbusEncoder.writeSingleCoil(slaveId: 1, address: 5, value: true);
      final off =
          ModbusEncoder.writeSingleCoil(slaveId: 1, address: 5, value: false);
      expect(on.sublist(0, 6), equals([0x01, 0x05, 0x00, 0x05, 0xFF, 0x00]));
      expect(off.sublist(0, 6), equals([0x01, 0x05, 0x00, 0x05, 0x00, 0x00]));
    });

    test('writeMultipleRegisters lays out count, byte count, and data', () {
      final frame = ModbusEncoder.writeMultipleRegisters(
        slaveId: 1,
        startAddress: 0x0100,
        values: [0x000A, 0x0102],
      );
      expect(
        frame.sublist(0, 11),
        equals([
          0x01, 0x10, // slave, fn
          0x01, 0x00, // start address
          0x00, 0x02, // quantity = 2
          0x04, // byte count = 4
          0x00, 0x0A, // value 0
          0x01, 0x02, // value 1
        ]),
      );
      expect(Crc16Modbus.isValid(frame), isTrue);
    });

    test('writeMultipleCoils packs bits LSB-first', () {
      // 3 coils: [true, false, true] -> 0b00000101 = 0x05, 1 byte.
      final frame = ModbusEncoder.writeMultipleCoils(
        slaveId: 1,
        startAddress: 0,
        values: [true, false, true],
      );
      expect(
        frame.sublist(0, 8),
        equals([0x01, 0x0F, 0x00, 0x00, 0x00, 0x03, 0x01, 0x05]),
      );
    });

    test('rejects out-of-range register values', () {
      expect(
        () => ModbusEncoder.writeSingleRegister(
            slaveId: 1, address: 0, value: 70000),
        throwsArgumentError,
      );
    });

    test('rejects non-positive quantity', () {
      expect(
        () => ModbusEncoder.readHoldingRegisters(
            slaveId: 1, startAddress: 0, quantity: 0),
        throwsArgumentError,
      );
    });

    test('rejects empty value lists', () {
      expect(
        () => ModbusEncoder.writeMultipleRegisters(
            slaveId: 1, startAddress: 0, values: []),
        throwsArgumentError,
      );
    });

    // --- slaveId validation --------------------------------------------------

    test('rejects negative slaveId', () {
      expect(
        () => ModbusEncoder.readHoldingRegisters(
            slaveId: -1, startAddress: 0, quantity: 1),
        throwsArgumentError,
      );
    });

    test('rejects slaveId > 247', () {
      expect(
        () => ModbusEncoder.readHoldingRegisters(
            slaveId: 248, startAddress: 0, quantity: 1),
        throwsArgumentError,
      );
    });

    test('accepts slaveId 0 (broadcast) and 247 (boundary)', () {
      expect(
        () => ModbusEncoder.readHoldingRegisters(
            slaveId: 0, startAddress: 0, quantity: 1),
        returnsNormally,
      );
      expect(
        () => ModbusEncoder.readHoldingRegisters(
            slaveId: 247, startAddress: 0, quantity: 1),
        returnsNormally,
      );
    });

    // --- address validation --------------------------------------------------

    test('rejects negative address', () {
      expect(
        () => ModbusEncoder.readHoldingRegisters(
            slaveId: 1, startAddress: -1, quantity: 1),
        throwsArgumentError,
      );
    });

    test('rejects address > 0xFFFF', () {
      expect(
        () => ModbusEncoder.writeSingleRegister(
            slaveId: 1, address: 0x10000, value: 0),
        throwsArgumentError,
      );
    });

    // --- Modbus spec quantity limits -----------------------------------------

    test('rejects readCoils quantity > 2000', () {
      expect(
        () => ModbusEncoder.readCoils(
            slaveId: 1, startAddress: 0, quantity: 2001),
        throwsArgumentError,
      );
    });

    test('accepts readCoils quantity = 2000 (spec boundary)', () {
      expect(
        () => ModbusEncoder.readCoils(
            slaveId: 1, startAddress: 0, quantity: 2000),
        returnsNormally,
      );
    });

    test('rejects readDiscreteInputs quantity > 2000', () {
      expect(
        () => ModbusEncoder.readDiscreteInputs(
            slaveId: 1, startAddress: 0, quantity: 2001),
        throwsArgumentError,
      );
    });

    test('rejects readHoldingRegisters quantity > 125', () {
      expect(
        () => ModbusEncoder.readHoldingRegisters(
            slaveId: 1, startAddress: 0, quantity: 126),
        throwsArgumentError,
      );
    });

    test('accepts readHoldingRegisters quantity = 125 (spec boundary)', () {
      expect(
        () => ModbusEncoder.readHoldingRegisters(
            slaveId: 1, startAddress: 0, quantity: 125),
        returnsNormally,
      );
    });

    test('rejects readInputRegisters quantity > 125', () {
      expect(
        () => ModbusEncoder.readInputRegisters(
            slaveId: 1, startAddress: 0, quantity: 126),
        throwsArgumentError,
      );
    });

    test('rejects writeMultipleCoils with > 1968 values', () {
      expect(
        () => ModbusEncoder.writeMultipleCoils(
            slaveId: 1,
            startAddress: 0,
            values: List.filled(1969, true)),
        throwsArgumentError,
      );
    });

    test('accepts writeMultipleCoils with 1968 values (spec boundary)', () {
      expect(
        () => ModbusEncoder.writeMultipleCoils(
            slaveId: 1,
            startAddress: 0,
            values: List.filled(1968, false)),
        returnsNormally,
      );
    });

    test('rejects writeMultipleRegisters with > 123 values', () {
      expect(
        () => ModbusEncoder.writeMultipleRegisters(
            slaveId: 1,
            startAddress: 0,
            values: List.filled(124, 0)),
        throwsArgumentError,
      );
    });

    test('accepts writeMultipleRegisters with 123 values (spec boundary)', () {
      expect(
        () => ModbusEncoder.writeMultipleRegisters(
            slaveId: 1,
            startAddress: 0,
            values: List.filled(123, 0)),
        returnsNormally,
      );
    });

    test('error message includes index for bad value in writeMultipleRegisters',
        () {
      expect(
        () => ModbusEncoder.writeMultipleRegisters(
            slaveId: 1, startAddress: 0, values: [100, 70000, 200]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            contains('[1]'),
          ),
        ),
      );
    });

    // --- address + quantity range validation ---------------------------------

    test('rejects readHoldingRegisters when last address exceeds 0xFFFF', () {
      // startAddress=0xFF00, quantity=125 → last address 0xFF00+124=0xFF7C (ok)
      // startAddress=0xFF00, quantity=256 → blocked by quantity>125 guard first
      // startAddress=0xFFFF, quantity=2 → last address 0x10000 overflows
      expect(
        () => ModbusEncoder.readCoils(
            slaveId: 1, startAddress: 0xFFFF, quantity: 2),
        throwsArgumentError,
      );
    });

    test('accepts readCoils when last address is exactly 0xFFFF', () {
      // startAddress=0xFF00, quantity=256 → last address 0xFF00+255=0xFFFF (ok)
      expect(
        () => ModbusEncoder.readCoils(
            slaveId: 1, startAddress: 0xFF00, quantity: 256),
        returnsNormally,
      );
    });

    test('rejects writeMultipleRegisters when address range overflows 0xFFFF',
        () {
      expect(
        () => ModbusEncoder.writeMultipleRegisters(
            slaveId: 1, startAddress: 0xFFFE, values: [0, 1, 2]),
        throwsArgumentError,
      );
    });

    test('rejects writeMultipleCoils when address range overflows 0xFFFF', () {
      expect(
        () => ModbusEncoder.writeMultipleCoils(
            slaveId: 1, startAddress: 0xFFFF, values: [true, false]),
        throwsArgumentError,
      );
    });
  });
}
