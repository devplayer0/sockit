import 'dart:collection';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:multicast_dns/multicast_dns.dart';

const SERVICE = '_sockit._tcp';
const QUERY = '${SERVICE}.local';
const SEARCH_TIME = Duration(seconds: 2);
const EXTRA_SEARCH_TIME = Duration(milliseconds: 300);
final DESCRIPTION_REGEX = RegExp(r'.*description=');

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

String getErrorMessage(int type) {
  switch (type) {
    case 0x00:
      return 'Bad request';
    case 0x01:
      return 'Failed';
    default:
      return 'Unknown';
  }
}
abstract class Request<R> {
  static const MAGIC = 'SKIT';

  final int type;
  Request(this.type);

  ByteData encode();
  R decodeResponse(ByteData res) {
    if (res.lengthInBytes == 0) {
      throw 'Received zero length response';
    }

    final status = res.getUint8(0);
    if (status == 0xff) {
      throw getErrorMessage(res.getUint8(1));
    }
  }
}
class GetState extends Request<bool> {
  GetState() : super(0x00);

  @override
  bool decodeResponse(ByteData res) {
    super.decodeResponse(res);
    return res.getUint8(1) != 0;
  }

  @override
  ByteData encode() {
    return null;
  }
}
class SetState extends Request<bool> {
  final bool newState;
  SetState(this.newState) : super(0x01);

  @override
  bool decodeResponse(ByteData res) {
    super.decodeResponse(res);
    return res.getUint8(1) != 0;
  }

  @override
  ByteData encode() {
    return ByteData(1)
      ..setUint8(0, newState ? 1 : 0);
  }
}

class Device {
  String service, name, description;
  int port;
  Set<InternetAddress> addresses = LinkedHashSet();

  Device(this.service, this.port) {
    this.name = service.substring(0, service.length - QUERY.length - 1);
  }

  Future<R> _makeReq<R>(Request<R> req) async {
    final conn = await Socket.connect(addresses.first, port);

    var data = ascii.encode(Request.MAGIC) + [req.type];
    final reqParams = req.encode();
    if (reqParams != null) {
      data += reqParams.buffer.asUint8List();
    }
    conn.add(data);

    final res_data = Uint8List.fromList(await conn.first);
    final res = ByteData.view(res_data.buffer);
    conn.destroy();

    return req.decodeResponse(res);
  }

  _extra() =>
    Wrap(
      direction: Axis.vertical,
      spacing: 2.0,
      children: <Widget>[
        if (description != null) Text(description),
        Text(
          addresses.map((addr) => '${addr.host}:${port}').join(', '),
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    );

  Widget build(BuildContext context) =>
      ListTile(
        title: Text(name),
        subtitle: _extra(),
        isThreeLine: true,
        onTap: () async {
          var message;
          try {
            bool newState = Random().nextBool();
            bool oldState = await _makeReq(SetState(newState));
            message = 'New state: $oldState, Old state: $oldState';
          } catch (err) {
            message = 'Failed to get state: $err';
          }

          final snackBar = SnackBar(content: Text(message));
          Scaffold.of(context).showSnackBar(snackBar);
        },
      );
}
class _SockitHomeState extends State<SockitHome> with WidgetsBindingObserver {
  final List<Device> _devices = [];
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey<RefreshIndicatorState>();

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

    final MDnsClient mDnsClient = MDnsClient();
    await mDnsClient.start();
    await for (PtrResourceRecord ptr in mDnsClient.lookup(ResourceRecordQuery.serverPointer(QUERY), timeout: SEARCH_TIME)) {
      await for (SrvResourceRecord srv in mDnsClient.lookup(ResourceRecordQuery.service(ptr.domainName), timeout: EXTRA_SEARCH_TIME)) {
        var device = _devices.firstWhere((dev) => dev.service == srv.name, orElse: () {
          var dev = Device(srv.name, srv.port);
          _devices.add(dev);
          return dev;
        });

        await for (IPAddressResourceRecord a in mDnsClient.lookup(ResourceRecordQuery.addressIPv4(srv.target), timeout: EXTRA_SEARCH_TIME)) {
          setState(() {
            device.addresses.add(a.address);
          });
        }
        await for (TxtResourceRecord txt in mDnsClient.lookup(ResourceRecordQuery.text(srv.target), timeout: EXTRA_SEARCH_TIME)) {
          if (txt.text.trim().startsWith(DESCRIPTION_REGEX)) {
            setState(() {
              device.description = txt.text.split('=').sublist(1).join('=');
            });
          }
        }
      }
    }

    mDnsClient.stop();
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
