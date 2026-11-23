import 'package:modbus_codec/modbus_codec.dart';
import 'package:test/test.dart';

List<int> withCrc(List<int> pdu) => [...pdu, ...Crc16Modbus.bytes(pdu)];

void main() {
  // A 10-register read response: 3 + 20 + 2 = 25 bytes.
  final tenRegs = withCrc([0x01, 0x03, 0x14, for (var i = 0; i < 20; i++) i]);

  group('ModbusFrameAssembler', () {
    test('returns a frame that arrives in one chunk', () {
      final assembler = ModbusFrameAssembler();
      expect(assembler.add(tenRegs), equals([tenRegs]));
      expect(assembler.hasPartialFrame, isFalse);
    });

    test('reassembles a frame split into 20-byte BLE notifications', () {
      final assembler = ModbusFrameAssembler();
      expect(assembler.add(tenRegs.sublist(0, 20)), isEmpty);
      expect(assembler.hasPartialFrame, isTrue);
      expect(assembler.bufferedLength, equals(20));

      final frames = assembler.add(tenRegs.sublist(20));
      expect(frames, equals([tenRegs]));
      expect(assembler.hasPartialFrame, isFalse);

      final response = ModbusDecoder.decode(frames.single);
      expect((response as ReadRegistersResponse).registers.length, equals(10));
    });

    test('handles one byte at a time, including the header', () {
      final assembler = ModbusFrameAssembler();
      final out = <List<int>>[];
      for (final b in tenRegs) {
        out.addAll(assembler.add([b]));
      }
      expect(out, equals([tenRegs]));
    });

    test('returns several frames from one chunk and keeps the remainder', () {
      final echo = ModbusEncoder.writeSingleRegister(
          slaveId: 1, address: 40, value: 670); // echo == request for FC 06
      final assembler = ModbusFrameAssembler();
      final frames =
          assembler.add([...echo, ...echo, ...tenRegs.sublist(0, 5)]);
      expect(frames, equals([echo, echo]));
      expect(assembler.bufferedLength, equals(5));
      expect(assembler.add(tenRegs.sublist(5)), equals([tenRegs]));
    });

    test('assembles exception responses', () {
      final err = withCrc([0x01, 0x83, 0x02]);
      final assembler = ModbusFrameAssembler();
      expect(assembler.add(err.sublist(0, 2)), isEmpty);
      final frames = assembler.add(err.sublist(2));
      expect(frames, equals([err]));
      expect(() => ModbusDecoder.decode(frames.single),
          throwsA(isA<ModbusDeviceException>()));
    });

    test('reset discards a partial frame', () {
      final assembler = ModbusFrameAssembler();
      assembler.add(tenRegs.sublist(0, 10));
      assembler.reset();
      expect(assembler.hasPartialFrame, isFalse);
      expect(assembler.add(tenRegs), equals([tenRegs]));
    });

    test('throws and clears the buffer on an unsupported function code', () {
      final assembler = ModbusFrameAssembler();
      expect(() => assembler.add([0x01, 0x2B, 0x00]),
          throwsA(isA<ModbusFrameException>()));
      expect(assembler.hasPartialFrame, isFalse);
      expect(assembler.add(tenRegs), equals([tenRegs]));
    });
  });
}
