import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../widgets/joystick.dart';
import '../services/esp32_service.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  bool ledOn = false;
  bool _isMoving = false;
  String _lastCommand = '';
  DateTime _lastCommandTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Tentative de connexion au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptConnection();
    });
  }

  Future<void> _attemptConnection() async {
    final svc = context.read<Esp32Service>();
    if (!svc.connected) {
      debugPrint('Attempting initial connection...');
      await svc.testConnection();
    }
  }

  void _onJoystick(double dx, double dy) {
    final svc = context.read<Esp32Service>();
    if (!svc.connected) return;

    String command = '';
    bool shouldMove = false;

    // Seuils pour éviter les commandes trop sensibles
    const threshold = 0.3;

    if (dy.abs() > dx.abs()) {
      // Mouvement vertical prioritaire
      if (dy > threshold) {
        command = 'forward';
        shouldMove = true;
      } else if (dy < -threshold) {
        command = 'backward';
        shouldMove = true;
      }
    } else {
      // Mouvement horizontal
      if (dx > threshold) {
        command = 'right';
        shouldMove = true;
      } else if (dx < -threshold) {
        command = 'left';
        shouldMove = true;
      }
    }

    // Éviter les commandes répétitives
    final now = DateTime.now();
    if (command != _lastCommand ||
        now.difference(_lastCommandTime).inMilliseconds > 100) {

      if (shouldMove && command.isNotEmpty) {
        _sendCommand(command);
        _setMovingState(true);
      } else if (!shouldMove) {
        _sendCommand('stop');
        _setMovingState(false);
      }

      _lastCommand = command;
      _lastCommandTime = now;
    }
  }

  void _setMovingState(bool moving) {
    if (_isMoving != moving) {
      setState(() => _isMoving = moving);
      if (moving) HapticFeedback.lightImpact();
    }
  }

  Future<void> _sendCommand(String command) async {
    final svc = context.read<Esp32Service>();
    if (!svc.connected) {
      debugPrint('Cannot send command: not connected');
      return;
    }

    debugPrint('Sending command: $command');

    try {
      switch (command) {
        case 'forward':
          await svc.forward();
          break;
        case 'backward':
          await svc.backward();
          break;
        case 'left':
          await svc.left();
          break;
        case 'right':
          await svc.right();
          break;
        case 'stop':
          await svc.stop();
          break;
        default:
          await svc.sendCommand(command);
      }
    } catch (e) {
      debugPrint('Error sending command: $e');
      // Ne pas changer l'état de connexion ici, laisser le service le gérer
    }
  }

  Future<void> _sendDirectionCommand(String direction) async {
    HapticFeedback.selectionClick();
    await _sendCommand(direction);
    _setMovingState(direction != 'stop');
  }

  Future<void> _reconnect() async {
    final svc = context.read<Esp32Service>();
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reconnecting...'),
        duration: Duration(seconds: 2),
      ),
    );

    await svc.testConnection();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<Esp32Service>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Robot Wi‑Fi Control'),
        actions: [
          if (!svc.connected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reconnect,
              tooltip: 'Reconnect',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Status row améliorée
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Icon(Icons.wifi,
                            color: svc.connected ? Colors.greenAccent : Colors.redAccent),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              svc.connected ? 'Connected' : 'Disconnected',
                              style: TextStyle(
                                color: svc.connected ? Colors.greenAccent : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${svc.ip}:${svc.port} (${svc.mode.toString().split('.').last.toUpperCase()})',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        if (!svc.connected) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        ]
                      ]),
                      Row(children: [
                        Icon(Icons.battery_full,
                            color: svc.battery > 20 ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text('${svc.battery.toStringAsFixed(0)}%'),
                      ])
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Zone de contrôle principale
              Expanded(
                child: Row(
                  children: [
                    // Joystick
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: svc.connected ? 1.0 : 0.5,
                          duration: const Duration(milliseconds: 300),
                          child: Joystick(
                            size: 260,
                            onChange: svc.connected
                                ? _onJoystick
                                : (dx, dy) {}, // Fonction vide si non connecté
                            onRelease: () {
                              _sendCommand('stop');
                              _setMovingState(false);
                            },
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Colonne droite : boutons et contrôles
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Bouton Stop principal
                          ElevatedButton(
                            onPressed: svc.connected
                                ? () => _sendDirectionCommand('stop')
                                : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(18),
                              shape: const CircleBorder(),
                              backgroundColor: _isMoving ? Colors.red : Colors.grey[700],
                              foregroundColor: Colors.white,
                            ),
                            child: Icon(
                              Icons.stop,
                              size: 28,
                              color: _isMoving ? Colors.white : Colors.grey[400],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Bouton LED
                          ElevatedButton.icon(
                            onPressed: svc.connected
                                ? () async {
                              await _sendCommand('led_toggle');
                              if (mounted) {
                                setState(() => ledOn = !ledOn);
                                HapticFeedback.selectionClick();
                              }
                            }
                                : null,
                            icon: Icon(
                              ledOn ? Icons.lightbulb : Icons.lightbulb_outline,
                              color: ledOn ? Colors.yellow : null,
                            ),
                            label: Text(ledOn ? 'LED ON' : 'LED OFF'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ledOn ? Colors.amber[800] : null,
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Bouton Buzzer
                          ElevatedButton.icon(
                            onPressed: svc.connected
                                ? () async {
                              await _sendCommand('buzzer');
                              HapticFeedback.selectionClick();
                            }
                                : null,
                            icon: const Icon(Icons.volume_up),
                            label: const Text('Buzzer'),
                          ),

                          const SizedBox(height: 20),

                          // Contrôle de vitesse
                          Text(
                            'Speed: ${(svc.speed * 100).toInt()}%',
                            style: Theme.of(context).textTheme.titleSmall,
                            textAlign: TextAlign.center,
                          ),

                          Slider(
                            value: svc.speed,
                            onChanged: svc.connected
                                ? (v) {
                              svc.setSpeed(v);
                              HapticFeedback.selectionClick();
                            }
                                : null,
                            divisions: 10,
                            label: '${(svc.speed * 100).toInt()}%',
                            activeColor: Theme.of(context).primaryColor,
                            inactiveColor: Colors.grey[600],
                          ),

                          const Spacer(),

                          // Boutons additionnels
                          ElevatedButton.icon(
                            onPressed: svc.connected
                                ? () async {
                              await _sendCommand('camera');
                              HapticFeedback.selectionClick();
                            }
                                : null,
                            icon: const Icon(Icons.videocam),
                            label: const Text('Camera'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[700],
                            ),
                          ),

                          const SizedBox(height: 8),

                          ElevatedButton.icon(
                            onPressed: svc.connected
                                ? () async {
                              await _sendCommand('reset');
                              HapticFeedback.selectionClick();
                              // Reset de l'état LED
                              setState(() => ledOn = false);
                            }
                                : null,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reset'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Contrôles directionnels rapides
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      Text(
                        'Quick Controls',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _DirectionButton(
                            connected: svc.connected,
                            icon: Icons.keyboard_arrow_up,
                            onPressed: () => _sendDirectionCommand('forward'),
                            active: _isMoving,
                            tooltip: 'Forward',
                          ),
                          _DirectionButton(
                            connected: svc.connected,
                            icon: Icons.keyboard_arrow_left,
                            onPressed: () => _sendDirectionCommand('left'),
                            active: _isMoving,
                            tooltip: 'Left',
                          ),
                          _DirectionButton(
                            connected: svc.connected,
                            icon: Icons.stop,
                            onPressed: () => _sendDirectionCommand('stop'),
                            active: false,
                            isStop: true,
                            tooltip: 'Stop',
                          ),
                          _DirectionButton(
                            connected: svc.connected,
                            icon: Icons.keyboard_arrow_right,
                            onPressed: () => _sendDirectionCommand('right'),
                            active: _isMoving,
                            tooltip: 'Right',
                          ),
                          _DirectionButton(
                            connected: svc.connected,
                            icon: Icons.keyboard_arrow_down,
                            onPressed: () => _sendDirectionCommand('backward'),
                            active: _isMoving,
                            tooltip: 'Backward',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Indicateur de mouvement
              if (_isMoving)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    // Correction de la méthode withOpacity() dépréciée
                    color: const Color(0x334CAF50), // Vert avec 20% d'opacité (0x33 = 20%)
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green),
                  ),
                  // Ajout de const pour tous les éléments du Row
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_run, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Robot Moving',
                        style: TextStyle(color: Colors.green, fontSize: 12),
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
}

class _DirectionButton extends StatelessWidget {
  final bool connected;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final bool isStop;
  final String tooltip;

  const _DirectionButton({
    required this.connected,
    required this.icon,
    required this.onPressed,
    required this.active,
    this.isStop = false,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: connected
                ? (isStop ? Colors.red : Theme.of(context).primaryColor)
                : Colors.grey,
            width: 2,
          ),
          color: active && !isStop
              ? Theme.of(context).primaryColor.withAlpha(30)
              : Colors.transparent,
        ),
        child: IconButton(
          iconSize: 24,
          onPressed: connected ? onPressed : null,
          icon: Icon(
            icon,
            color: connected
                ? (isStop ? Colors.red : Theme.of(context).primaryColor)
                : Colors.grey,
          ),
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}