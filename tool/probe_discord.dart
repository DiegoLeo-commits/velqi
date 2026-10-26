import 'dart:async';
import 'dart:io';

import 'package:discord_rich_presence/discord_rich_presence.dart';

Future<void> main(List<String> args) async {
  final clientId = args.isNotEmpty ? args[0] : '154414874584615987';
  print('connecting with client id $clientId ...');
  final client = Client(clientId: clientId);
  try {
    await client.connect();
    print('CONNECTED');
  } catch (e) {
    print('CONNECT FAILED: $e');
    exit(1);
  }
  await Future.delayed(const Duration(milliseconds: 300));

  for (final attempt in [1, 2, 3]) {
    try {
      await client.setActivity(
        Activity(
          name: 'Velqi',
          type: ActivityType.listening,
          details: 'Probe song $attempt',
          state: 'Probe artist',
          timestamps: ActivityTimestamps(start: DateTime.now()),
        ),
      );
      print('setActivity #$attempt OK');
    } catch (e, st) {
      print('setActivity #$attempt FAILED: $e');
      print(st.toString().split('\n').take(4).join('\n'));
    }
    await Future.delayed(const Duration(milliseconds: 800));
  }
  await client.disconnect();
  print('done');
  exit(0);
}
