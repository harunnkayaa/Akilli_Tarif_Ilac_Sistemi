import 'package:flutter/material.dart';
import 'auth_api.dart';

class BootScreen extends StatefulWidget {
  final AuthApi authApi;
  const BootScreen({super.key, required this.authApi});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }
  /*
  Future<void> _boot() async {
    final ok = await widget.authApi.hasValidSession();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, ok ? '/main' : '/login');
  }*/
  Future<void> _boot() async {
  bool ok = false;

  try {
    ok = await widget.authApi
        .hasValidSession()
        .timeout(const Duration(seconds: 6), onTimeout: () => false);
  } catch (_) {
    ok = false;
  }

  if (!mounted) return;
  Navigator.pushReplacementNamed(context, ok ? '/main' : '/login');
}

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator()),
      ),
    );
  }
}
