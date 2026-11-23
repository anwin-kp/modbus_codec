## 0.2.0

**Breaking changes** — read before upgrading:

- Read requests (FC 01–04) now reject `slaveId: 0`. Broadcast is only defined
  for writes; a broadcast read never gets a reply.
- `ModbusDecoder.decode` rejects frames containing values outside `0..255`.
  Previously these passed the CRC check (which masks to 8 bits) and produced
  impossible register values.
- Exception responses must be exactly 5 bytes, and function code `0x80` is
  rejected as malformed instead of reported as a device error for "FC 0".

Earlier patch releases also contained breaking changes that should have been a
minor bump. If you are upgrading from 0.1.0–0.1.3, note:

- 0.1.1: `ReadBitsResponse.values` has `byteCount * 8` entries (not the
  requested quantity) — slice to your request quantity.
- 0.1.4: `ReadBitsResponse` no longer takes a `packedBitCount` constructor
  argument (it is a getter); `ModbusConvert.bit` throws for positions > 31.

New:

- `ModbusFrameAssembler` — reassembles responses split across BLE
  notifications (or partial serial reads) into complete frames.
- `ModbusDecoder.expectedLength` — total frame length from the first 2–3 bytes.
- `ModbusConvert.toFloat32`, `float32At`, `fromFloat32` — IEEE-754 float
  registers.
- `ModbusConvert.split32` — split a 32-bit value into two registers for writing.
- `ModbusConvert.fromSigned16` — signed value to raw register (`-5` → `65531`).
- `ModbusConvert.swapBytes16` — for devices using BADC / DCBA byte order.

Fixes and housekeeping:

- Documentation no longer claims native Modbus TCP support: frames must be RTU
  (with CRC bytes); RTU-over-TCP works, MBAP-framed Modbus TCP does not.
- Test suite now compiles and passes on the web (dart2js); CI runs it on every
  push.
- Removed unreachable length checks in the decoder.

## 0.1.4

- Decoder rejects oversized read responses (`byteCount > 250`) instead of accepting out-of-spec data.
- Decoder validates the address range on write-multiple echoes (`startAddress + quantity - 1 <= 0xFFFF`).
- `ModbusConvert.bit` restricted to position `0..31` — positions ≥ 32 are silently wrong on Flutter Web (dart2js).
- `ModbusConvert.scale` throws on factors that overflow the result to infinity.
- Added Modbus exception code `0x07` (negative acknowledge) to `ModbusExceptionCode`.
- `ModbusFrameException.toString()` now includes the raw frame bytes for easier debugging.
- `ReadBitsResponse.packedBitCount` is now a derived getter (always equals `values.length`).

## 0.1.3

- Fix README install snippet to reference `^0.1.2` (was pinned to old version).

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
