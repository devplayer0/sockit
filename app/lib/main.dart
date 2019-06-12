import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:multicast_dns/multicast_dns.dart';

const SERVICE = '_sockit._tcp';
const QUERY = '${SERVICE}.local';
const SEARCH_TIME = Duration(seconds: 3);
const EXTRA_SEARCH_TIME = Duration(milliseconds: 300);

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

class Device {
  String service, name;
  int port;

  Set<InternetAddress> addresses = {};

  Device(this.service, this.port) {
    this.name = service.substring(0, service.length - QUERY.length - 1);
  }

  _addressSummary() =>
    Text(addresses.map((addr) => '${addr.host}:${port}').join(', '));
  Widget build(BuildContext context) =>
      ListTile(
        title: Text(name),
        subtitle: _addressSummary(),
      );

}
class _SockitHomeState extends State<SockitHome> with WidgetsBindingObserver {
  final List<Device> _devices = [];
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey<RefreshIndicatorState>();
  final MDnsClient _mDnsClient = MDnsClient();

  @override
  void initState() {
    super.initState();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _refreshKey.currentState.show();
    });
  }

  Future<void> _reload() async {
    setState(() {
      _devices.clear();
    });

    await _mDnsClient.start();
    await for (PtrResourceRecord ptr in _mDnsClient.lookup(ResourceRecordQuery.serverPointer(QUERY), timeout: SEARCH_TIME)) {
      await for (SrvResourceRecord srv in _mDnsClient.lookup(ResourceRecordQuery.service(ptr.domainName), timeout: EXTRA_SEARCH_TIME)) {
        await for (IPAddressResourceRecord a in _mDnsClient.lookup(ResourceRecordQuery.addressIPv4(srv.target), timeout: EXTRA_SEARCH_TIME)) {
          var device = _devices.firstWhere((dev) => dev.service == srv.name, orElse: () {
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

    _mDnsClient.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: new RefreshIndicator(
        child: ListView.builder(
          itemCount: _devices.length,
          itemBuilder: (context, position) =>
            _devices[position].build(context),
        ),
        onRefresh: _reload,
        key: _refreshKey,
      ),
    );
  }
}
