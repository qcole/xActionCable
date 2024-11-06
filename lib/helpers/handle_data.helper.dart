import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:x_action_cable/store/action_channel_callbacks_store.dart';

import '../models/action_response.dart';
import 'package:logger/logger.dart';

import '../types.dart';
import 'identifier.helper.dart';
import 'logger.helper.dart';

class HandleDataHelper {
  final ActionChannelCallbacksStore actionChannelCallbacksStore;

  final VoidCallback? _onConnected;
  final OnPingMessage _onPingMessage;

  HandleDataHelper({
    required this.actionChannelCallbacksStore,
    required VoidCallback? onConnected,
    required OnPingMessage onPingMessage,
  })  : _onConnected = onConnected,
        _onPingMessage = onPingMessage;

  void onData(dynamic payload) {
    payload = jsonDecode(payload);
    ActionLoggerHelper.log(payload);

    if (payload['type'] != null) {
      _handleProtocolMessage(payload);
    } else {
      _handleDataMessage(payload);
    }
  }

  void _handleProtocolMessage(Map payload) {
    switch (payload['type']) {
      case 'ping':
        _onPing(payload);
        break;
      case 'welcome':
        _onWelcome();
        break;
      case 'disconnect':
        _onDisconnected(payload);
        break;
      case 'confirm_subscription':
        _onConfirmSubscription(payload);
        break;
      case 'reject_subscription':
        _onRejectSubscription();
        break;
      default:
        throw 'InvalidMessage';
    }
  }

  void _handleDataMessage(Map<String, dynamic> payload) {
    final channelId = IdentifierHelper.parseChannelId(payload['identifier']);
    final onMessageCallback =
        this.actionChannelCallbacksStore.message[channelId];
    if (onMessageCallback == null) {
      Logger().e('Currently you are disconnected from channel = $channelId');
      return;
    }

    final methodName = payload['message']['method'] as String?;
    if (methodName == null) {
      Logger().e(
        'The server it\'s not sending the method on payload. Try to add a "method" key on json in your server.\nMessage: ${payload}',
      );
      return;
    }

    final actionCallback = onMessageCallback.firstWhereOrNull(
      (e) => e.name.toLowerCase() == methodName.toLowerCase(),
    );

    if (actionCallback == null) {
      Logger().e(
        'Server tried to send a message that the application did not register with ActionCallback.\nTry to register when you go to subscribe to a channel.\nMethod: ${payload['message']['method']}',
      );
      return;
    }

    final response = ActionResponse(
      data: payload['message']['data'],
      error: payload['message']['error'],
    );

    actionCallback.callback(response);
  }

  void _onPing(Map _) {
    // Note: You cannot rely on the clocks being synchronized. Therefore, you cannot use the
    // timestamp of the server to detect timeouts! ALWAYS use your local clock!!!
    // It could also be wrong, but that's not a problem as long as we compare the times with ourselves!
    _onPingMessage(DateTime.now());
  }

  void _onWelcome() => _onConnected?.call();

  void _onDisconnected(Map payload) {
    final channelId = IdentifierHelper.parseChannelId(payload['identifier']);
    final onDisconnected =
        this.actionChannelCallbacksStore.disconnected[channelId];
    onDisconnected?.call();
  }

  void _onConfirmSubscription(Map payload) {
    final channelId = IdentifierHelper.parseChannelId(payload['identifier']);

    // Remove the subscribeTimedOut callback after the subscription was confirmed.
    final onSubscribed = this.actionChannelCallbacksStore.subscribed[channelId];
    this.actionChannelCallbacksStore.subscribeTimedOut.remove(channelId);
    if (onSubscribed != null) {
      onSubscribed();
    }
  }

  void _onRejectSubscription() {}
}
