import 'dart:io';

import 'package:flutter/material.dart';
import 'package:multicast_dns/multicast_dns.dart';

const SERVICE = '_sockit._tcp';
const QUERY = '${SERVICE}.local';
const SEARCH_TIME = Duration(seconds: 10);
const EXTRA_SEARCH_TIME = Duration(milliseconds: 300);

void main() => runApp(SockitApp());

class SockitApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
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

class Device {
  String name;
  int port;

  Set<InternetAddress> addresses = {};

  Device(this.name, this.port);
}
class _SockitHomeState extends State<SockitHome> with WidgetsBindingObserver {
  List<Device> _devices = [];
  bool _isSearching = true;
  MDnsClient _mDnsClient = MDnsClient();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _reload();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      print('pausing mDNS client');
      _mDnsClient.stop();
    }
  }

  _reload() async {
    setState(() {
      _devices.clear();
    });

    await _mDnsClient.start();
    await for (PtrResourceRecord ptr in _mDnsClient.lookup(ResourceRecordQuery.serverPointer(QUERY), timeout: SEARCH_TIME)) {
      await for (SrvResourceRecord srv in _mDnsClient.lookup(ResourceRecordQuery.service(ptr.domainName), timeout: EXTRA_SEARCH_TIME)) {
        await for (IPAddressResourceRecord a in _mDnsClient.lookup(ResourceRecordQuery.addressIPv4(srv.target), timeout: EXTRA_SEARCH_TIME)) {
          var device = _devices.firstWhere((dev) => dev.name == srv.name, orElse: () {
            var dev = Device(srv.name, srv.port);
            _devices.add(dev);
            return dev;
          });

          setState(() {
            device.addresses.add(a.address);
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: ListView.builder(
        itemCount: _devices.length,
        itemBuilder: (context, position) =>
          Padding(
            padding: EdgeInsets.all(10.0),
            child: Text(_devices[position].name)
          ),
      ),
    );
  }
}
