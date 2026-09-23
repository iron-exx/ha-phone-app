import 'package:flutter/material.dart';

import '../services/sip_channel.dart';

/// Replaces the old native SettingsActivity. Same EncryptedSharedPreferences
/// keys underneath (host/port/username/password), just read/written via
/// SipChannel instead of Compose -- see SipChannelHandler.kt.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final creds = await SipChannel.instance.getCredentials();
    _host.text = creds['host'] ?? '';
    _port.text = creds['port'] ?? '';
    _username.text = creds['username'] ?? '';
    _password.text = creds['password'] ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if ([_host, _port, _username, _password].any((c) => c.text.trim().isEmpty)) {
      setState(() => _error = 'Alle Felder ausfüllen!');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await SipChannel.instance.saveCredentials(
      host: _host.text.trim(),
      port: _port.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    await SipChannel.instance.clearCredentials();
    _host.clear();
    _port.clear();
    _username.clear();
    _password.clear();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Tragen Sie hier Ihre HA-Phone-Box-Zugangsdaten ein.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _host,
                  decoration: const InputDecoration(labelText: 'SIP-Server (Host)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _port,
                  decoration: const InputDecoration(labelText: 'SIP-Port (meist 5061 für TLS)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Benutzername (Nebenstellennummer)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'SIP-Passwort'),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Speichern...' : 'Speichern'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 32),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Zurücksetzen', style: Theme.of(context).textTheme.titleMedium),
                        const Text('Alle SIP-Daten löschen.'),
                        const SizedBox(height: 8),
                        FilledButton(onPressed: _clear, child: const Text('Alles löschen')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
