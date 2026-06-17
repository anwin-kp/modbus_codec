/// Modbus RTU codec for BLE and mobile apps.
///
/// Build bytes to send to a device, and turn bytes received back into values.
///
/// **Send:**
/// ```dart
/// final bytes = ModbusEncoder.readHoldingRegisters(
///   slaveId: 1, startAddress: 0, quantity: 10,
/// );
/// await bleCharacteristic.write(bytes);
/// ```
///
/// **Receive:**
/// ```dart
/// final response = ModbusDecoder.decode(receivedBytes);
/// if (response is ReadRegistersResponse) {
///   final temp = ModbusConvert.scale(response.registers[0], factor: 10);
/// }
/// ```
library;

export 'src/constants/function_codes.dart';
export 'src/convert/modbus_convert.dart';
export 'src/crc/crc16_modbus.dart';
export 'src/decoder/modbus_decoder.dart';
export 'src/encoder/modbus_encoder.dart';
export 'src/models/modbus_exception.dart';
export 'src/models/modbus_response.dart';
