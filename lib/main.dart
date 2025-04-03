import 'dart:io';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
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
        print('Received data: $receivedData');
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
      _devicesList.clear();
    });

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
        elevation: 10,
        shadowColor: Colors.blueAccent.withOpacity(0.5),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black87,
              Colors.blueGrey.shade900,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (!isConnected) ...[
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 8,
                      shadowColor: Colors.blueAccent.withOpacity(0.5),
                    ),
                    onPressed: _scanDevices,
                    child: Text(
                      'SCAN DEVICES',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                if (_devicesList.isNotEmpty)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.blueAccent.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: ListView.builder(
                          itemCount: _devicesList.length,
                          itemBuilder: (context, index) {
                            BluetoothDevice device = _devicesList[index];
                            return Container(
                              margin: EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 8),
                              decoration: BoxDecoration(
                                color: _selectedDevice == device
                                    ? Colors.blueAccent.withOpacity(0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedDevice == device
                                      ? Colors.blueAccent
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  Icons.bluetooth,
                                  color: Colors.blueAccent,
                                ),
                                title: Text(
                                  device.name ?? 'Unknown device',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  device.address,
                                  style: TextStyle(color: Colors.white70),
                                ),
                                trailing: _selectedDevice == device
                                    ? Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.check,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedDevice = device;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      backgroundColor: _selectedDevice != null
                          ? Colors.blueAccent
                          : Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 8,
                      shadowColor: Colors.blueAccent.withOpacity(0.5),
                    ),
                    onPressed: () {
                      if (_selectedDevice != null) {
                        _connectToDevice(_selectedDevice!);
                      }
                    },
                    child: Text(
                      'CONNECT TO DEVICE',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
              if (isConnected) ...[
                Container(
                  padding: EdgeInsets.all(16),
                  margin: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.blueAccent.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Connected to ${_selectedDevice?.name}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 16),
                      _buildSensorCard(
                          'Air Quality', airQualityValue, Icons.air),
                      _buildSensorCard(
                          'Temperature', temperatureValue, Icons.thermostat),
                      _buildSensorCard(
                          'Humidity', humidityValue, Icons.water_drop),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _customIconButton(Icons.arrow_upward, 'F', 'S'), // Forward
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _customIconButton(Icons.arrow_back, 'L', 'S'), // Left
                    SizedBox(width: 20),
                    _customIconButton(Icons.stop, 'S', 'S'), // Stop
                    SizedBox(width: 20),
                    _customIconButton(Icons.arrow_forward, 'R', 'S'), // Right
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _customIconButton(
                        Icons.arrow_downward, 'B', 'S'), // Backward
                  ],
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 8,
                  ),
                  onPressed: () {
                    if (connection != null) {
                      connection!.close();
                      setState(() {
                        isConnected = false;
                        _selectedDevice = null;
                      });
                    }
                  },
                  child: Text(
                    'DISCONNECT',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorCard(String title, String value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blueAccent.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 28),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _customIconButton(
      IconData icon, String commandDown, String commandUp) {
    return GestureDetector(
      onTapDown: (_) => _sendCommand(commandDown),
      onTapUp: (_) => _sendCommand(commandUp),
      child: Container(
        margin: EdgeInsets.all(8),
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.blueAccent.shade400, Colors.blueAccent.shade700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blueAccent.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 36,
          color: Colors.white,
        ),
      ),
    );
  }
}

extension on Future<BluetoothState> {
  void listen(Null Function(dynamic state) param0) {}
}
