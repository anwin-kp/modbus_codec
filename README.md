# modbus_codec

Talk to Modbus devices over BLE (or serial / TCP) from Flutter/Dart.  
Build the bytes to send → get clean values back from the bytes you receive.  
Zero dependencies, pure Dart.

## Install

```yaml
dependencies:
  modbus_codec: ^0.1.1
```

## The idea in one picture

```
your app  ──►  ModbusEncoder  ──►  bytes  ──►  BLE write  ──►  device
your app  ◄──  ModbusDecoder  ◄──  bytes  ◄──  BLE notify ◄──  device
```

You never touch raw bytes yourself — the encoder builds them, the decoder
reads them.

---

## Send a request

```dart
import 'package:modbus_codec/modbus_codec.dart';

// Read 10 registers starting at address 0, from device #1.
final bytes = ModbusEncoder.readHoldingRegisters(
  slaveId: 1,
  startAddress: 0,
  quantity: 10,
);

await bleCharacteristic.write(bytes);
```

That's it. `bytes` is a `List<int>` ready to write straight to a BLE
characteristic.

---

## Read the response

```dart
// `received` is the List<int> from your BLE notification callback.
final response = ModbusDecoder.decode(received);

if (response is ReadRegistersResponse) {
  final regs = response.registers; // plain list of numbers

  final temperature = ModbusConvert.scale(regs[0], factor: 10); // 245 → 24.5
  final isRunning   = regs[1] == 1;
  final errorCode   = ModbusConvert.toSigned16(regs[2]);         // can be negative
}
```

---

## Write a value

```dart
// Turn a pump ON (coil at address 5).
final onCmd = ModbusEncoder.writeSingleCoil(
  slaveId: 1,
  address: 5,
  value: true,
);
await bleCharacteristic.write(onCmd);

// Set a setpoint — device stores pH 6.70 as the integer 670.
final setCmd = ModbusEncoder.writeSingleRegister(
  slaveId: 1,
  address: 40,
  value: 670,
);
await bleCharacteristic.write(setCmd);
```

---

## Handle errors

```dart
try {
  final response = ModbusDecoder.decode(received);
  // use response...
} on ModbusDeviceException catch (e) {
  // The device understood the request but rejected it (e.g. bad address).
  print('Device error: ${e.description}');
} on ModbusFrameException catch (e) {
  // The bytes were garbled or corrupted.
  print('Bad data: ${e.message}');
}
```

---

## Read coils (on/off bits)

```dart
final bytes = ModbusEncoder.readCoils(
  slaveId: 1,
  startAddress: 0,
  quantity: 8,
);
await bleCharacteristic.write(bytes);

// ... in your notification handler:
final response = ModbusDecoder.decode(received) as ReadBitsResponse;
// Slice to however many you requested — response may contain padding bits.
final coils = response.values.sublist(0, 8);
// coils[0] = first coil, coils[1] = second coil, etc.
```

---

## Convert register values

Most Modbus devices store numbers in simple integer formats. `ModbusConvert`
helps you turn them into real values:

```dart
// Device sends 245, means 24.5 °C (divided by 10).
final temp = ModbusConvert.scale(regs[0], factor: 10);   // → 24.5

// Negative values (e.g. –5 stored as 65531).
final offset = ModbusConvert.toSigned16(regs[1]);         // → –5

// 32-bit value spread across two consecutive registers.
final totalFlow = ModbusConvert.combine32At(regs, 4);     // regs[4] + regs[5]

// Device name stored as text.
final name = ModbusConvert.asciiFromRegisters(regs.sublist(10, 18)); // → "Pump1"
```

---

## Write text to a device

```dart
final bytes = ModbusEncoder.writeMultipleRegisters(
  slaveId: 1,
  startAddress: 100,
  values: ModbusConvert.asciiToRegisters('MyPool', padToRegisters: 8),
);
await bleCharacteristic.write(bytes);
```

---

## What's available

### Encoder (build bytes to send)

| Method | What it does |
|---|---|
| `readHoldingRegisters` | Read sensor/config values |
| `readInputRegisters` | Read read-only sensor values |
| `readCoils` | Read on/off outputs |
| `readDiscreteInputs` | Read read-only on/off inputs |
| `writeSingleRegister` | Write one value |
| `writeSingleCoil` | Turn one output on/off |
| `writeMultipleRegisters` | Write several values at once |
| `writeMultipleCoils` | Set several outputs at once |

### Decoder (read bytes received)

Pass the raw `List<int>` from your BLE notification to `ModbusDecoder.decode`.
It returns one of:

| Type | When you get it |
|---|---|
| `ReadRegistersResponse` | Response to any register read |
| `ReadBitsResponse` | Response to a coil/discrete read |
| `WriteSingleResponse` | Echo after a single write |
| `WriteMultipleResponse` | Echo after a multiple write |

### Convert helpers

| Helper | Use case |
|---|---|
| `scale(value, factor: 10)` | Fixed-point → decimal (e.g. 245 → 24.5) |
| `toSigned16(value)` | Unsigned int → signed (handles negative values) |
| `combine32At(regs, index)` | Two registers → one 32-bit number |
| `asciiFromRegisters(regs)` | Registers → text string |
| `asciiToRegisters(text)` | Text string → registers |
| `bit(value, position)` | Read a single bit flag from a register |

---

## License

MIT
