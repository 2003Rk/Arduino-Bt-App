import 'dart:io';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'; // For InAppWebView
import 'package:permission_handler/permission_handler.dart'; // Permission handler for Android 12+

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arduino RC Car',
      color: Colors.white,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  BluetoothConnection? connection;
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _selectedDevice;
  bool isConnected = false;

  // Sensor data variables
  String airQualityValue = 'N/A';
  String temperatureValue = 'N/A';
  String humidityValue = 'N/A';

  InAppWebViewController? webViewController; // InAppWebView controller

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _requestBluetoothPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.bluetoothScan.request().isGranted &&
          await Permission.bluetoothConnect.request().isGranted &&
          await Permission.bluetoothAdvertise.request().isGranted) {
        // Permissions granted
      } else {
        // Permissions denied
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Bluetooth permissions are required to use this app.'),
          ),
        );
      }
    }
  }

  void _initBluetooth() async {
    await _requestBluetoothPermissions(); // Request permissions for Android 12+

    _bluetoothState = await FlutterBluetoothSerial.instance.state;
    if (_bluetoothState == BluetoothState.STATE_OFF) {
      _showBluetoothOffDialog();
    }

    FlutterBluetoothSerial.instance.state.listen((state) {
      setState(() {
        _bluetoothState = state;
        if (_bluetoothState == BluetoothState.STATE_OFF) {
          _showBluetoothOffDialog();
        }
      });
    });

    FlutterBluetoothSerial.instance.getBondedDevices().then((devices) {
      setState(() {
        _devicesList = devices;
      });
    });
  }

  void _showBluetoothOffDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Bluetooth is Turned Off'),
          content: Text('Please turn on Bluetooth to use this app.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _connectToDevice(BluetoothDevice device) async {
    if (connection != null) {
      await connection!.close();
    }

    try {
      connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        isConnected = true;
      });

      // Listen for data from Arduino
      connection!.input!.listen((Uint8List data) {
        String receivedData = String.fromCharCodes(data).trim();
        print('Received data: $receivedData'); // Debugging: print received data
        _parseSensorData(receivedData);
      }).onDone(() {
        setState(() {
          isConnected = false;
        });
        print('Disconnected from device');
      });

      print('Connected to ${device.name}');
    } catch (e) {
      setState(() {
        isConnected = false;
      });
      print('Failed to connect to ${device.name}: $e');
    }
  }

  void _parseSensorData(String receivedData) {
    setState(() {
      // Assuming data format "A:<airQuality>,T:<temperature>,H:<humidity>"
      List<String> sensorData = receivedData.split(',');

      for (var dataPart in sensorData) {
        if (dataPart.startsWith('A:')) {
          airQualityValue = dataPart.substring(2).trim();
        } else if (dataPart.startsWith('T:')) {
          temperatureValue = dataPart.substring(2).trim();
        } else if (dataPart.startsWith('H:')) {
          humidityValue = dataPart.substring(2).trim();
        }
      }
    });
  }

  void _sendCommand(String command) async {
    if (connection != null && isConnected) {
      Uint8List commandData = Uint8List.fromList(command.codeUnits);
      connection!.output.add(commandData);
      await connection!.output.allSent;
    }
  }

  void _scanDevices() async {
    setState(() {
      _devicesList.clear(); // Clear the list before scanning
    });

    // Start the device discovery and listen to the stream of discovered devices
    FlutterBluetoothSerial.instance.startDiscovery().listen((event) {
      if (event.device != null) {
        setState(() {
          _devicesList.add(event.device!);
        });
      }
    }).onDone(() {
      print('Device scan completed');
    });
  }

  @override
  void dispose() {
    connection?.dispose();
    connection = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Arduino RC Car',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black87,
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image:
                AssetImage("assets/images/img1.jpg"), // Gaming-style background
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (!isConnected) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 10,
                  shadowColor: Colors.blueAccent.withOpacity(0.5),
                ),
                onPressed: _scanDevices,
                child: Text(
                  'Scan for Devices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (_devicesList.isNotEmpty)
                Expanded(
                  child: ListView.builder(
                    itemCount: _devicesList.length,
                    itemBuilder: (context, index) {
                      BluetoothDevice device = _devicesList[index];
                      return ListTile(
                        title: Text(
                          device.name ?? 'Unknown device',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(device.address,
                            style: TextStyle(color: Colors.white54)),
                        onTap: () {
                          setState(() {
                            _selectedDevice = device;
                          });
                        },
                        trailing: _selectedDevice == device
                            ? Icon(Icons.check, color: Colors.green)
                            : null,
                      );
                    },
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 10,
                  shadowColor: Colors.blueAccent.withOpacity(0.5),
                ),
                onPressed: () {
                  if (_selectedDevice != null) {
                    _connectToDevice(_selectedDevice!);
                  }
                },
                child: Text(
                  'Connect to Selected Device',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            if (isConnected) ...[
              Center(
                child: Text(
                  'Connected to ${_selectedDevice?.name}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text('Air Quality: $airQualityValue',
                  style: TextStyle(color: Colors.white)),
              Text('Temperature: $temperatureValue',
                  style: TextStyle(color: Colors.white)),
              Text('Humidity: $humidityValue',
                  style: TextStyle(color: Colors.white)),
              SizedBox(height: 20),
              // WebView for camera feed
              Container(
                height: 300, // Set a height for the web view
                child: InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: Uri.parse('http://your_camera_feed_url')),
                  initialOptions: InAppWebViewGroupOptions(
                    crossPlatform: InAppWebViewOptions(),
                  ),
                  onWebViewCreated: (InAppWebViewController controller) {
                    webViewController = controller;
                  },
                ),
              ),
              SizedBox(height: 20),
              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _customIconButton(Icons.arrow_upward, 'F', 'S'), // Forward
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _customIconButton(Icons.arrow_back, 'L', 'S'), // Left
                  _customIconButton(Icons.stop, 'S', 'S'), // Stop
                  _customIconButton(Icons.arrow_forward, 'R', 'S'), // Right
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _customIconButton(Icons.arrow_downward, 'B', 'S'), // Backward
                ],
              ),
              SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _customIconButton(
      IconData icon, String commandDown, String commandUp) {
    return GestureDetector(
      onTapDown: (_) => _sendCommand(commandDown),
      onTapUp: (_) => _sendCommand(commandUp),
      child: Container(
        padding: EdgeInsets.all(20), // Increased padding for a bigger button
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.purpleAccent, Colors.blueAccent], // Bright gradient
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blueAccent.withOpacity(0.7),
              blurRadius: 15,
              spreadRadius: 3,
              offset: Offset(0, 5), // Adds depth with an offset shadow
            ),
          ],
          border: Border.all(
            color: Colors.white.withOpacity(0.8), // White border for contrast
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.white), // Direction arrow
            SizedBox(height: 5),
            Text(
              _getDirectionLabel(commandDown), // Adding direction text
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  String _getDirectionLabel(String command) {
    switch (command) {
      case 'F':
        return 'Forward';
      case 'B':
        return 'Backward';
      case 'L':
        return 'Left';
      case 'R':
        return 'Right';
      default:
        return '';
    }
  }
}

extension on Future<BluetoothState> {
  void listen(Null Function(dynamic state) param0) {}
}
