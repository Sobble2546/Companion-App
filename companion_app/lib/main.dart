import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CompanionApp());
}

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nano Companion',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const CompanionHomePage(),
    );
  }
}

class CompanionHomePage extends StatefulWidget {
  const CompanionHomePage({super.key});

  @override
  State<CompanionHomePage> createState() => _CompanionHomePageState();
}

class _CompanionHomePageState extends State<CompanionHomePage> {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  final List<BluetoothDevice> _devices = <BluetoothDevice>[];
  final List<String> _logs = <String>[];
  final StringBuffer _incomingBuffer = StringBuffer();
  final Map<Permission, PermissionStatus> _permissionStatuses = <Permission, PermissionStatus>{};
  final List<String> _breakTriggers = <String>['BREAK_TIME', 'START_BREAK', 'LOOK_AWAY'];

  StreamSubscription<BluetoothDiscoveryResult>? _discoverySubscription;
  StreamSubscription<BluetoothState>? _stateSubscription;
  BluetoothConnection? _connection;
  BluetoothDevice? _selectedDevice;
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;

  bool _isScanning = false;
  bool _isConnecting = false;
  bool _overlayVisible = false;
  String _overlayMessage = 'Look Away For 20 Seconds';
  bool _hasOverlayPrivilege = false;
  bool _ignoresBatteryOptimizations = false;

  @override
  void initState() {
    super.initState();
    _bootstrapBluetooth();
  }

  Future<void> _bootstrapBluetooth() async {
    final BluetoothState state = await _bluetooth.state;
    if (!mounted) return;

    setState(() => _bluetoothState = state);

    _stateSubscription = _bluetooth.onStateChanged().listen((BluetoothState updated) {
      if (!mounted) {
        return;
      }
      setState(() => _bluetoothState = updated);
      if (updated == BluetoothState.STATE_OFF) {
        _appendLog('Bluetooth turned off');
        unawaited(_disconnect());
      }
    });

    unawaited(_refreshBondedDevices());
  }

  Future<void> _refreshBondedDevices() async {
    try {
      final List<BluetoothDevice> bonded = await _bluetooth.getBondedDevices();
      if (!mounted) {
        return;
      }
      setState(() {
        for (final BluetoothDevice device in bonded) {
          _upsertDevice(device);
        }
      });
    } catch (error) {
      _appendLog('Bonded device lookup failed: $error');
    }
  }

  void _appendLog(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.insert(0, '${DateTime.now().toIso8601String()}  $message');
      if (_logs.length > 200) {
        _logs.removeLast();
      }
    });
  }

  Future<void> _requestPermissions() async {
    final Map<Permission, PermissionStatus> results = await <Permission>[
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
      Permission.systemAlertWindow,
      Permission.ignoreBatteryOptimizations,
    ].request();

    if (!mounted) return;

    setState(() {
      _permissionStatuses
        ..clear()
        ..addAll(results);
      _hasOverlayPrivilege = results[Permission.systemAlertWindow]?.isGranted == true;
      _ignoresBatteryOptimizations = results[Permission.ignoreBatteryOptimizations]?.isGranted == true;
    });

    if (results.values.every((PermissionStatus status) => status.isGranted)) {
      _appendLog('All requested permissions granted');
      await _ensureBluetoothEnabled();
    } else {
      _appendLog('Bluetooth/location permissions missing');
    }
  }

  Future<void> _ensureBluetoothEnabled() async {
    final BluetoothState current = await _bluetooth.state;
    if (current == BluetoothState.STATE_ON) {
      return;
    }
    final bool? enabled = await _bluetooth.requestEnable();
    if (enabled == true) {
      _appendLog('Bluetooth enabled');
      await _refreshBondedDevices();
    } else {
      _appendLog('Bluetooth enable request denied');
    }
  }

  Future<void> _toggleScan() async {
    if (_isScanning) {
      await _discoverySubscription?.cancel();
      if (mounted) {
        setState(() => _isScanning = false);
      }
      return;
    }

    await _ensureBluetoothEnabled();

    setState(() {
      _isScanning = true;
    });

    _discoverySubscription = _bluetooth.startDiscovery().listen(
      (BluetoothDiscoveryResult result) {
        if (!mounted) {
          return;
        }
        setState(() {
          _upsertDevice(result.device);
        });
      },
      onError: (Object error) {
        _appendLog('Discovery failed: $error');
      },
      onDone: () {
        if (mounted) {
          setState(() => _isScanning = false);
        }
      },
    );
  }

  void _upsertDevice(BluetoothDevice device) {
    final int index = _devices.indexWhere((BluetoothDevice d) => d.address == device.address);
    if (index >= 0) {
      _devices[index] = device;
    } else {
      _devices.add(device);
    }
    _devices.sort((BluetoothDevice a, BluetoothDevice b) {
      final String left = (a.name ?? a.address).toLowerCase();
      final String right = (b.name ?? b.address).toLowerCase();
      return left.compareTo(right);
    });
  }

  Future<void> _connectOrDisconnect() async {
    if (_connection?.isConnected == true) {
      await _disconnect();
      return;
    }

    final BluetoothDevice? target = _selectedDevice;
    if (target == null) {
      _appendLog('Select an HC-05 device first');
      return;
    }

    setState(() => _isConnecting = true);

    try {
      await _ensureBluetoothEnabled();
      final BluetoothConnection connection = await BluetoothConnection.toAddress(target.address);
      connection.input?.listen(
        _onDataReceived,
        onDone: () {
          if (!mounted) return;
          _appendLog('Connection closed by remote device');
          setState(() => _connection = null);
        },
        onError: (Object error) {
          _appendLog('Connection stream error: $error');
        },
      );

      if (!mounted) return;
      setState(() {
        _connection = connection;
        _isConnecting = false;
      });
      _appendLog('Connected to ${target.name ?? target.address}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isConnecting = false);
      _appendLog('Connection failed: $error');
    }
  }

  Future<void> _disconnect() async {
    final BluetoothConnection? connection = _connection;
    if (connection != null) {
      await connection.close();
      connection.dispose();
    }
    if (!mounted) return;
    setState(() => _connection = null);
    _appendLog('Disconnected');
  }

  void _onDataReceived(Uint8List data) {
    final String chunk = const Utf8Decoder(allowMalformed: true).convert(data);
    _incomingBuffer.write(chunk);
    String pending = _incomingBuffer.toString();

    int newlineIndex = pending.indexOf('\n');
    while (newlineIndex != -1) {
      final String message = pending.substring(0, newlineIndex).trim();
      if (message.isNotEmpty) {
        _handleIncomingMessage(message);
      }
      pending = pending.substring(newlineIndex + 1);
      newlineIndex = pending.indexOf('\n');
    }

    _incomingBuffer
      ..clear()
      ..write(pending);
  }

  Future<void> _handleIncomingMessage(String message) async {
    _appendLog('RX: $message');
    final String normalized = message.toUpperCase();
    final bool shouldAlert = _breakTriggers.any(normalized.contains);
    if (shouldAlert) {
      await _showOverlay(message);
    }
  }

  Future<void> _showOverlay(String message) async {
    if (!mounted) return;

    if (!_hasOverlayPrivilege) {
      _appendLog('Overlay permission missing; tap Allow Draw-Over & Background');
      return;
    }

    setState(() {
      _overlayMessage = message.isEmpty ? 'Look Away For 20 Seconds' : message;
      _overlayVisible = true;
    });

    unawaited(_buzzAlert());
  }

  Future<void> _buzzAlert() async {
    try {
      for (int i = 0; i < 3; i++) {
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } catch (_) {
      // Ignore if haptics are unavailable on the device.
    }
  }

  Widget _buildStatusCard() {
    final bool connected = _connection?.isConnected == true;
    final String subtitle = connected
        ? 'Connected to ${_selectedDevice?.name ?? _selectedDevice?.address ?? 'device'}'
        : 'Select and connect to your HC-05 module';

    return Card(
      child: ListTile(
        leading: Icon(
          connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
          color: connected ? Colors.green : Colors.redAccent,
          size: 32,
        ),
        title: Text(
          connected ? 'Connected' : 'Disconnected',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(subtitle),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Adapter: ${_stateLabel(_bluetoothState)}'),
            if (_isConnecting)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _requestPermissions,
                icon: const Icon(Icons.security),
                label: const Text('Request Permissions'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _toggleScan,
                icon: Icon(_isScanning ? Icons.stop_circle_outlined : Icons.search),
                label: Text(_isScanning ? 'Stop Scan' : 'Scan For Devices'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _ensureOverlayAndBackground,
            icon: const Icon(Icons.mobile_off),
            label: const Text('Allow Draw-Over & Background'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            _hasOverlayPrivilege && _ignoresBatteryOptimizations
                ? 'Overlay + background privileges active'
                : 'Grant overlay/background access so alerts can appear above other apps.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isConnecting ? null : _connectOrDisconnect,
            icon: Icon(_connection?.isConnected == true ? Icons.link_off : Icons.link),
            label: Text(_connection?.isConnected == true ? 'Disconnect' : 'Connect'),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _permissionStatuses.isEmpty
                ? <Widget>[const Text('Permissions: not requested yet')]
                : _permissionStatuses.entries
                    .map(
                      (MapEntry<Permission, PermissionStatus> entry) => Chip(
                        avatar: Icon(
                          entry.value.isGranted ? Icons.check_circle : Icons.error_outline,
                          size: 16,
                          color: entry.value.isGranted ? Colors.green : Colors.orange,
                        ),
                        label: Text('${_permissionLabel(entry.key)}: ${entry.value.name}'),
                      ),
                    )
                    .toList(),
          ),
        ),
      ],
    );
  }

  String _permissionLabel(Permission permission) {
    final List<String> tokens = permission.toString().split('.');
    return tokens.isNotEmpty ? tokens.last : permission.toString();
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return const Center(
        child: Text('No Bluetooth devices discovered yet.\nTap "Scan For Devices" after pairing the HC-05.'),
      );
    }

    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (BuildContext context, int index) {
        final BluetoothDevice device = _devices[index];
        final bool bonded = device.bondState == BluetoothBondState.bonded;
        final bool selected = _selectedDevice?.address == device.address;
        return Card(
          child: ListTile(
            onTap: () => setState(() => _selectedDevice = device),
            leading: Icon(
              bonded ? Icons.lock : Icons.bluetooth,
              color: bonded ? Colors.indigo : null,
            ),
            title: Text(device.name ?? 'Unknown'),
            subtitle: Text(device.address),
            trailing: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: _logs.isEmpty
          ? const Center(child: Text('Logs will appear here once data is received.'))
          : ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (BuildContext context, int index) {
                return Text(
                  _logs[index],
                  style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
                );
              },
            ),
    );
  }

  Widget _buildOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _overlayVisible = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.85),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.visibility_off, color: Colors.white, size: 96),
              const SizedBox(height: 24),
              Text(
                _overlayMessage.isEmpty ? 'Look Away For 20 Seconds' : _overlayMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Focus on something 20ft away to rest your eyes.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                onPressed: () => setState(() => _overlayVisible = false),
                child: const Text('I LOOKED AWAY'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nano Companion'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh bonded devices',
            onPressed: _refreshBondedDevices,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildStatusCard(),
                const SizedBox(height: 12),
                _buildActionButtons(),
                const SizedBox(height: 12),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _buildDeviceList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _buildLogs(),
                ),
              ],
            ),
          ),
          if (_overlayVisible) _buildOverlay(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    _stateSubscription?.cancel();
    _connection?.dispose();
    super.dispose();
  }

  String _stateLabel(BluetoothState state) {
    final String value = state.toString();
    final int index = value.lastIndexOf('.');
    return index == -1 ? value : value.substring(index + 1);
  }

  Future<void> _ensureOverlayAndBackground() async {
    final PermissionStatus overlayStatus = await Permission.systemAlertWindow.status;
    final PermissionStatus batteryStatus = await Permission.ignoreBatteryOptimizations.status;

    PermissionStatus finalOverlay = overlayStatus;
    PermissionStatus finalBattery = batteryStatus;

    if (!overlayStatus.isGranted) {
      finalOverlay = await Permission.systemAlertWindow.request();
      if (!finalOverlay.isGranted) {
        await openAppSettings();
      }
    }

    if (!batteryStatus.isGranted) {
      finalBattery = await Permission.ignoreBatteryOptimizations.request();
      if (!finalBattery.isGranted) {
        await openAppSettings();
      }
    }

    if (!mounted) return;

    setState(() {
      _permissionStatuses[Permission.systemAlertWindow] = finalOverlay;
      _permissionStatuses[Permission.ignoreBatteryOptimizations] = finalBattery;
      _hasOverlayPrivilege = finalOverlay.isGranted;
      _ignoresBatteryOptimizations = finalBattery.isGranted;
    });

    _appendLog(
      'Overlay: ${finalOverlay.name}, Background: ${finalBattery.name}',
    );
  }
}
