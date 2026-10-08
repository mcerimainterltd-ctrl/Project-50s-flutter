import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/xametel_voice_service.dart';
import '../../../core/theme/app_theme.dart';

class XameTelIncomingCallScreen extends ConsumerStatefulWidget {
  final XameTelEvent event;

  const XameTelIncomingCallScreen({
    super.key,
    required this.event,
  });

  @override
  ConsumerState<XameTelIncomingCallScreen> createState() =>
      _XameTelIncomingCallScreenState();
}

class _XameTelIncomingCallScreenState
    extends ConsumerState<XameTelIncomingCallScreen> {
  StreamSubscription<XameTelEvent>? _eventSub;

  bool _busy = false;
  bool _connected = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();

    final service = ref.read(xameTelVoiceServiceProvider);

    _eventSub = service.events.listen((event) {
      if (!mounted || event.callSid != widget.event.callSid) return;

      switch (event.event) {
        case 'call_connected':
          setState(() {
            _busy = false;
            _connected = true;
          });
          break;

        case 'call_cancelled':
        case 'call_rejected':
        case 'call_disconnected':
        case 'call_error':
          _close();
          break;
      }
    });
  }

  Future<void> _accept() async {
    if (_busy || _connected || _closed) return;

    setState(() => _busy = true);

    final ok = await ref
        .read(xameTelVoiceServiceProvider)
        .acceptIncomingCall(widget.event.callSid);

    if (!mounted || _closed) return;

    if (!ok) {
      setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy || _closed) return;

    setState(() => _busy = true);

    final ok = await ref
        .read(xameTelVoiceServiceProvider)
        .rejectIncomingCall(widget.event.callSid);

    if (mounted) {
      if (ok) {
        _close();
      } else {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disconnect() async {
    if (_busy || !_connected || _closed) return;

    setState(() => _busy = true);

    await ref
        .read(xameTelVoiceServiceProvider)
        .disconnectActiveCall(widget.event.callSid);
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caller = widget.event.from?.trim();
    final callerText =
        caller == null || caller.isEmpty ? 'Unknown caller' : caller;

    return PopScope(
      canPop: !_busy && !_connected,
      child: Scaffold(
        backgroundColor: context.xBg,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.xText.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: 76,
                  backgroundColor: context.xCard,
                  child: Icon(
                    _connected ? Icons.phone_in_talk : Icons.phone,
                    size: 58,
                    color: context.xAccent,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                callerText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.xText,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 14),

              Text(
                _connected
                    ? 'XameTel call connected'
                    : _busy
                        ? 'Connecting…'
                        : 'Incoming XameTel call',
                style: TextStyle(
                  color: context.xText.withOpacity(0.55),
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(flex: 3),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _control(
                      context,
                      icon: _connected ? Icons.call_end : Icons.close,
                      label: _connected ? 'End' : 'Decline',
                      color: Colors.redAccent,
                      onTap: _connected ? _disconnect : _reject,
                    ),
                    if (!_connected)
                      _control(
                        context,
                        icon: Icons.call,
                        label: 'Accept',
                        color: context.xAccent,
                        onTap: _accept,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _control(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        IconButton.filled(
          onPressed: _busy ? null : onTap,
          icon: Icon(icon, size: 30),
          style: IconButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withOpacity(0.35),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(18),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: context.xText.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
