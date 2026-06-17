## 0.1.0

Initial release.

- `ModbusEncoder` for building RTU request frames: read coils / discrete inputs
  / holding registers / input registers (FC 01–04), and write single & multiple
  coils / registers (FC 05, 06, 15, 16).
- `ModbusDecoder` for parsing RTU response bytes into typed responses
  (`ReadRegistersResponse`, `ReadBitsResponse`, `WriteSingleResponse`,
  `WriteMultipleResponse`), with optional CRC validation.
- `Crc16Modbus` — CRC-16/MODBUS compute, byte generation, and validation.
- `ModbusConvert` helpers: signed 16/32-bit, 32-bit register pairing with
  selectable word order, fixed-point scaling, and packed-ASCII encode/decode.
- `ModbusDeviceException` / `ModbusFrameException` for device-reported errors
  and malformed frames.
- Zero runtime dependencies; pure Dart.
