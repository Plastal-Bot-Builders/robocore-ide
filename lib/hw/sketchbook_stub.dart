// The web app: projects stay in the browser's storage.
import '../state/project_folder.dart';

bool get projectsFolderSupported => false;

Future<ProjectFolder?> restoreProjectsFolder() async => null;

Future<ProjectFolder?> chooseProjectsFolder() async => null;

ProjectFolder? projectsFolderAt(String path) => null;

/// File > Open Sketch… (the macOS app only).
Future<(String, Map<String, String>)?> pickSketch() async => null;
