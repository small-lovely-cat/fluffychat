/*
 *   Famedly
 *   Copyright (C) 2020, 2021 Famedly GmbH
 *   Copyright (C) 2021 Fluffychat
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as
 *   published by the Free Software Foundation, either version 3 of the
 *   License, or (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:fluffychat/main.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_new_badger/flutter_new_badger.dart';
import 'package:matrix/matrix.dart';

import '../widgets/matrix.dart';

class BackgroundPush {
  static BackgroundPush? _instance;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Client client;
  MatrixState? matrix;

  BackgroundPush._(this.client) {
    unawaited(_init());
  }

  factory BackgroundPush.clientOnly(Client client) {
    return _instance ??= BackgroundPush._(client);
  }

  factory BackgroundPush(MatrixState matrix) {
    final instance = BackgroundPush.clientOnly(matrix.client);
    instance.client = matrix.client;
    instance.matrix = matrix;
    return instance;
  }

  /// 初始化本地通知点击回调与通知插件。
  ///
  /// 参数：无。
  /// 返回值：返回初始化完成后的异步任务。
  /// 用途：保留本地通知点击跳转与角标清理能力；Firebase 与 UnifiedPush
  /// 远程推送注册已按需求移除。
  Future<void> _init() async {
    try {
      mainIsolateReceivePort?.listen((message) async {
        try {
          await notificationTap(
            NotificationResponseJson.fromJsonString(message),
            client: client,
            router: FluffyChatApp.router,
          );
        } catch (e, s) {
          Logs().wtf('Main Notification Tap crashed', e, s);
        }
      });

      if (Platform.isAndroid) {
        final port = ReceivePort();
        IsolateNameServer.removePortNameMapping('background_tab_port');
        IsolateNameServer.registerPortWithName(
          port.sendPort,
          'background_tab_port',
        );
        port.listen((message) async {
          try {
            await notificationTap(
              NotificationResponseJson.fromJsonString(message),
              client: client,
              router: FluffyChatApp.router,
            );
          } catch (e, s) {
            Logs().wtf('Main Notification Tap crashed', e, s);
          }
        });
      }

      await _flutterLocalNotificationsPlugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('notifications_icon'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) => notificationTap(
          response,
          client: client,
          router: FluffyChatApp.router,
        ),
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      Logs().i(
        '[Push] Firebase and UnifiedPush support removed. '
        'Skip remote push registration.',
      );
    } catch (e, s) {
      Logs().e('Unable to initialize Flutter local notifications', e, s);
    }
  }

  /// 取消指定房间的本地通知，并同步更新 iOS 角标。
  ///
  /// 参数：
  /// - roomId: 需要清理通知的 Matrix 房间 ID。
  /// 返回值：返回清理通知完成后的异步任务。
  /// 用途：用户进入房间后清理遗留的本地通知，避免旧通知与未读角标残留。
  Future<void> cancelNotification(String roomId) async {
    Logs().v('Cancel notification for room', roomId);
    await _flutterLocalNotificationsPlugin.cancel(id: roomId.hashCode);

    if (!Platform.isIOS) {
      return;
    }

    final activeClient = matrix?.client ?? client;
    final unreadCount = activeClient.rooms
        .where((room) => room.isUnreadOrInvited && room.id != roomId)
        .length;

    if (unreadCount == 0) {
      FlutterNewBadger.removeBadge();
      return;
    }

    FlutterNewBadger.setBadge(unreadCount);
  }
}
