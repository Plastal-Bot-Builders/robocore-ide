// A picture of blocks drawn by the editor's own Blockly (rcEditor.blocks.picture in web/robocore_editors.js), so Cog's
// suggested stacks look exactly like the blocks in the editor.
import 'dart:convert';
import 'dart:typed_data';

class BlockPicture {
  const BlockPicture(this.png, this.width, this.height, this.ratio);

  /// The PNG, [ratio] image pixels to a logical pixel.
  final Uint8List png;

  /// The size to show it at, in logical pixels (the editor's blocks at their starting size).
  final double width, height;
  final double ratio;

  /// From the page's answer: a PNG data: URL and its size; null for anything else.
  static BlockPicture? fromPage(Object? url, Object? width, Object? height, Object? ratio) {
    if (url is! String || width is! num || height is! num || width <= 0 || height <= 0) return null;
    final i = url.indexOf('base64,');
    if (!url.startsWith('data:image/png') || i < 0) return null;
    try {
      return BlockPicture(base64Decode(url.substring(i + 7)), width.toDouble(), height.toDouble(), ratio is num && ratio > 0 ? ratio.toDouble() : 1);
    } on FormatException {
      return null;
    }
  }
}
