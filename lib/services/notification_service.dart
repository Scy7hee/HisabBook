import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const int dailyReminderId = 9001;

  Future<void> initializeAndScheduleDailyReminder() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (error) {
      debugPrint('Could not detect device timezone: $error');
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(settings: initializationSettings);

    _initialized = true;

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.requestNotificationsPermission();

    await scheduleDailyReminder();
  }

  Future<void> scheduleDailyReminder({int hour = 21, int minute = 0}) async {
    if (!_initialized) {
      await initializeAndScheduleDailyReminder();
      return;
    }

    final now = tz.TZDateTime.now(tz.local);

    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }

    const androidDetails = AndroidNotificationDetails(
      'hisabbook_daily_reminder',
      'Daily HisabBook Reminder',
      channelDescription: 'A daily reminder to record your finances.',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.zonedSchedule(
      id: dailyReminderId,
      title: 'Time to update HisabBook',
      body: 'Aaj ka hisaab likh lo. Record today’s income and expenses.',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> showGoalCompleted({
    required int goalId,
    required String goalTitle,
  }) async {
    if (!_initialized) {
      await initializeAndScheduleDailyReminder();
    }

    final notificationId = 10000 + goalId;

    await _plugin.show(
      id: notificationId,
      title: 'Savings goal completed!',
      body: 'Congratulations! You reached your "$goalTitle" goal.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'hisabbook_goal_completed',
          'Savings Goal Completed',
          channelDescription:
              'Notifications shown when a savings goal is completed.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}
