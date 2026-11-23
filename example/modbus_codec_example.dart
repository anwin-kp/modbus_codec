// Demonstrates the two halves of the codec: encoding requests to send to a
// device, and decoding the raw bytes that come back into usable values.
//
// The transport (BLE / serial / TCP) is intentionally not shown — this package
// only deals in `List<int>`. Wherever you see `sendToDevice` / `bytesFromDevice`
// below, plug in your own transport.
import 'package:modbus_codec/modbus_codec.dart';

void main() {
  const slaveId = 1;

  // --- SEND PATH: intent -> bytes -------------------------------------------

  // Ask to read 4 holding registers starting at address 0.
  final readRequest = ModbusEncoder.readHoldingRegisters(
    slaveId: slaveId,
    startAddress: 0,
    quantity: 4,
  );
  print('Read request bytes: ${_hex(readRequest)}');
  // -> send readRequest over your transport here.

  // Write pH setpoint 6.70 to register 40 (device stores it as 670).
  final writeRequest = ModbusEncoder.writeSingleRegister(
    slaveId: slaveId,
    address: 40,
    value: (6.70 * 100).round(),
  );
  print('Write request bytes: ${_hex(writeRequest)}');

  // --- RECEIVE PATH: bytes -> usable data -----------------------------------

  // Simulated bytes arriving from the device (slave 1, FC 03, 4 registers):
  //   reg0 = 670  (pH * 100)
  //   reg1 = 523  (ORP * 100)
  //   reg2,reg3 = a 32-bit Unix timestamp split across two registers
  final pdu = [
    slaveId, 0x03, 0x08, //
    0x02, 0x9E, // 670
    0x02, 0x0B, // 523
    0x65, 0x4A, // timestamp high word
    0x12, 0x34, // timestamp low word
  ];
  final bytesFromDevice = [...pdu, ...Crc16Modbus.bytes(pdu)];

  // Over BLE the reply may arrive in pieces (e.g. 20-byte notifications).
  // The assembler joins them and yields each complete frame.
  final assembler = ModbusFrameAssembler();
  final frames = [
    ...assembler.add(bytesFromDevice.sublist(0, 6)), // first notification
    ...assembler.add(bytesFromDevice.sublist(6)), // second notification
  ];

  final response = ModbusDecoder.decode(frames.single);

  if (response is ReadRegistersResponse) {
    final regs = response.registers;

    // Apply *your* device's register map to the raw values:
    final ph = ModbusConvert.scale(regs[0], factor: 100); // 6.70
    final orp = ModbusConvert.scale(regs[1], factor: 100); // 5.23
    final timestamp = ModbusConvert.combine32At(regs, 2); // 32-bit value

    print('pH        = $ph');
    print('ORP       = $orp');
    print('timestamp = $timestamp');
  }

  // Write a float setpoint (IEEE-754, two registers) to register 50.
  final floatWrite = ModbusEncoder.writeMultipleRegisters(
    slaveId: slaveId,
    startAddress: 50,
    values: ModbusConvert.fromFloat32(7.25),
  );
  print('Float write bytes: ${_hex(floatWrite)}');

  // --- Error handling -------------------------------------------------------

  try {
    // An exception response: FC 03 error (0x83), code 0x02 (illegal address).
    final errPdu = [slaveId, 0x83, 0x02];
    ModbusDecoder.decode([...errPdu, ...Crc16Modbus.bytes(errPdu)]);
  } on ModbusDeviceException catch (e) {
    print('Device rejected request: ${e.description}');
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
