import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'net.dart';
import 'device.dart';
import 'globals.dart';

final LIST_EQUALS = ListEquality().equals;

const SEARCH_INTERVAL = Duration(milliseconds: 500);
const SEARCH_TIME = Duration(seconds: 2);

const DEV_ANIMATE_DURATION = Duration(milliseconds: 200);

void main() => runApp(SockitApp());

class SockitApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sockit',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: SockitHome(title: 'Sockit'),
    );
  }
}

class SockitHome extends StatefulWidget {
  final title;
  SockitHome({Key key, this.title}) : super(key: key);

  @override
  _SockitHomeState createState() => _SockitHomeState();
}

class _SockitHomeState extends State<SockitHome> with WidgetsBindingObserver {
  final List<Device> _devices = [];
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  bool _reloading = false;

  @override
  void initState() {
    super.initState();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _refreshKey.currentState.show();
    });
  }

  Future<void> _reload(BuildContext context) async {
    setState(() {
      _reloading = true;
      _devices.forEach((dev) => dev.editable = false);
    });

    final found = HashSet<Device>();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    socket.multicastHops = 1;

    final searchData = PROTO_MAGIC + [0x00];
    socket.send(searchData, MULTICAST_GROUP, DISCOVERY_PORT);
    final searchTimer = Timer.periodic(
      SEARCH_INTERVAL,
      (timer) {
        socket.send(searchData, MULTICAST_GROUP, DISCOVERY_PORT);
      },
    );

    Future.delayed(SEARCH_TIME, () {
      searchTimer.cancel();
      socket.close();
    });
    await for (RawSocketEvent event in socket) {
      if (event != RawSocketEvent.read) {
        continue;
      }

      final msg = socket.receive();
      final data = ByteData.view(Uint8List.fromList(msg.data).buffer);
      if (!LIST_EQUALS(data.buffer.asUint8List(0, PROTO_MAGIC.length), PROTO_MAGIC)) {
        print('ignoring invalid beacon from ${msg.address}:${msg.port}');
        continue;
      }

      print('received beacon from ${msg.address}:${msg.port}');

      final nameLen = data.getUint8(PROTO_MAGIC.length + 2);
      final name = utf8.decode(data.buffer.asUint8List(PROTO_MAGIC.length + 2 + 1, nameLen));
      final description = utf8.decode(data.buffer.asUint8List(PROTO_MAGIC.length + 2 + 1 + nameLen));
      final device = _devices.firstWhere(
        (dev) => dev.address == msg.address,
        orElse: () {
          final port = data.getUint16(PROTO_MAGIC.length);

          var dev = Device(
            msg.address,
            port,
            name: name,
            description: description,
          );
          _devices.add(dev);
          _listKey.currentState.insertItem(_devices.length - 1, duration: DEV_ANIMATE_DURATION);
          return dev;
        },
      );
      if (name != device.name) device.name = name;
      if (description != device.description) device.description = description;
      if (found.add(device)) {
        setState(() {
          device.editable = true;
          device.loadState();
        });
      }
    }

    setState(() {
      _reloading = false;
      _devices.where((dev) => !found.contains(dev)).toSet().forEach((dev) {
        int i =_devices.indexOf(dev);
        _devices.removeAt(i);
        _listKey.currentState.removeItem(i, dev.build, duration: DEV_ANIMATE_DURATION);
      });
    });
  }

  Widget _getBody() {
    return _devices.length != 0 || _reloading ?
      AnimatedList(
        key: _listKey,
        itemBuilder: (context, position, animation) =>
          _devices[position].build(context, animation),
      ) : LayoutBuilder(
        builder: (context, viewportConstraints) =>
          SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewportConstraints.maxHeight,
              ),
              child: Center(child: Text('No devices found.'))
            ),
          ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: appKey,
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: new RefreshIndicator(
        child: _getBody(),
        onRefresh: () => _reload(context),
        key: _refreshKey,
      ),
    );
  }
}
