/// Standard Modbus function codes.
///
/// These identify the operation a request performs and appear as the second
/// byte of every Modbus RTU frame (immediately after the slave/unit id).
///
/// An error response uses the request's function code OR-ed with [errorMask]
/// (`0x80`). For example, an error reply to [readHoldingRegisters] (`0x03`)
/// arrives as `0x83`.
abstract final class ModbusFunctionCode {
  /// FC 01 — Read Coils (1-bit, read/write outputs).
  static const int readCoils = 0x01;

  /// FC 02 — Read Discrete Inputs (1-bit, read-only inputs).
  static const int readDiscreteInputs = 0x02;

  /// FC 03 — Read Holding Registers (16-bit, read/write).
  static const int readHoldingRegisters = 0x03;

  /// FC 04 — Read Input Registers (16-bit, read-only).
  static const int readInputRegisters = 0x04;

  /// FC 05 — Write Single Coil.
  static const int writeSingleCoil = 0x05;

  /// FC 06 — Write Single Holding Register.
  static const int writeSingleRegister = 0x06;

  /// FC 15 (0x0F) — Write Multiple Coils.
  static const int writeMultipleCoils = 0x0F;

  /// FC 16 (0x10) — Write Multiple Holding Registers.
  static const int writeMultipleRegisters = 0x10;

  /// Bit OR-ed onto a function code to signal an exception response.
  static const int errorMask = 0x80;

  /// The `0xFF00` value a device expects to turn a coil ON (FC 05).
  static const int coilOn = 0xFF00;

  /// The `0x0000` value a device expects to turn a coil OFF (FC 05).
  static const int coilOff = 0x0000;
}

/// Modbus exception (error) codes carried in an exception response.
///
/// Surfaced via `ModbusDeviceException`. The numeric value is the
/// device-supplied reason a request could not be fulfilled.
abstract final class ModbusExceptionCode {
  /// 0x01 — The function code is not supported by the device.
  static const int illegalFunction = 0x01;

  /// 0x02 — The data address (register/coil) does not exist on the device.
  static const int illegalDataAddress = 0x02;

  /// 0x03 — A value in the request is outside the allowable range.
  static const int illegalDataValue = 0x03;

  /// 0x04 — An unrecoverable error occurred on the device.
  static const int serverDeviceFailure = 0x04;

  /// 0x05 — The request was accepted; the device needs a long time to process.
  static const int acknowledge = 0x05;

  /// 0x06 — The device is busy processing a long-duration command.
  static const int serverDeviceBusy = 0x06;

  /// 0x08 — A memory parity error was detected.
  static const int memoryParityError = 0x08;

  /// 0x0A — The gateway could not allocate an internal path.
  static const int gatewayPathUnavailable = 0x0A;

  /// 0x0B — The target device failed to respond through the gateway.
  static const int gatewayTargetFailedToRespond = 0x0B;

  /// Returns a human-readable description for an exception [code].
  static String describe(int code) {
    switch (code) {
      case illegalFunction:
        return 'Illegal function: the function code is not supported.';
      case illegalDataAddress:
        return 'Illegal data address: the address does not exist on the device.';
      case illegalDataValue:
        return 'Illegal data value: a value in the request is out of range.';
      case serverDeviceFailure:
        return 'Server device failure: an unrecoverable device error occurred.';
      case acknowledge:
        return 'Acknowledge: request accepted, processing will take time.';
      case serverDeviceBusy:
        return 'Server device busy: the device is processing another command.';
      case memoryParityError:
        return 'Memory parity error.';
      case gatewayPathUnavailable:
        return 'Gateway path unavailable.';
      case gatewayTargetFailedToRespond:
        return 'Gateway target device failed to respond.';
      default:
        return 'Unknown Modbus exception code: 0x${code.toRadixString(16)}.';
    }
  }
}
