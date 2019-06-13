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

const DEV_DURATION = Duration(milliseconds: 200);

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

final _scaffoldKey = GlobalKey<ScaffoldState>();
class Device {
  static const MIN_REQ_DURATION = Duration(milliseconds: 200);

  final String service, name;
  final int port;
  final Set<InternetAddress> addresses = LinkedHashSet();

  String description;
  final _reqInProgress = ValueNotifier(false);
  final _state = ValueNotifier(false);

  Device(this.service, this.port) : name =
    service.substring(0, service.length - QUERY.length - 1);
  @override
  int get hashCode => name.hashCode;
  @override
  bool operator ==(dynamic other) {
    if (other is! Device) {
      return false;
    }

    Device dev = other;
    return dev.name == name;
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
  Future<R> _uiReq<R>(Request<R> req, {String failure = 'Error'}) async {
    final watch = Stopwatch()..start();
    _reqInProgress.value = true;
    try {
      return await _makeReq(req);
    } catch (err) {
      final snackBar = SnackBar(content: Text('$failure: $err'));
      _scaffoldKey.currentState.showSnackBar(snackBar);
    } finally {
      watch.stop();
      await Future.delayed(MIN_REQ_DURATION - watch.elapsed);
      _reqInProgress.value = false;
    }
  }

  Future<void> loadState() async {
    _state.value = await _uiReq(
      GetState(),
      failure: 'Failed to get state of "$name"'
    );
  }
  Future<void> setState(bool newState) async {
    if (await _uiReq(
        SetState(newState),
        failure: 'Failed to turn "$name" ${newState ? "on" : "off"}'
    ) != null) {
      _state.value = newState;
    }
  }

  _extraInfo() =>
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

  Widget build(BuildContext context, Animation<double> animation) =>
    SlideTransition(
      position: animation.drive(Tween<Offset>(
        begin: Offset(1, 0),
        end: Offset.zero,
      )),
      child: Card(
        child: ListTile(
          title: Text(name),
          subtitle: _extraInfo(),
          isThreeLine: description != null,
          trailing: ValueListenableBuilder<bool>(
            valueListenable: _reqInProgress,
            builder: (context, rip, child) => rip ?
              CircularProgressIndicator() :
                ValueListenableBuilder<bool>(
                  valueListenable: _state,
                  builder: (context, state, child) => Switch(
                    value: _state.value,
                    onChanged: setState,
                  ),
                ),
          ),
          onTap: () => setState(!_state.value),
        )
      )
    );
}

class _SockitHomeState extends State<SockitHome> with WidgetsBindingObserver {
  bool _reloading = false;
  final List<Device> _devices = [];
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey();

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
    });

    final renewed = HashSet();
    final MDnsClient mDnsClient = MDnsClient();
    await mDnsClient.start();
    await for (PtrResourceRecord ptr in mDnsClient.lookup(
      ResourceRecordQuery.serverPointer(QUERY),
      timeout: SEARCH_TIME)
    ) {
      await for (SrvResourceRecord srv in mDnsClient.lookup(
        ResourceRecordQuery.service(ptr.domainName),
        timeout: EXTRA_SEARCH_TIME)
      ) {
        var device = _devices.firstWhere(
          (dev) => dev.service == srv.name,
          orElse: () {
            var dev = Device(srv.name, srv.port);
            _devices.add(dev);
            _listKey.currentState.insertItem(_devices.length - 1, duration: DEV_DURATION);
            return dev;
          },
        );
        final shouldLoad = renewed.add(device);

        await for (IPAddressResourceRecord a in mDnsClient.lookup(
          ResourceRecordQuery.addressIPv4(srv.target),
          timeout: EXTRA_SEARCH_TIME)
        ) {
          setState(() {
            device.addresses.add(a.address);
            if (shouldLoad) {
              device.loadState();
            }
          });
        }
        await for (TxtResourceRecord txt in mDnsClient.lookup(
          ResourceRecordQuery.text(srv.target),
          timeout: EXTRA_SEARCH_TIME)
        ) {
          if (txt.text.trim().startsWith(DESCRIPTION_REGEX)) {
            setState(() {
              device.description = txt.text.split('=').sublist(1).join('=');
            });
          }
        }
      }
    }

    mDnsClient.stop();
    setState(() {
      _reloading = false;
      _devices.where((dev) => !renewed.contains(dev)).toSet().forEach((dev) {
        int i =_devices.indexOf(dev);
        _devices.removeAt(i);
        _listKey.currentState.removeItem(i, dev.build, duration: DEV_DURATION);
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
              child: Center(child: const Text('No devices found'))
            ),
          ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
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
