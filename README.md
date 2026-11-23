# modbus_codec

Talk to Modbus RTU devices over BLE (or serial / RTU-over-TCP) from Flutter/Dart.  
Build the bytes to send → get clean values back from the bytes you receive.  
Zero dependencies, pure Dart.

## Install

```yaml
dependencies:
  modbus_codec: ^0.2.0
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

BLE notifications are small (often 20 bytes), so a bigger response arrives in
several pieces. Feed every notification to a `ModbusFrameAssembler`; it hands
you each response once all of its bytes are in:

```dart
final assembler = ModbusFrameAssembler();

characteristic.onValueReceived.listen((chunk) {
  for (final frame in assembler.add(chunk)) {
    handle(ModbusDecoder.decode(frame));
  }
});

// If a request times out, drop any half-received response:
assembler.reset();
```

Then use the values:

```dart
void handle(ModbusResponse response) {

if (response is ReadRegistersResponse) {
  final regs = response.registers; // plain list of numbers

  final temperature = ModbusConvert.scale(regs[0], factor: 10); // 245 → 24.5
  final isRunning   = regs[1] == 1;
  final errorCode   = ModbusConvert.toSigned16(regs[2]);         // can be negative
}
}
```

`received` in the examples below is one complete frame from the assembler.

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
final totalFlow = ModbusConvert.combine32At(regs, 4);     // regs[4]<<16 | regs[5]

// Floating-point value (IEEE-754 float32) in two registers.
final pressure = ModbusConvert.float32At(regs, 6);        // → 1.013

// Device name stored as text (8 registers = up to 16 characters).
final name = ModbusConvert.asciiFromRegisters(regs.sublist(8, 16)); // → "Pump1"
```

32-bit values have no standard layout. If you get nonsense, try
`order: ModbusWordOrder.lowWordFirst`; if still wrong, the device also swaps
bytes — pass each register through `ModbusConvert.swapBytes16` first.

---

## Write numbers that don't fit one register

```dart
// Negative value → raw register.
ModbusEncoder.writeSingleRegister(
  slaveId: 1, address: 20, value: ModbusConvert.fromSigned16(-5), // 65531
);

// Float or 32-bit integer → two registers.
ModbusEncoder.writeMultipleRegisters(
  slaveId: 1, startAddress: 30, values: ModbusConvert.fromFloat32(7.25),
);
ModbusEncoder.writeMultipleRegisters(
  slaveId: 1, startAddress: 32, values: ModbusConvert.split32(100000),
);
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

Pass one complete frame (from `ModbusFrameAssembler`) to `ModbusDecoder.decode`.
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
| `float32At(regs, index)` | Two registers → `double` (IEEE-754 float) |
| `fromFloat32(value)` | `double` → two registers to write |
| `split32(value)` | 32-bit integer → two registers to write |
| `fromSigned16(value)` | Negative number → register value to write |
| `swapBytes16(value)` | Swap the two bytes of a register (BADC/DCBA devices) |
| `asciiFromRegisters(regs)` | Registers → text string |
| `asciiToRegisters(text)` | Text string → registers |
| `bit(value, position)` | Read a single bit flag (position 0–31) from a register |

### Reassembly

| Helper | Use case |
|---|---|
| `ModbusFrameAssembler` | Join BLE notification chunks into complete frames |
| `ModbusDecoder.expectedLength(bytes)` | Total frame length from the first 2–3 bytes |

---

## Scope

This package encodes and decodes **Modbus RTU** frames (with CRC). It works over
any transport that carries RTU bytes: BLE, serial, or RTU-over-TCP gateways.
Native Modbus TCP (MBAP header, no CRC) is not supported. Read requests must
target a single device (`slaveId` 1–247); broadcast (`slaveId` 0) is for
writes only, and devices don't reply to it.

---

## License

MIT
