import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../data/live_api.dart';
import '../models/live_entitlement.dart';

enum GoLiveBillingEventType {
  pending,
  verified,
  error,
}

class GoLiveBillingEvent {
  const GoLiveBillingEvent({
    required this.type,
    this.productId,
    this.entitlement,
    this.message,
    this.code,
  });

  final GoLiveBillingEventType type;
  final String? productId;
  final GoLiveEntitlement? entitlement;
  final String? message;
  final String? code;
}

class GoLiveBillingException implements Exception {
  const GoLiveBillingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoLiveBillingService {
  GoLiveBillingService({
    required LiveApi api,
    InAppPurchase? store,
  })  : _api = api,
        _store = store ?? InAppPurchase.instance;

  static const Set<String> paidProductIds = <String>{
    'xamelive_weekly',
    'xamelive_monthly',
    'xamelive_2_months',
    'xamelive_3_months',
    'xamelive_6_months',
    'xamelive_annual',
  };

  final LiveApi _api;
  final InAppPurchase _store;

  final StreamController<GoLiveBillingEvent> _events =
      StreamController<GoLiveBillingEvent>.broadcast();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  Map<String, ProductDetails> _products = const <String, ProductDetails>{};
  bool _initialized = false;
  bool _available = false;
  bool _processingPurchase = false;

  bool get isInitialized => _initialized;
  bool get isAvailable => _available;
  bool get isProcessingPurchase => _processingPurchase;

  Stream<GoLiveBillingEvent> get events => _events.stream;

  List<ProductDetails> get products => List<ProductDetails>.unmodifiable(
        _products.values,
      );

  ProductDetails? productFor(String productId) => _products[productId];

  Future<void> initialize() async {
    if (_initialized) return;

    // XameLive Google Play billing is intentionally Android-only.
    // iOS billing can be added separately when an Apple product catalog
    // and verification path exist.
    if (defaultTargetPlatform != TargetPlatform.android) {
      _available = false;
      return;
    }

    if (_purchaseSubscription == null) {
      _purchaseSubscription = _store.purchaseStream.listen(
        _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        _emit(
          GoLiveBillingEvent(
            type: GoLiveBillingEventType.error,
            message: error.toString(),
          ),
        );
        },
      );
    }

    _available = await _store.isAvailable();

    if (!_available) {
      throw const GoLiveBillingException(
        'Google Play billing is unavailable on this device.',
      );
    }

    final response = await _store.queryProductDetails(paidProductIds);

    if (response.error != null) {
      throw GoLiveBillingException(
        response.error!.message,
      );
    }

    if (response.notFoundIDs.isNotEmpty) {
      throw GoLiveBillingException(
        'Google Play products not found: '
        '${response.notFoundIDs.join(', ')}',
      );
    }

    final products = <String, ProductDetails>{};

    for (final product in response.productDetails) {
      if (paidProductIds.contains(product.id)) {
        products[product.id] = product;
      }
    }

    if (products.length != paidProductIds.length) {
      final missing = paidProductIds.difference(products.keys.toSet());

      throw GoLiveBillingException(
        'Google Play Go Live products are incomplete. '
        'Missing: ${missing.join(', ')}',
      );
    }

    _products = products;
    _initialized = true;
  }

  Future<void> purchasePlan(String productId) async {
    if (_processingPurchase) {
      throw const GoLiveBillingException(
        'A Go Live purchase is already being processed.',
      );
    }

    if (!_initialized) {
      throw const GoLiveBillingException(
        'Go Live billing has not been initialized.',
      );
    }

    if (!_available) {
      throw const GoLiveBillingException(
        'Google Play billing is unavailable.',
      );
    }

    final product = _products[productId];

    if (product == null) {
      throw GoLiveBillingException(
        'Go Live product is unavailable: $productId',
      );
    }

    final purchaseParam = PurchaseParam(
      productDetails: product,
    );

    final launched = await _store.buyConsumable(
      purchaseParam: purchaseParam,
      autoConsume: false,
    );

    if (!launched) {
      throw const GoLiveBillingException(
        'Google Play could not start the purchase.',
      );
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      await _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(
    PurchaseDetails purchase,
  ) async {
    final productId = purchase.productID;

    if (purchase.status == PurchaseStatus.pending) {
      _emit(
        GoLiveBillingEvent(
          type: GoLiveBillingEventType.pending,
          productId: productId,
        ),
      );
      return;
    }

    if (purchase.status == PurchaseStatus.error) {
      final error = purchase.error;

      _emit(
        GoLiveBillingEvent(
          type: GoLiveBillingEventType.error,
          productId: productId,
          code: error?.code,
          message: error?.message ?? 'Google Play purchase failed.',
        ),
      );
      return;
    }

    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return;
    }

    final purchaseToken =
        purchase.verificationData.serverVerificationData.trim();

    if (purchaseToken.isEmpty) {
      _emit(
        GoLiveBillingEvent(
          type: GoLiveBillingEventType.error,
          productId: productId,
          code: 'GO_LIVE_PURCHASE_TOKEN_MISSING',
          message: 'Google Play did not provide a purchase token.',
        ),
      );
      return;
    }

    _processingPurchase = true;

    try {
      final entitlement = await _api.verifyGoLivePurchase(
        purchaseToken: purchaseToken,
      );

      // Only finalize the store transaction after XamePage has
      // successfully verified and granted the entitlement.
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }

      _emit(
        GoLiveBillingEvent(
          type: GoLiveBillingEventType.verified,
          productId: productId,
          entitlement: entitlement,
        ),
      );
    } catch (error) {
      // Deliberately do NOT complete an unverified purchase.
      // This allows Google Play to redeliver it so verification can
      // be retried after a temporary network/backend/consumption failure.
      _emit(
        GoLiveBillingEvent(
          type: GoLiveBillingEventType.error,
          productId: productId,
          message: error.toString(),
        ),
      );
    } finally {
      _processingPurchase = false;
    }
  }

  void _emit(GoLiveBillingEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;

    await _events.close();
  }
}
