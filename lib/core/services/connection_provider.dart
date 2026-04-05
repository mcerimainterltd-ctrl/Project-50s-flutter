import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'socket_service.dart';

final connectionStateProvider = StreamProvider<SocketState>((ref) {
  final socket = ref.watch(socketServiceProvider);
  return socket.connectionState;
});
