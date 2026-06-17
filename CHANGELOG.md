## 0.1.1

Bug fixes and input validation hardening.

**Bug fixes**
- `ModbusDecoder`: truncated exception response (missing exception-code byte)
  now throws `ModbusFrameException` instead of crashing with an `IndexError`.
- `ModbusDecoder`: empty payload for FC 03 / FC 04 / FC 01 / FC 02 responses
  now throws `ModbusFrameException` instead of crashing with an `IndexError`.

**New validation**
- `ModbusEncoder`: `slaveId` is now validated to be in range `0..247`.
- `ModbusEncoder`: `startAddress` / `address` is now validated to be in range
  `0x0000..0xFFFF`; values above `0xFFFF` previously silently truncated.
- `ModbusEncoder`: Modbus spec quantity limits are now enforced —
  FC 01/02 max 2000, FC 03/04 max 125, FC 15 max 1968, FC 16 max 123.
- `ModbusConvert.scale`: `factor` must now be positive; negative factors
  previously returned a silently inverted result.
- `ModbusConvert.asciiToRegisters`: all characters must now be printable ASCII
  (0x20–0x7E); non-ASCII input previously silently corrupted the output.

**Improved error messages**
- CRC failure now reports the expected and actual CRC bytes.
- Odd register byte count now explicitly states the even-only requirement.
- `writeMultipleRegisters` out-of-range value now includes the list index
  (e.g. `values[2]`) so the offending entry is easy to locate.

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
