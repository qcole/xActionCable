import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:x_action_cable/store/action_channel_callbacks_store.dart';
import 'package:x_action_cable/types.dart';
import 'package:x_action_cable/web_socket/abstractions/web_socket.interface.dart';

import '../helpers/handle_data.helper.dart';
import '../helpers/identifier.helper.dart';
import '../helpers/logger.helper.dart';
import 'action_callback.dart';
import 'action_channel.dart';

IWebSocket _webSocket = IWebSocket();

const Duration _kSubscriptionTimeout = Duration(seconds: 4);

class ActionCable {
  /// Last ping to calculate when need to drop the connection
  /// because it passed 6 seconds without response from server
  DateTime? _lastPing;

  /// WebSocket for connect to ActionCable on rails
  late WebSocketChannel _socketChannel;

  /// Stream for listen data trough websocket
  late StreamSubscription _listener;

  /// Timer for helth check
  late Timer _timer;

  final ActionChannelCallbacksStore _actionChannelCallbacksStore =
      ActionChannelCallbacksStore();

  /// Factory for connect to ActionCable on Rails
  ActionCable.connect(
    String url, {
    Map<String, String> headers: const {},
    VoidCallback? onConnected,
    VoidCallback? onConnectionLost,
    required void Function(dynamic reason)? onCannotConnect,
  }) {
    final handleDataHelper = _createHandleDataHelper(
      actionChannelCallbacksStore: this._actionChannelCallbacksStore,
      onConnected: onConnected,
      onConnectionLost: onConnectionLost,
    );
    final socketChannel = _createSocketChannel(url: url, headers: headers);
    _addHandleDataListener(
      handleData: handleDataHelper,
      onCannotConnect: onCannotConnect,
      socketChannel: socketChannel,
    );
    _addHandleHelthCheckListener(onConnectionLost);
  }

  HandleDataHelper _createHandleDataHelper({
    required ActionChannelCallbacksStore actionChannelCallbacksStore,
    required VoidCallback? onConnected,
    required VoidCallback? onConnectionLost,
  }) {
    return HandleDataHelper(
      actionChannelCallbacksStore: actionChannelCallbacksStore,
      onConnected: onConnected,
      onPingMessage: (time) {
        _lastPing = time;
      },
    );
  }

  WebSocketChannel _createSocketChannel({
    required String url,
    required Map<String, String> headers,
  }) {
    // rails gets a ping every 3 seconds
    final socketChannel = _webSocket.connect(
      url,
      headers: headers,
      pingInterval: Duration(seconds: 3),
    );

    _socketChannel = socketChannel;

    return socketChannel;
  }

  void _addHandleDataListener({
    required WebSocketChannel socketChannel,
    required HandleDataHelper handleData,
    required void Function(dynamic message)? onCannotConnect,
  }) {
    _listener = socketChannel.stream.listen(
      handleData.onData,
      onError: (reason) {
        disconnect(); // close a socket and the timer
        onCannotConnect?.call(reason);
      },
    );
  }

  void disconnect() {
    _timer.cancel();
    _socketChannel.sink.close();
    _listener.cancel();

    // All action channels are disconnected when the main ActionCable connection is.
    for (VoidCallback? onDisconnected
        in this._actionChannelCallbacksStore.disconnected.values) {
      onDisconnected?.call();
    }
  }

  void _send(Map<String, dynamic> payload) {
    _socketChannel.sink.add(jsonEncode(payload));
    ActionLoggerHelper.log(payload);
  }

  void _addHandleHelthCheckListener(VoidCallback? onConnectionLost) {
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _healthCheck(onConnectionLost: onConnectionLost);
    });
  }

  void _healthCheck({VoidCallback? onConnectionLost}) {
    if (_lastPing == null) return;

    if (DateTime.now().difference(_lastPing!) > Duration(seconds: 6)) {
      onConnectionLost?.call();
      disconnect();
    }
  }

  /// Subscribe to a channel
  /// ```Dart
  /// void receiveMessage(Map payload) => print(payload);
  /// final actionCallback = ActionCallback(name: 'receive_message', callback: receiveMessage);
  ///
  ///  ActionChannel channel = cable.subscribe(
  ///   'Chat', // either 'Chat' and 'ChatChannel' is fine
  ///    channelParams: { 'room': 'private' },
  ///    onSubscribed: (){}, // `confirm_subscription` received
  ///    onSubscribeTimedOut: (){}, // Didn't receive `confirm_subscription` within [subscriptionTimeout].
  ///    onDisconnected: (){}, // `disconnect` received
  ///    callbacks: [actionCallback] // Callback list to able the server  to call any method that you registered in your aplicaticon
  ///  );
  /// ```
  ActionChannel subscribe(
    String channelName, {
    Map? channelParams,
    VoidCallback? onSubscribed,
    VoidCallback? onSubscribeTimedOut,
    VoidCallback? onDisconnected,
    List<ActionCallback> callbacks = const [],
    Duration subscriptionTimeout = _kSubscriptionTimeout,
  }) {
    final identifier = IdentifierHelper.encodeChanelId(
      channelName,
      channelParams,
    );

    this._actionChannelCallbacksStore.subscribed[identifier] = onSubscribed;
    this._actionChannelCallbacksStore.subscribeTimedOut[identifier] =
        onSubscribeTimedOut;
    this._actionChannelCallbacksStore.disconnected[identifier] = onDisconnected;
    this._actionChannelCallbacksStore.message[identifier] = callbacks;

    _send({'identifier': identifier, 'command': 'subscribe'});

    return ActionChannel(
      actionChannelCallbacksStore: this._actionChannelCallbacksStore,
      identifier: identifier,
      subscriptionTimeout: subscriptionTimeout,
      sendMessageCallback: _send,
    );
  }
}
