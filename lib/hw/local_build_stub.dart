// The web app compiles on the compile server only.
import '../engine/compiler.dart' show SourceFile;
import 'compile_client.dart' show ServerBuild;

class LocalBuilder {
  bool get supported => false;

  Future<ServerBuild> compile({required String board, required List<SourceFile> files, required void Function(String) log}) async =>
      ServerBuild.failed('Compiling on this computer needs the Windows app.');
}
