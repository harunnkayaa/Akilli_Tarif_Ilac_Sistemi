import 'package:flutter/material.dart';
import 'auth_api.dart';
import '../profile/profile_screen.dart';
import 'login_screen.dart';

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

  Future<void> _boot() async {
    final ok = await widget.authApi.hasValidSession();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ok
            ? const ProfileScreen()
            : LoginScreen(authApi: widget.authApi),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}
