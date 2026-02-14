import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';

class ProfileScreen extends StatefulWidget {
  final ApiClient client;

  const ProfileScreen({super.key, required this.client});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  String? _email;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.client.dio.get('/users/me');
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _email = (data['email'] ?? '').toString();
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?.toString() ?? e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Error', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadMe,
                child: const Text('Retry'),
              ),
            ],
          )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: cs.primary,
                      child: Text(
                        (_email?.isNotEmpty ?? false) ? _email![0].toUpperCase() : '?',
                        style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Signed in as', style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 2),
                          Text(_email ?? '-', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Next: user_profile endpoints (GET/PUT /profile).',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
