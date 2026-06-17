# modbus_codec

A pure Dart library for **encoding and decoding Modbus RTU frames**. It is a
transport-agnostic translation layer that sits between your application and the
raw bytes of a Modbus device — use it over **BLE, serial, or TCP**, anywhere you
can send and receive `List<int>`.

- 🔄 **Two directions** — encode high-level intent into request frames; decode
  raw response bytes into clean, typed values.
- 🧱 **Zero dependencies** — no Flutter, no native code, pure Dart.
- ✅ **CRC-16/MODBUS** built in (generate + validate).
- 🧰 **Conversion helpers** for signed integers, 32-bit register pairs,
  fixed-point scaling, and packed ASCII.
- 🚫 **Unopinionated** — it never assumes what a register *means*; your device's
  register map stays in your code.

## Why "codec", not a device driver?

Modbus is an application-layer protocol; it has nothing to do with the
transport. A water-quality controller might speak Modbus over BLE, while a PLC
speaks the same Modbus over RS-485 or TCP. This package handles only the part
that is identical everywhere — the **frame format** — and leaves the transport
and the register meanings to you.

```
your intent ──> ModbusEncoder ──> bytes ──> [ your transport ] ──> device
device ──> [ your transport ] ──> bytes ──> ModbusDecoder ──> typed data
```

## Install

```yaml
dependencies:
  modbus_codec: ^0.1.0
```

## Receive path — bytes in, usable data out

```dart
import 'package:modbus_codec/modbus_codec.dart';

// `rawBytes` came from your transport (e.g. a BLE characteristic notification).
final response = ModbusDecoder.decode(rawBytes);

if (response is ReadRegistersResponse) {
  final regs = response.registers;            // raw List<int> of uint16 values

  // Apply YOUR device's register map:
  final ph        = ModbusConvert.scale(regs[14], factor: 100);   // 670 -> 6.70
  final offset    = ModbusConvert.toSigned16(regs[41]);           // signed
  final timestamp = ModbusConvert.combine32At(regs, 48);          // 32-bit pair
  final serial    = ModbusConvert.asciiFromRegisters(regs.sublist(50, 58));
}
```

## Send path — intent in, bytes out

```dart
// Read 55 holding registers starting at address 0.
final read = ModbusEncoder.readHoldingRegisters(
  slaveId: 1, startAddress: 0, quantity: 55,
);

// Write pH setpoint 6.70 -> stored as 670 in register 40.
final write = ModbusEncoder.writeSingleRegister(
  slaveId: 1, address: 40, value: (6.70 * 100).round(),
);

// Write a name to a fixed-width string field.
final name = ModbusEncoder.writeMultipleRegisters(
  slaveId: 1,
  startAddress: 1100,
  values: ModbusConvert.asciiToRegisters('MyPool', padToRegisters: 16),
);

await transport.send(read); // your BLE / serial / TCP write
```

## Errors

`ModbusDecoder.decode` throws:

| Exception | Meaning |
| --- | --- |
| `ModbusDeviceException` | The device returned an exception response (e.g. illegal address). Inspect `.exceptionCode` / `.description`. |
| `ModbusFrameException` | The bytes are malformed or failed the CRC check. |

```dart
try {
  final response = ModbusDecoder.decode(rawBytes);
} on ModbusDeviceException catch (e) {
  print('Device rejected: ${e.description}');
} on ModbusFrameException catch (e) {
  print('Bad frame: ${e.message}');
}
```

## Supported function codes

| FC | Operation | Encoder | Decoder result |
| --- | --- | --- | --- |
| 01 | Read Coils | `readCoils` | `ReadBitsResponse` |
| 02 | Read Discrete Inputs | `readDiscreteInputs` | `ReadBitsResponse` |
| 03 | Read Holding Registers | `readHoldingRegisters` | `ReadRegistersResponse` |
| 04 | Read Input Registers | `readInputRegisters` | `ReadRegistersResponse` |
| 05 | Write Single Coil | `writeSingleCoil` | `WriteSingleResponse` |
| 06 | Write Single Register | `writeSingleRegister` | `WriteSingleResponse` |
| 15 | Write Multiple Coils | `writeMultipleCoils` | `WriteMultipleResponse` |
| 16 | Write Multiple Registers | `writeMultipleRegisters` | `WriteMultipleResponse` |

## Conversion helpers (`ModbusConvert`)

| Helper | Purpose |
| --- | --- |
| `toSigned16` / `toSigned32` | Two's-complement interpretation |
| `combine32` / `combine32At` | Merge two registers into a 32-bit value (word order selectable) |
| `scale` | Fixed-point division (e.g. `670 / 100 = 6.70`) |
| `asciiFromRegisters` / `asciiToRegisters` | Packed-ASCII decode / encode |
| `bit` | Read a single bit from a value |

## A note on CRC and Modbus TCP

The trailing CRC is for **Modbus RTU**. If you carry RTU frames over a transport
that already guarantees integrity (or you are handling Modbus TCP payloads),
pass `validateCrc: false` to `ModbusDecoder.decode`.

## Example

See [`example/modbus_codec_example.dart`](example/modbus_codec_example.dart) for
a full encode → decode → convert walkthrough.

## License

MIT
