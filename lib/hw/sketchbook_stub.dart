// The web app: projects stay in the browser's storage.
import '../state/project_folder.dart';

bool get projectsFolderSupported => false;

Future<ProjectFolder?> restoreProjectsFolder() async => null;

Future<ProjectFolder?> chooseProjectsFolder() async => null;

Future<ProjectFolder?> defaultProjectsFolder() async => null;

ProjectFolder? projectsFolderAt(String path) => null;

/// Open from computer (the desktop apps only).
bool get canOpenSketch => false;

Future<(String, Map<String, String>, String?)?> pickSketch() async => null;
