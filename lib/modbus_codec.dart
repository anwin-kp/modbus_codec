/// A pure Dart library for encoding and decoding Modbus RTU frames.
///
/// `modbus_codec` is a transport-agnostic translation layer that sits between
/// your application and the raw bytes of a Modbus device. It works equally
/// over BLE, serial, or TCP — anywhere you can send and receive `List<int>`.
///
/// **Receive path** — bytes in, clean data out:
/// ```dart
/// final response = ModbusDecoder.decode(rawBytesFromDevice);
/// if (response is ReadRegistersResponse) {
///   final ph = ModbusConvert.scale(response.registers[14], factor: 100);
/// }
/// ```
///
/// **Send path** — intent in, bytes out:
/// ```dart
/// final frame = ModbusEncoder.writeSingleRegister(
///   slaveId: 1, address: 40, value: 567,
/// );
/// await transport.send(frame); // e.g. BLE characteristic write
/// ```
///
/// The library never assumes what a register *means*. It returns raw 16-bit
/// values and expanded booleans; you apply signing, 32-bit combination,
/// scaling and ASCII decoding via [ModbusConvert], driven by your own
/// device's register map.
library;

export 'src/constants/function_codes.dart';
export 'src/convert/modbus_convert.dart';
export 'src/crc/crc16_modbus.dart';
export 'src/decoder/modbus_decoder.dart';
export 'src/encoder/modbus_encoder.dart';
export 'src/models/modbus_exception.dart';
export 'src/models/modbus_response.dart';
