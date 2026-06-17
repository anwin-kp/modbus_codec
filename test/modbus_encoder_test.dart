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
  });
}
