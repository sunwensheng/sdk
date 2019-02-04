// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:analysis_server_client/protocol.dart';
import 'package:dartfix/src/driver.dart';
import 'package:test/test.dart';

import 'test_context.dart';

const _debug = true;
const _updateExample = false;

main() {
  File exampleFile;
  File exampleFixedFile;
  Directory exampleDir;

  setUp(() {
    exampleFile = findFile('pkg/dartfix/example/example.dart');
    exampleFixedFile = findFile('pkg/dartfix/example/example-fixed.dart');
    exampleDir = exampleFile.parent;
  });

  test('client version', () {
    // The edit.dartfix protocol is experimental and will continue to evolve
    // an so dartfix will only work with this specific version of the
    // analysis_server_client package.
    // If the protocol changes, then a new version of both the
    // analysis_server_client and dartfix packages must be published.
    expect(clientVersion, clientVersionInDartfixPubspec);
  });

  test('fix example', () async {
    final driver = new Driver();
    final testContext = new TestContext();
    final testLogger = new TestLogger();
    String exampleSource = await exampleFile.readAsString();

    await driver.start([exampleDir.path],
        testContext: testContext, testLogger: testLogger);
    if (_debug) {
      print(testLogger.stderrBuffer.toString());
      print(testLogger.stdoutBuffer.toString());
      print('--- original example');
      print(exampleSource);
    }

    final suggestions = driver.result.suggestions;
    expect(suggestions, hasLength(2));
    expectHasSuggestion(suggestions, 'Convert MyMixin to a mixin');
    expectHasSuggestion(suggestions, 'Replace a double literal');

    expect(driver.result.edits, hasLength(1));
    for (SourceEdit edit in driver.result.edits[0].edits) {
      exampleSource = edit.apply(exampleSource);
    }
    if (_debug) {
      print('--- fixed example');
      print(exampleSource);
    }

    exampleSource = replaceLeadingComment(exampleSource);
    if (_updateExample) {
      await exampleFixedFile.writeAsString(exampleSource);
    } else {
      final expectedSource = await exampleFixedFile.readAsString();
      expect(exampleSource, expectedSource);
    }
  });

  test('run example', () async {
    if (_debug) print('--- launching original example');
    final futureResult1 =
        Process.run(Platform.resolvedExecutable, [exampleFile.path]);

    if (_debug) print('--- launching fixed example');
    final futureResult2 =
        Process.run(Platform.resolvedExecutable, [exampleFixedFile.path]);

    if (_debug) print('--- waiting for original example');
    final result1 = await futureResult1;

    if (_debug) print('--- waiting for fixed example');
    final result2 = await futureResult2;

    final stdout1 = result1.stdout;
    final stdout2 = result2.stdout;
    if (_debug) {
      print('--- original example output');
      print(stdout1);
      print('--- fixed example output');
      print(stdout2);
    }
    expect(stdout1, stdout2);
  });
}

String get clientVersion =>
    findValue(findFile('pkg/analysis_server_client/pubspec.yaml'), 'version');

String get clientVersionInDartfixPubspec =>
    findValue(findFile('pkg/dartfix/pubspec.yaml'), 'analysis_server_client');

File findFile(String relPath) {
  Directory dir = Directory.current;
  while (true) {
    final file = new File.fromUri(dir.uri.resolve(relPath));
    if (file.existsSync()) {
      return file;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('Failed to find $relPath');
    }
    dir = parent;
  }
}

String findValue(File pubspec, String key) {
  List<String> lines = pubspec.readAsLinesSync();
  for (String line in lines) {
    if (line.trim().startsWith('$key:')) {
      return line.split(':')[1].trim();
    }
  }
  fail('Failed to find $key in ${pubspec.path}');
}

void expectHasSuggestion(
    List<DartFixSuggestion> suggestions, String expectedText) {
  for (DartFixSuggestion suggestion in suggestions) {
    if (suggestion.description.contains(expectedText)) {
      return;
    }
  }
  fail('Failed to find suggestion containing: $expectedText');
}

String replaceLeadingComment(String source) {
  final out = new StringBuffer('''
// This file contains code that has been modified by running dartfix.
// See example.dart for the original unmodified code.
  '''
      .trim());
  final pattern = 'the content of this file matches example-fixed.dart.';
  out.write(source.substring(source.indexOf(pattern) + pattern.length));
  return out.toString();
}
