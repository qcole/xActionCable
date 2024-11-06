import 'package:x_action_cable/types.dart';

/// Callback stores for action channels.
class ActionChannelCallbacksStore {
  Map<String, VoidCallback?> subscribed = {};
  Map<String, VoidCallback?> disconnected = {};
  Map<String, VoidCallback?> subscribeTimedOut = {};
  OnMessageCallbacks message = {};
}
