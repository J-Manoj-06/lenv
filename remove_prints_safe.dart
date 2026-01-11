import 'dart:io';

void main() async {
  final libDir = Directory('lib');
  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  print('Processing ${dartFiles.length} Dart files...');

  int filesProcessed = 0;
  int printsRemoved = 0;

  for (final file in dartFiles) {
    final lines = await file.readAsLines();
    final newLines = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // Skip lines that are print/debugPrint statements
      if (trimmed.startsWith('print(') || trimmed.startsWith('debugPrint(')) {
        // Count opening and closing parentheses
        int openCount = line.split('(').length - 1;
        int closeCount = line.split(')').length - 1;

        // If single line print (equal parens), skip it
        if (openCount == closeCount) {
          printsRemoved++;
          continue;
        }

        // Multi-line print: skip lines until we find matching closing paren
        printsRemoved++;
        int balance = openCount - closeCount;
        while (balance > 0 && i + 1 < lines.length) {
          i++;
          final nextLine = lines[i];
          openCount = nextLine.split('(').length - 1;
          closeCount = nextLine.split(')').length - 1;
          balance += openCount - closeCount;
        }
        continue;
      }

      newLines.add(line);
    }

    if (newLines.length != lines.length) {
      await file.writeAsString('${newLines.join('\n')}\n');
      filesProcessed++;
    }
  }

  print('\nDone!');
  print('Files processed: $filesProcessed');
  print('Print statements removed: $printsRemoved');
}
