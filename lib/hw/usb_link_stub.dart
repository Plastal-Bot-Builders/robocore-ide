// USB link for platforms without Web Serial (tests and, for now, the native apps).
import 'usb_link.dart';

class _NoUsb extends UsbLink {
  @override
  bool get supported => false;
  @override
  bool get isOpen => false;
  @override
  Future<UsbResult> connect({required int baud, bool espressifOnly = false}) async => UsbResult.unsupported;
  @override
  Future<UsbResult> reconnect({required int baud}) async => UsbResult.unsupported;
  @override
  Future<UsbResult> disconnect() async => const UsbResult(true);
  @override
  Future<UsbResult> setBaud(int baud) async => const UsbResult(true);
  @override
  Future<UsbResult> write(String text) async => UsbResult.unsupported;
  @override
  Future<UsbResult> reset({String arch = 'esp32'}) async => UsbResult.unsupported;
  @override
  Future<UsbResult> flash(Map<String, dynamic> job) async => UsbResult.unsupported;
  @override
  Future<UsbResult> cancelFlash() async => const UsbResult(true);
  @override
  Future<UsbResult> identify({required int baud, String arch = 'esp32'}) async => UsbResult.unsupported;
}

UsbLink createUsbLink() => _NoUsb();
