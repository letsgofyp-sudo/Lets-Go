import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/profile/profile_general_info_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/profile/profile_general_info_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ProfileGeneralInfoController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bgetCnicImages\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bhydrateProfile\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bimageUrl\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bresolveCnic\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bresolvePhone\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bresolveString\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsaveChanges\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetEditing\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btoggleEdit\s*\(').hasMatch(source), isTrue);
    });
  });
}