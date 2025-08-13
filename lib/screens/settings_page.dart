//settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/esp32_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  ConnectionMode _mode = ConnectionMode.http;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final svc = context.read<Esp32Service>();
    _ipController.text = svc.ip;
    _portController.text = svc.port.toString();
    _mode = svc.mode;
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _testAndShowConnectionResult() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 80;
    
    final svc = context.read<Esp32Service>();
    svc.updateConfig(
      ipAddr: ip,
      portNum: port,
      newMode: _mode,
    );

    final ok = await svc.testConnection();
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Connected successfully' : 'Connection failed'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<Esp32Service>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(labelText: 'ESP32 IP'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Mode:'),
                const SizedBox(width: 12),
                DropdownButton<ConnectionMode>(
                  value: _mode,
                  items: const [
                    DropdownMenuItem(
                      value: ConnectionMode.http,
                      child: Text('HTTP'),
                    ),
                    DropdownMenuItem(
                      value: ConnectionMode.websocket, 
                      child: Text('WebSocket'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _mode = v ?? ConnectionMode.http),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _testAndShowConnectionResult,
              child: const Text('Save & Test Connection'),
            ),
            const SizedBox(height: 16),

// Bouton Déconnexion
            ElevatedButton(
              onPressed: () {
                final svc = context.read<Esp32Service>();
                svc.disconnect();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Déconnecté de l’ESP32'),
                    duration: Duration(seconds: 2),
                  ),
                );
                setState(() {}); // Rafraîchir l'affichage du statut
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Se déconnecter'),
            ),

            const SizedBox(height: 16),
            Text(
              'Status: ${svc.connected ? 'Connected' : 'Disconnected'}',
              style: TextStyle(
                color: svc.connected ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}