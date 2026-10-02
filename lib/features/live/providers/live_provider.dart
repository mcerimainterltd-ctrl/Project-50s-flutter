import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/services/socket_service.dart';
import '../data/live_api.dart';
import '../models/live_session.dart';
import '../models/live_entitlement.dart';
import '../services/go_live_billing_service.dart';

final liveProvider =
    StateNotifierProvider<LiveNotifier, LiveState>((ref) {
  final notifier = LiveNotifier(
    ref.read(socketServiceProvider),
    LiveApi(),
  );

  ref.onDispose(notifier.dispose);
  return notifier;
});

class LiveState {
  final List<LiveSession> activeLives;
  final LiveSession? broadcasterSession;
  final LiveSession? viewerSession;
  final bool loading;
  final bool entitlementLoading;
  final GoLiveEntitlement? entitlement;
  final List<GoLivePlan> plans;
  final bool billingLoading;
  final bool billingAvailable;
  final bool billingProcessing;
  final String? billingError;
  final String? error;

  const LiveState({
    this.activeLives = const [],
    this.broadcasterSession,
    this.viewerSession,
    this.loading = false,
    this.entitlementLoading = false,
    this.entitlement,
    this.plans = const [],
    this.billingLoading = false,
    this.billingAvailable = false,
    this.billingProcessing = false,
    this.billingError,
    this.error,
  });

  LiveState copyWith({
    List<LiveSession>? activeLives,
    LiveSession? broadcasterSession,
    bool clearBroadcasterSession = false,
    LiveSession? viewerSession,
    bool clearViewerSession = false,
    bool? loading,
    bool? entitlementLoading,
    GoLiveEntitlement? entitlement,
    bool clearEntitlement = false,
    List<GoLivePlan>? plans,
    bool? billingLoading,
    bool? billingAvailable,
    bool? billingProcessing,
    String? billingError,
    bool clearBillingError = false,
    String? error,
    bool clearError = false,
  }) {
    return LiveState(
      activeLives: activeLives ?? this.activeLives,
      broadcasterSession: clearBroadcasterSession
          ? null
          : broadcasterSession ?? this.broadcasterSession,
      viewerSession: clearViewerSession
          ? null
          : viewerSession ?? this.viewerSession,
      loading: loading ?? this.loading,
      entitlementLoading:
          entitlementLoading ?? this.entitlementLoading,
      entitlement: clearEntitlement
          ? null
          : entitlement ?? this.entitlement,
      plans: plans ?? this.plans,
      billingLoading: billingLoading ?? this.billingLoading,
      billingAvailable: billingAvailable ?? this.billingAvailable,
      billingProcessing: billingProcessing ?? this.billingProcessing,
      billingError: clearBillingError
          ? null
          : billingError ?? this.billingError,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class LiveNotifier extends StateNotifier<LiveState> {
  LiveNotifier(
    this._socketService,
    this._api,
  ) : super(const LiveState()) {
    _billing = GoLiveBillingService(api: _api);
    _billingEventSubscription =
        _billing.events.listen(_handleBillingEvent);
    _listenSocket();
    _socketStateSubscription = _socketService.connectionState.listen((socketState) {
      if (socketState == SocketState.connected) {
        _listenSocket();
      }
    });
  }

  final SocketService _socketService;
  final LiveApi _api;
  late final GoLiveBillingService _billing;
  StreamSubscription<GoLiveBillingEvent>? _billingEventSubscription;

  StreamSubscription<SocketState>? _socketStateSubscription;
  io.Socket? _listeningSocket;

  io.Socket? get _socket => _socketService.rawSocket;

  void _listenSocket() {
    final socket = _socket;
    if (socket == null || identical(socket, _listeningSocket)) {
      return;
    }

    _listeningSocket = socket;

    socket.on('live:started', (data) {
      final map = _asMap(data);
      if (map == null) return;

      final session = LiveSession.fromJson(map);

      _upsertActiveLive(session);
    });

    socket.on('live:ended', (data) {
      final map = _asMap(data);
      if (map == null) return;

      final sessionId = map['sessionId']?.toString();
      if (sessionId == null || sessionId.isEmpty) return;

      final endedBroadcaster =
          state.broadcasterSession?.sessionId == sessionId;

      state = state.copyWith(
        activeLives: state.activeLives
            .where((session) => session.sessionId != sessionId)
            .toList(),
        clearBroadcasterSession: endedBroadcaster,
        clearViewerSession:
            state.viewerSession?.sessionId == sessionId,
      );

      if (endedBroadcaster) {
        loadGoLiveEntitlement();
      }
    });

    socket.on('live:viewer-count', (data) {
      final map = _asMap(data);
      if (map == null) return;

      final sessionId = map['sessionId']?.toString();
      final viewerCount = _asInt(map['viewerCount']);

      if (sessionId == null || sessionId.isEmpty) return;

      _updateViewerCount(sessionId, viewerCount);
    });
  }

  String? goLivePriceFor(String productId) {
    return _billing.productFor(productId)?.price;
  }

  Future<void> initializeGoLiveBilling() async {
    if (state.billingLoading || state.billingAvailable) {
      return;
    }

    state = state.copyWith(
      billingLoading: true,
      clearBillingError: true,
    );

    try {
      await _billing.initialize();

      state = state.copyWith(
        billingLoading: false,
        billingAvailable: _billing.isAvailable,
      );
    } catch (e) {
      state = state.copyWith(
        billingLoading: false,
        billingAvailable: false,
        billingError: e.toString(),
      );
    }
  }

  Future<void> purchaseGoLivePlan(String productId) async {
    state = state.copyWith(
      clearBillingError: true,
      clearError: true,
    );

    try {
      await _billing.purchasePlan(productId);
    } catch (e) {
      state = state.copyWith(
        billingError: e.toString(),
      );
    }
  }

  void _handleBillingEvent(GoLiveBillingEvent event) {
    switch (event.type) {
      case GoLiveBillingEventType.pending:
        state = state.copyWith(
          billingProcessing: true,
          clearBillingError: true,
        );
        break;

      case GoLiveBillingEventType.verified:
        state = state.copyWith(
          billingProcessing: false,
          billingAvailable: true,
          clearBillingError: true,
          entitlement: event.entitlement,
        );
        loadGoLiveEntitlement();
        break;

      case GoLiveBillingEventType.error:
        state = state.copyWith(
          billingProcessing: false,
          billingError: event.message ?? 'Go Live purchase failed.',
        );
        break;
    }
  }

  Future<void> loadGoLiveEntitlement() async {
    state = state.copyWith(
      entitlementLoading: true,
      clearError: true,
    );

    try {
      final entitlement = await _api.getGoLiveEntitlement();

      state = state.copyWith(
        clearEntitlement: entitlement == null,
        entitlement: entitlement,
        entitlementLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        entitlementLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadGoLivePlans() async {
    try {
      final plans = await _api.getGoLivePlans();

      state = state.copyWith(
        plans: plans,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
      );
    }
  }

  Future<GoLiveEntitlement?> claimGoLiveTrial() async {
    try {
      final entitlement = await _api.claimGoLiveTrial();

      state = state.copyWith(
        entitlement: entitlement,
        clearError: true,
      );

      return entitlement;
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
      );
      return null;
    }
  }

  Future<void> loadGoLiveAccess() async {
    state = state.copyWith(
      entitlementLoading: true,
      clearError: true,
    );

    try {
      final results = await Future.wait([
        _api.getGoLiveEntitlement(),
        _api.getGoLivePlans(),
      ]);

      final entitlement = results[0] as GoLiveEntitlement?;
      final plans = results[1] as List<GoLivePlan>;

      state = state.copyWith(
        clearEntitlement: entitlement == null,
        entitlement: entitlement,
        plans: plans,
        entitlementLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        entitlementLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadActiveLives() async {
    state = state.copyWith(
      loading: true,
      clearError: true,
    );

    try {
      final sessions = await _api.getActiveLives();

      state = state.copyWith(
        activeLives: sessions,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );
    }
  }

  Future<LiveStartResult?> startLive({
    required String title,
    required String category,
  }) async {
    state = state.copyWith(
      loading: true,
      clearError: true,
    );

    try {
      final result = await _api.startLive(
        title: title,
        category: category,
      );

      state = state.copyWith(
        broadcasterSession: result.session,
        loading: false,
      );

      _upsertActiveLive(result.session);

      return result;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );

      return null;
    }
  }

  Future<bool> endLive() async {
    final session = state.broadcasterSession;

    if (session == null) {
      return true;
    }

    state = state.copyWith(
      loading: true,
      clearError: true,
    );

    try {
      await _api.endLive(session.sessionId);

      state = state.copyWith(
        loading: false,
        clearBroadcasterSession: true,
        activeLives: state.activeLives
            .where((item) => item.sessionId != session.sessionId)
            .toList(),
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );

      return false;
    }
  }

  Future<LiveSession?> joinLive(String sessionId) async {
    state = state.copyWith(
      loading: true,
      clearError: true,
    );

    try {
      final session = await _api.joinLive(sessionId);

      _socketService.emit('live:join', {
        'sessionId': sessionId,
      });

      state = state.copyWith(
        viewerSession: session,
        loading: false,
      );

      _updateViewerCount(
        session.sessionId,
        session.viewerCount,
      );

      return session;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );

      return null;
    }
  }

  Future<bool> leaveLive() async {
    final session = state.viewerSession;

    if (session == null) {
      return true;
    }

    state = state.copyWith(
      loading: true,
      clearError: true,
    );

    try {
      _socketService.emit('live:leave', {
        'sessionId': session.sessionId,
      });

      await _api.leaveLive(session.sessionId);

      state = state.copyWith(
        loading: false,
        clearViewerSession: true,
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );

      return false;
    }
  }

  void _upsertActiveLive(LiveSession session) {
    final lives = [...state.activeLives];

    final index = lives.indexWhere(
      (item) => item.sessionId == session.sessionId,
    );

    if (index >= 0) {
      lives[index] = session;
    } else {
      lives.insert(0, session);
    }

    state = state.copyWith(
      activeLives: lives,
    );
  }

  void _updateViewerCount(
    String sessionId,
    int viewerCount,
  ) {
    final lives = state.activeLives.map((session) {
      if (session.sessionId != sessionId) {
        return session;
      }

      return LiveSession(
        sessionId: session.sessionId,
        broadcasterXameId: session.broadcasterXameId,
        title: session.title,
        category: session.category,
        status: session.status,
        startedAt: session.startedAt,
        endedAt: session.endedAt,
        viewerCount: viewerCount,
        playbackUrl: session.playbackUrl,
        allowedMinutes: session.allowedMinutes,
        usageCutoffAt: session.usageCutoffAt,
      );
    }).toList();

    LiveSession? updateSession(LiveSession? session) {
      if (session == null || session.sessionId != sessionId) {
        return session;
      }

      return LiveSession(
        sessionId: session.sessionId,
        broadcasterXameId: session.broadcasterXameId,
        title: session.title,
        category: session.category,
        status: session.status,
        startedAt: session.startedAt,
        endedAt: session.endedAt,
        viewerCount: viewerCount,
        playbackUrl: session.playbackUrl,
        allowedMinutes: session.allowedMinutes,
        usageCutoffAt: session.usageCutoffAt,
      );
    }

    state = state.copyWith(
      activeLives: lives,
      broadcasterSession: updateSession(state.broadcasterSession),
      viewerSession: updateSession(state.viewerSession),
    );
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    return null;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  void dispose() {
    _socketStateSubscription?.cancel();
    _socketStateSubscription = null;

    final socket = _listeningSocket;

    if (socket != null) {
      socket.off('live:started');
      socket.off('live:ended');
      socket.off('live:viewer-count');
    }

    _listeningSocket = null;

  _billingEventSubscription?.cancel();
  _billingEventSubscription = null;
  _billing.dispose();

    super.dispose();
  }
}
