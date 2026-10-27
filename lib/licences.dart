// About → Licences: what the IDE is made with besides its Dart packages, which register their own licences. The
// fonts and icons come with the app; Blockly, Monaco and esptool-js run in its web pages; the Mac app also carries
// arduino-cli and the board tools, whose notices come with them (tools/make_offline_bundle.sh).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'hw/compile_client.dart' show LocalBuilder;

const _licences = [
  ('Barlow and Barlow Condensed (fonts)', 'assets/licenses/Barlow-OFL.txt'),
  ('JetBrains Mono (font)', 'assets/licenses/JetBrainsMono-OFL.txt'),
  ('Noto Sans Math (font, cut down to its arrows and symbols)', 'assets/licenses/NotoSansMath-OFL.txt'),
  ('Noto Sans Symbols 2 (font, cut down to its symbols)', 'assets/licenses/NotoSansSymbols2-OFL.txt'),
  ('Lucide (icons)', 'assets/licenses/Lucide-LICENSE.txt'),
  ('Google Blockly (blocks editor)', 'web/vendor/blockly/LICENSE'),
  ('Monaco Editor (code editor)', 'web/vendor/monaco/LICENSE'),
  ('Monaco Editor (code editor)', 'web/vendor/monaco/ThirdPartyNotices.txt'),
  ('esptool-js (uploads to ESP32 boards)', 'web/vendor/esptool-js/LICENSE'),
];

void registerLicences(LocalBuilder? local) {
  LicenseRegistry.addLicense(() async* {
    for (final (name, asset) in _licences) {
      yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString(asset));
    }
    final tools = await local?.licences();
    if (tools != null) yield LicenseEntryWithLineBreaks(['arduino-cli and the board tools (Mac app)'], tools);
  });
}
