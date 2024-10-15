import 'dart:async';
import 'dart:convert';

import 'package:x_action_cable/store/callbacks.store.dart';
import 'package:x_action_cable/types.dart';

/// This class represents the channel that you are going to perfome actions
/// Like:
/// ```Dart
/// channel.performAction(
///   action: 'send_message',
///   actionParams: { 'message': 'Hello private peeps! 😜' }
/// );
/// ```
class ActionChannel {
  final String identifier;

  final Duration subscriptionTimeout;
  final SendMessageCallback _sendMessageCallback;

  Timer? _subscriptionTimeoutTimer;

  ActionChannel({
    required this.identifier,
    required this.subscriptionTimeout,
    required SendMessageCallback sendMessageCallback,
  }) : _sendMessageCallback = sendMessageCallback {
    this._subscriptionTimeoutTimer = Timer(
      this.subscriptionTimeout,
      () {
        // Try to call the subscribeTimedOut callback when the Timer finishes.
        // If the subscription has been confirmed in the meantime, that
        // callback will have been removed by now.
        // Otherwise this is a timeout.
        final VoidCallback? subscriptionTimeout =
            CallbacksStore.subscribeTimedOut[this.identifier];
        subscriptionTimeout?.call();
      },
    );
  }

  /// If you need to unsubscribe
  /// ```Dart
  /// channel.unsubscribe();
  /// ```
  void unsubscribe() {
    CallbacksStore.subscribed.remove(identifier);
    CallbacksStore.subscribeTimedOut.remove(identifier);
    CallbacksStore.diconnected.remove(identifier);
    CallbacksStore.message.remove(identifier);

    this._subscriptionTimeoutTimer?.cancel();

    final command = {'identifier': identifier, 'command': 'unsubscribe'};
    _sendMessageCallback(command);
  }

  /// If you need to perfome an action in your channel just call this method passing the name of your action that you need to call on server
  /// ```Dart
  /// channel.performAction(
  ///   action: 'send_message',
  ///   actionParams: { 'message': 'Hello private peeps! 😜' }
  /// );
  /// ```
  void performAction(
    String action, {
    Map<String, dynamic>? params,
  }) {
    params ??= {};
    params['action'] = action;

    final command = {
      'identifier': identifier,
      'command': 'message',
      'data': jsonEncode(params)
    };

    _sendMessageCallback(command);
  }
}
