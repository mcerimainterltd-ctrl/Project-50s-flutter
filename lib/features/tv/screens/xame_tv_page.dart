// lib/features/tv/screens/xame_tv_page.dart
// Entry point — router points here, delegates to XameTvScreen
import 'package:flutter/material.dart';
import 'xame_tv_screen.dart';

class XameTVPage extends StatelessWidget {
  const XameTVPage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => const XameTvScreen();
}
