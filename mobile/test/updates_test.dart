import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/src/data/updates.dart';

void main() {
  group('גרסה חדשה', () {
    test('משווה מספרית ולא לקסיקוגרפית', () {
      expect(Updates.isNewer('0.10.0', '0.9.0'), isTrue);
      expect(Updates.isNewer('1.1.0', '1.0.9'), isTrue);
      expect(Updates.isNewer('1.0.1', '1.0.0'), isTrue);
    });

    test('גרסה זהה או ישנה אינה עדכון', () {
      expect(Updates.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(Updates.isNewer('0.9.0', '1.0.0'), isFalse);
    });

    test('קורא את התג של ה-workflow המאוחד ואת התגים הישנים', () {
      expect(Updates.versionFromTag('v1.2.3'), '1.2.3');
      expect(Updates.versionFromTag('android-v1.2.3'), '1.2.3');
    });
  });
}
