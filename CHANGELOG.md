## 0.1.3

- Decoder rejects oversized read responses (`byteCount > 250`) instead of accepting out-of-spec data.
- Decoder validates the address range on write-multiple echoes (`startAddress + quantity - 1 <= 0xFFFF`).
- `ModbusConvert.bit` restricted to position `0..31` — positions ≥ 32 are silently wrong on Flutter Web (dart2js).
- `ModbusConvert.scale` throws on factors that overflow the result to infinity.
- Added Modbus exception code `0x07` (negative acknowledge) to `ModbusExceptionCode`.
- `ModbusFrameException.toString()` now includes the raw frame bytes for easier debugging.
- `ReadBitsResponse.packedBitCount` is now a derived getter (always equals `values.length`).

## 0.1.2

- Rewrote README and library doc for BLE/mobile audience — send/receive examples, plain-language tables, no protocol jargon.
- Added address-range overflow check: encoder throws when `startAddress + quantity - 1 > 0xFFFF`.
- `ModbusConvert.combine32` now uses multiplication instead of bit-shift for correct behaviour on dart2js.
- Decoder enforces minimum write-response frame length (8 bytes) before decoding FC 05/06/15/16.

## 0.1.1

- Input validation for `slaveId`, `address`, and quantity limits on all function codes.
- `ReadBitsResponse` now returns all `byteCount * 8` bits; caller slices to request quantity.
- Decoder throws `ModbusFrameException` on malformed frames instead of crashing.
- `ModbusConvert` guards for non-ASCII input, negative scale factor, and `padToRegisters` overflow.

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
