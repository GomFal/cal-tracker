import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) return;

      for (final entry in data.entries) {
        final key = entry.key;
        final value = entry.value;
        if (!key.endsWith('_timeline') || value is! Map<String, dynamic>) {
          continue;
        }

        final timeline = driver.Timeline.fromJson(value);
        final summary = driver.TimelineSummary.summarize(timeline);
        await summary.writeTimelineToFile(
          key,
          pretty: true,
          includeSummary: true,
        );
      }
    },
  );
}
