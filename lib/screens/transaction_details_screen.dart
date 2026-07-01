import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _kTeal  = Color(0xFF00B0A0);
const _kBg    = Color(0xFF0D1520);
const _kCard  = Color(0xFF111E2E);
const _kMuted = Color(0xFF7A9BB5);

/// Shown immediately after a successful bank transfer — mirrors the
/// OPay-style transaction details layout: status timeline, recipient info,
/// transaction metadata, and Report Issue / Share Receipt actions.
class TransactionDetailsScreen extends StatelessWidget {
  final double amount;
  final double fee;
  final double totalDebit;
  final int? cashbackCoins;
  final String senderName;
  final String recipientName;
  final String bankName;
  final String accountNumber;
  final String txRef;
  final String sessionId;
  final String paymentMethod;
  final DateTime ts;
  final String Function(double) fmt;
  /// Full, ready-to-display sentence describing the transaction, e.g.
  /// "Transfer to GIBSON AGBOR" or "Received from Covenant Agbor".
  /// This is the single source of truth for the title and receipt
  /// description — never reconstructed from recipientName + a template.
  final String description;

  const TransactionDetailsScreen({
    super.key,
    required this.amount,
    required this.fee,
    required this.totalDebit,
    this.cashbackCoins,
    required this.senderName,
    required this.recipientName,
    required this.bankName,
    required this.accountNumber,
    required this.description,
    required this.txRef,
    required this.sessionId,
    required this.paymentMethod,
    required this.ts,
    required this.fmt,
  });

  String _fmtTs(DateTime t) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '${months[t.month - 1]} ${t.day}, ${t.year} • $h:$m:$s';
  }

  String _fmtCompact(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '${t.month}-$dd $h:$m:$s'.replaceFirst('${t.month}', mm);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Transaction Details',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── Status card ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(color: Color(0x1A00B0A0), shape: BoxShape.circle),
                child: const Icon(Icons.account_balance_rounded, color: _kTeal, size: 24),
              ),
              const SizedBox(height: 14),
              Text(description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(fmt(amount),
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Successful',
                  style: TextStyle(color: _kTeal, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              // Status timeline
              Row(children: [
                _StatusDot(label: 'Payment\nsuccessful', time: _fmtCompact(ts), active: true),
                Expanded(child: Container(height: 2, color: _kTeal)),
                _StatusDot(label: 'Processing\nby bank', time: _fmtCompact(ts), active: true),
                Expanded(child: Container(height: 2, color: _kTeal)),
                _StatusDot(label: 'Received\nby bank', time: _fmtCompact(ts.add(const Duration(seconds: 30))), active: true),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                child: const Text(
                  'The recipient account is expected to be credited within 5 minutes, subject to notification by the bank.',
                  style: TextStyle(color: _kMuted, fontSize: 11, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Transaction details card ────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Transaction Details',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              if (senderName.isNotEmpty) _detailRow('Sender', senderName),
              if (recipientName.isNotEmpty || bankName.isNotEmpty || accountNumber.isNotEmpty)
                _detailRow('Recipient Details', [
                  if (recipientName.isNotEmpty) recipientName,
                  if (bankName.isNotEmpty && accountNumber.isNotEmpty) '$bankName | $accountNumber'
                  else if (bankName.isNotEmpty) bankName
                  else if (accountNumber.isNotEmpty) accountNumber,
                ].join('\n')),
              _detailRow('Transaction No.', txRef, copyable: true, context: context),
              _detailRow('Payment Method', paymentMethod),
              _detailRow('Transaction Date', _fmtTs(ts)),
              _detailRow('Session ID', sessionId, copyable: true, context: context),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Report issue + share receipt ────────────────────────────
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _reportIssue(context),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kTeal),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Report Issue', style: TextStyle(color: _kTeal, fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () => _shareReceipt(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Share Receipt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            )),
          ]),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool copyable = false, BuildContext? context}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: _kMuted, fontSize: 12))),
        Expanded(child: Text(value, textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
        if (copyable && context != null)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)));
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.copy_rounded, color: _kMuted, size: 14),
            ),
          ),
      ]),
    );
  }

  void _reportIssue(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Report an Issue', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Describe the issue with this transaction. Our support team will review it.',
              style: TextStyle(color: _kMuted, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'e.g. Recipient has not received funds...',
              hintStyle: const TextStyle(color: _kMuted),
              filled: true,
              fillColor: _kBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Issue reported. We\'ll get back to you shortly.')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: _kTeal, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Submit Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }

  // The receipt widget — intended transfer amount only, no fee breakdown
  Widget _buildReceiptWidget() {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('XamePay', style: TextStyle(color: _kTeal, fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            const Text('Transaction Receipt', style: TextStyle(color: Color(0xFF888888), fontSize: 11)),
          ]),
          const SizedBox(height: 16),
          Center(child: Text(fmt(amount),
              style: const TextStyle(color: Color(0xFFFF6464), fontSize: 36, fontWeight: FontWeight.w800))),
          const Center(child: Text('Completed', style: TextStyle(color: _kTeal, fontSize: 14))),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE0E0E0)),
          const SizedBox(height: 8),
          _receiptRow('Description', description),
          if (senderName.isNotEmpty) _receiptRow('Sender', senderName),
          if (recipientName.isNotEmpty) _receiptRow(
            'Recipient',
            [recipientName, if (bankName.isNotEmpty) bankName, if (accountNumber.isNotEmpty) accountNumber].join(' · '),
          ),
          _receiptRow('Date & Time', _fmtTs(ts)),
          _receiptRow('Reference', txRef),
          _receiptRow('Status', 'Completed'),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE0E0E0)),
          const SizedBox(height: 8),
          const Center(child: Text('Powered by XamePage', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 10))),
        ]),
      ),
    );
  }

  // Opens the pre-receipt preview, with explicit Image / PDF share choices
  void _shareReceipt(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ReceiptPreviewScreen(
      receiptBuilder: _buildReceiptWidget,
      txRef: txRef,
    )));
  }

  Widget _receiptRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Color(0xFF888888), fontSize: 11)),
      Flexible(child: Text(value, textAlign: TextAlign.right,
          style: const TextStyle(color: Color(0xFF222222), fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );
}

class _StatusDot extends StatelessWidget {
  final String label;
  final String time;
  final bool active;
  const _StatusDot({required this.label, required this.time, required this.active});

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      width: 22, height: 22,
      decoration: BoxDecoration(color: active ? _kTeal : Colors.white24, shape: BoxShape.circle),
      child: Icon(Icons.check, color: Colors.white, size: 13),
    ),
    const SizedBox(height: 6),
    Text(label, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
    const SizedBox(height: 2),
    Text(time, style: const TextStyle(color: _kMuted, fontSize: 9)),
  ]);
}

/// Pre-receipt preview shown before sharing — lets the user choose
/// whether to share as an Image or as a PDF, matching the OPay-style flow.
class _ReceiptPreviewScreen extends StatefulWidget {
  final Widget Function() receiptBuilder;
  final String txRef;
  const _ReceiptPreviewScreen({required this.receiptBuilder, required this.txRef});

  @override
  State<_ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<_ReceiptPreviewScreen> {
  final _ctrl = ScreenshotController();
  bool _busy = false;

  Future<Uint8List?> _capture() async {
    return await _ctrl.captureFromWidget(widget.receiptBuilder(), context: context);
  }

  Future<void> _shareAsImage() async {
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/xamepay_receipt_${widget.txRef}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: 'XamePay Transaction Receipt', subject: 'XamePay Transaction Receipt');
    } catch (_) {} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareAsPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (bytes == null) return;
      final pdfDoc = pw.Document();
      final pwImage = pw.MemoryImage(bytes);
      pdfDoc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Center(child: pw.Image(pwImage, width: 380)),
      ));
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/xamepay_receipt_${widget.txRef}.pdf');
      await file.writeAsBytes(await pdfDoc.save());
      await Share.shareXFiles([XFile(file.path)],
          text: 'XamePay Transaction Receipt', subject: 'XamePay Transaction Receipt');
    } catch (_) {} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Share Receipt',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Screenshot(controller: _ctrl, child: widget.receiptBuilder()),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _busy ? null : _shareAsImage,
                icon: const Icon(Icons.image_outlined, color: _kTeal, size: 18),
                label: const Text('Share as Image', style: TextStyle(color: _kTeal, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _kTeal),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton.icon(
                onPressed: _busy ? null : _shareAsPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white, size: 18),
                label: const Text('Share as PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              )),
            ]),
          ),
        ),
      ]),
    );
  }
}
