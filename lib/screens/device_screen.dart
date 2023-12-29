import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:cryptography/cryptography.dart';

import '../widgets/service_tile.dart';
import '../widgets/characteristic_tile.dart';
import '../widgets/descriptor_tile.dart';
import '../utils/snackbar.dart';
import '../utils/extra.dart';
import '../utils/devices.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  int? _rssi;
  int? _mtuSize;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  List<BluetoothService> _services = [];
  bool _isDiscoveringServices = false;
  bool _isConnecting = false;
  bool _isDisconnecting = false;

  late StreamSubscription<BluetoothConnectionState>
      _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;
  late StreamSubscription<int> _mtuSubscription;

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription =
        widget.device.connectionState.listen((state) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        _services = []; // must rediscover services
      }
      if (state == BluetoothConnectionState.connected && _rssi == null) {
        _rssi = await widget.device.readRssi();
      }
      if (mounted) {
        setState(() {});
      }
    });

    _mtuSubscription = widget.device.mtu.listen((value) {
      _mtuSize = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isConnectingSubscription = widget.device.isConnecting.listen((value) {
      _isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isDisconnectingSubscription =
        widget.device.isDisconnecting.listen((value) {
      _isDisconnecting = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _mtuSubscription.cancel();
    _isConnectingSubscription.cancel();
    _isDisconnectingSubscription.cancel();
    super.dispose();
  }

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
  }

  Future onConnectPressed() async {
    try {
      await widget.device.connectAndUpdateStream();
      Snackbar.show(ABC.c, "Connect: Success", success: true);
    } catch (e) {
      if (e is FlutterBluePlusException &&
          e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e),
            success: false);
      }
    }
  }

  Future onCancelPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream(queue: false);
      Snackbar.show(ABC.c, "Cancel: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Cancel Error:", e), success: false);
    }
  }

  Future onDisconnectPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Disconnect Error:", e),
          success: false);
    }
  }

  Future onDiscoverServicesPressed() async {
    if (mounted) {
      setState(() {
        _isDiscoveringServices = true;
      });
    }
    try {
      _services = await widget.device.discoverServices();
      Snackbar.show(ABC.c, "Discover Services: Success", success: true);
      var response;
      var command;
      for (BluetoothService s in _services) {
        for (BluetoothCharacteristic c in s.characteristics) {
          if (c.uuid.toString() == "9d410018-35d6-f4dd-ba60-e7bd8dc491c0") {
            command = c;
          } else if (c.uuid.toString() ==
              "9d410019-35d6-f4dd-ba60-e7bd8dc491c0") {
            response = c;
          }
        }
      }
      Random rng = Random();
      List<int> channel = [0];
      for (var i = 0; i < 4; i++) {
        channel.add(rng.nextInt(256));
      }

      List<int> randA = [];
      for (var i = 0; i < 14; i++) {
        randA.add(rng.nextInt(256));
      }
      var nonce = 0;
      List<int>? authKeyMac;
      var expectedPrefix = 0;
      response.onValueReceived.listen((data) async {
        final int prefix = data[0];
        int toaType;
        if (prefix != expectedPrefix) {
          throw "Something went wrong";
        }
        if (prefix == 0) {
          toaType = data[5];
        } else {
          toaType = data[1];
        }

        Future<void> authenticatedSend(int prefix, List<int> payload) async {
          nonce++;
          final bfNonceA = convertToLongBuffer(nonce);
          List<int> hmac = (await generateHmac(
                  authKeyMac!, bfNonceA + [1, payload.length] + payload))
              .bytes
              .sublist(0, 4);
          await command.write([prefix] + payload + hmac, withoutResponse: true);
        }

        ;

        if (toaType == 1) {
          // Just singing a song, walking along
          await authenticatedSend(prefix, [5, 2, 1, 3]);
        } else if (toaType == 7) {
          // Ringing...
          await authenticatedSend(expectedPrefix, [17, 0]);
        } else if (toaType == 18) {
          // Finish auth, open the channel
          expectedPrefix = data[6];
          List<int> channelData = data.sublist(7);

          final authKey = base64Decode(
              devices[widget.device.remoteId.toString()]!["authKey"]!);
          authKeyMac = (await generateHmac(authKey,
                  randA + channelData + [expectedPrefix] + channel.sublist(1)))
              .bytes
              .sublist(0, 16);
          await authenticatedSend(expectedPrefix, [18, 19]);
        } else if (toaType == 19) {
          // Closed, bye
        } else if (toaType == 21) {
          // Start auth
          await command.write(channel + [16] + randA, withoutResponse: true);
        }
      });
      await response.setNotifyValue(true);
      await command.write(channel + [20] + randA, withoutResponse: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e),
          success: false);
    }
    if (mounted) {
      setState(() {
        _isDiscoveringServices = false;
      });
    }
  }

  Future onRequestMtuPressed() async {
    try {
      await widget.device.requestMtu(223, predelay: 0);
      Snackbar.show(ABC.c, "Request Mtu: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Change Mtu Error:", e),
          success: false);
    }
  }

  List<Widget> _buildServiceTiles(BuildContext context, BluetoothDevice d) {
    return _services
        .map(
          (s) => ServiceTile(
            service: s,
            characteristicTiles: s.characteristics
                .map((c) => _buildCharacteristicTile(c))
                .toList(),
          ),
        )
        .toList();
  }

  CharacteristicTile _buildCharacteristicTile(BluetoothCharacteristic c) {
    return CharacteristicTile(
      characteristic: c,
      descriptorTiles:
          c.descriptors.map((d) => DescriptorTile(descriptor: d)).toList(),
    );
  }

  Widget buildSpinner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: CircularProgressIndicator(
          backgroundColor: Colors.black12,
          color: Colors.black26,
        ),
      ),
    );
  }

  Widget buildRemoteId(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text('${widget.device.remoteId}'),
    );
  }

  Widget buildRssiTile(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        isConnected
            ? const Icon(Icons.bluetooth_connected)
            : const Icon(Icons.bluetooth_disabled),
        Text(((isConnected && _rssi != null) ? '${_rssi!} dBm' : ''),
            style: Theme.of(context).textTheme.bodySmall)
      ],
    );
  }

  Widget buildGetServices(BuildContext context) {
    return IndexedStack(
      index: (_isDiscoveringServices) ? 1 : 0,
      children: <Widget>[
        TextButton(
          child: const Text("RING"),
          onPressed: onDiscoverServicesPressed,
        ),
        const IconButton(
          icon: SizedBox(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.grey),
            ),
            width: 18.0,
            height: 18.0,
          ),
          onPressed: null,
        )
      ],
    );
  }

  Widget buildMtuTile(BuildContext context) {
    return ListTile(
        title: const Text('MTU Size'),
        subtitle: Text('$_mtuSize bytes'),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: onRequestMtuPressed,
        ));
  }

  Widget buildConnectButton(BuildContext context) {
    return Row(children: [
      if (_isConnecting || _isDisconnecting) buildSpinner(context),
      TextButton(
          onPressed: _isConnecting
              ? onCancelPressed
              : (isConnected ? onDisconnectPressed : onConnectPressed),
          child: Text(
            _isConnecting ? "CANCEL" : (isConnected ? "DISCONNECT" : "CONNECT"),
            style: Theme.of(context)
                .primaryTextTheme
                .labelLarge
                ?.copyWith(color: Colors.white),
          ))
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.platformName),
          actions: [buildConnectButton(context)],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              buildRemoteId(context),
              ListTile(
                leading: buildRssiTile(context),
                title: Text(
                    'Device is ${_connectionState.toString().split('.')[1]}.'),
                trailing: buildGetServices(context),
              ),
              buildMtuTile(context),
              ..._buildServiceTiles(context, widget.device),
            ],
          ),
        ),
      ),
    );
  }
}

List<int> convertToLongBuffer(int n) {
  var hexString = n.toRadixString(16);
  if (hexString.length.isOdd) {
    hexString = "0" + hexString;
  }
  final l = hexString.length ~/ 2;
  var result = [0, 0, 0, 0, 0, 0, 0, 0];
  for (var i = 0; i < l; ++i) {
    var x = int.parse(hexString.substring(2 * i, 2 * (i + 1)), radix: 16);
    result[i] = x;
  }
  return result;
}

Future<Mac> generateHmac(List<int> secret, List<int> data) {
  final hmac = Hmac.sha256();
  while (data.length < 32) {
    data.add(0);
  }
  return hmac.calculateMac(
    data,
    secretKey: SecretKey(secret),
  );
}
