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

import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

final LIST_EQUALS = ListEquality().equals;

final MULTICAST_GROUP = InternetAddress('224.0.0.220');
const DISCOVERY_PORT = 40420;
final MAGIC = ascii.encode('SKIT');
const SEARCH_INTERVAL = Duration(milliseconds: 500);
const SEARCH_TIME = Duration(seconds: 2);

const DEV_DURATION = Duration(milliseconds: 200);
const MIN_RSSI = -100;
const MAX_RSSI = -55;

int _rssiToLevel(int rssi, int levels) {
  if (rssi <= MIN_RSSI) {
    return 0;
  } else if (rssi >= MAX_RSSI) {
    return levels - 1;
  } else {
    final inputRange = (MAX_RSSI - MIN_RSSI);
    final outputRange = (levels - 1);
    return ((rssi - MIN_RSSI) * outputRange ~/ inputRange);
  }
}
class AuthMode {
  final String name;

  AuthMode(this.name);

  Icon getIcon(int rssi) {
    final level = _rssiToLevel(rssi, 5);
    if (this == open) {
      switch (level) {
        case 0:
          return Icon(MdiIcons.wifiStrengthOutline);
        case 1:
          return Icon(MdiIcons.wifiStrength1);
        case 2:
          return Icon(MdiIcons.wifiStrength2);
        case 3:
          return Icon(MdiIcons.wifiStrength3);
        case 4:
          return Icon(MdiIcons.wifiStrength4);
      }
    } else if (this == unknown) {
      switch (level) {
        case 0:
          return Icon(MdiIcons.wifiStrengthAlertOutline);
        case 1:
          return Icon(MdiIcons.wifiStrength1Alert);
        case 2:
          return Icon(MdiIcons.wifiStrength2Alert);
        case 3:
          return Icon(MdiIcons.wifiStrength3Alert);
        case 4:
          return Icon(MdiIcons.wifiStrength4Alert);
      }
    } else {
      switch (level) {
        case 0:
          return Icon(MdiIcons.wifiStrengthLockOutline);
        case 1:
          return Icon(MdiIcons.wifiStrength1Lock);
        case 2:
          return Icon(MdiIcons.wifiStrength2Lock);
        case 3:
          return Icon(MdiIcons.wifiStrength3Lock);
        case 4:
          return Icon(MdiIcons.wifiStrength4Lock);
      }
    }
  }

  static AuthMode fromValue(int value) {
    switch (value) {
      case 0:
        return open;
      case 1:
        return wep;
      case 2:
        return wpa;
      case 3:
        return wpa2;
      case 4:
        return wpaWpa2;
      default:
        return unknown;
    }
  }

  static final AuthMode open = AuthMode('Open');
  static final AuthMode wep = AuthMode('WEP');
  static final AuthMode wpa = AuthMode('WPA PSK');
  static final AuthMode wpa2 = AuthMode('WPA2 PSK');
  static final AuthMode wpaWpa2 = AuthMode('WPA/WPA2 PSK');
  static final AuthMode unknown = AuthMode('Unknown');
}
class NetInfo {
  final String ssid;
  final AuthMode authMode;
  final int rssi;
  NetInfo(this.ssid, this.authMode, this.rssi);

  Icon getIcon() => authMode.getIcon(rssi);
}

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
  final int type;
  Request(this.type);

  ByteData encode() => null;
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
  ByteData encode() => ByteData(1)..setUint8(0, newState ? 1 : 0);
}

_encodeString(String str) {
  final strData = utf8.encode(str);
  if (strData.length > 0xff) {
    throw 'UTF-8 encoded string too long (max 255 bytes)';
  }

  final data = ByteData(1 + strData.length);
  data.setUint8(0, strData.length);
  data.buffer.asUint8List(1).setAll(0, strData);
  return data;
}
class SetName extends Request<bool> {
  final String newName;
  SetName(this.newName) : super(0x02);

  @override
  ByteData encode() => _encodeString(newName);
  @override
  bool decodeResponse(ByteData res) {
    super.decodeResponse(res);
    return true;
  }
}
class SetDescription extends Request<bool> {
  final String newDescription;
  SetDescription(this.newDescription) : super(0x03);

  @override
  ByteData encode() => _encodeString(newDescription);
  @override
  bool decodeResponse(ByteData res) {
    super.decodeResponse(res);
    return true;
  }
}
class GetNet extends Request<dynamic> {
  GetNet() : super(0x04);

  @override
  dynamic decodeResponse(ByteData res) {
    super.decodeResponse(res);
    final mode = res.getUint8(1);
    if (mode == 1) {
      return true;
    } else {
      final len = res.getUint8(2);
      return utf8.decode(res.buffer.asUint8List(3, len));
    }
  }
}
class GetNets extends Request<List<NetInfo>> {
  GetNets() : super(0x05);

  @override
  List<NetInfo> decodeResponse(ByteData res) {
    super.decodeResponse(res);

    final nets = List<NetInfo>();
    final count = res.getUint8(1);
    var offset = 2;
    for (var i = 0; i < count; i++) {
      final authMode = AuthMode.fromValue(res.getUint8(offset));
      final rssi = res.getInt8(offset + 1);
      final ssidLen = res.getUint8(offset + 2);
      final ssid = utf8.decode(res.buffer.asUint8List(offset + 3, ssidLen));
      offset += 3 + ssidLen;

      nets.add(NetInfo(ssid, authMode, rssi));
    }

    return nets;
  }
}
class SetNet extends Request<void> {
  final String ssid, password;
  SetNet(this.ssid, this.password) : super(0x06);
  SetNet.ap() : this(null, null);

  @override
  ByteData encode() {
    if (ssid == null) {
      return ByteData(1)..setUint8(0, 1);
    } else {
      final start = ByteData(1)..setUint8(0, 0);
      return ByteData.view(
        Uint8List.fromList(
          start.buffer.asUint8List() +
          _encodeString(ssid).buffer.asUint8List() +
          _encodeString(password).buffer.asUint8List()
        ).buffer
      );
    }
  }
}

final _scaffoldKey = GlobalKey<ScaffoldState>();
class Device {
  static const MIN_REQ_DURATION = Duration(milliseconds: 150);

  final InternetAddress address;
  final int port;
  final _name, _description;
  bool editable = false;

  final _state = ValueNotifier(false);
  final _reqInProgress = ValueNotifier(false);

  final GlobalKey<FormState> _settingsKey = GlobalKey();
  final _settingsChanged = ValueNotifier(false);
  final _nameCtl = TextEditingController();
  final _descCtl = TextEditingController();
  final _isApKey = GlobalKey<FormFieldState<bool>>();
  final _cNetKey = GlobalKey<FormFieldState<String>>();

  final GlobalKey<FormState> _pwdSettingsKey = GlobalKey();
  final _pwdCtl = TextEditingController();

  String _password;
  String _currentNet;
  List<NetInfo> _networks = List<NetInfo>();

  Device(this.address, this.port,
    {@required String name, @required String description}) :
    _name = ValueNotifier(name), _description = ValueNotifier(description) {
    _nameCtl.text = name;
    _descCtl.text = description;
  }
  @override
  int get hashCode => address.hashCode;
  @override
  bool operator ==(dynamic other) {
    if (other is! Device) {
      return false;
    }

    Device dev = other;
    return dev.address == address;
  }

  String get name => _name.value;
  String get description => _description.value;
  void set name(String newName) {
    _name.value = newName;
    _nameCtl.text = newName;
  }
  void set description(String newDesc) {
    _description.value = newDesc;
    _descCtl.text = newDesc;
  }

  Future<R> _makeReq<R>(Request<R> req) async {
    final conn = await Socket.connect(address, port);

    var data = MAGIC + [req.type];
    final reqParams = req.encode();
    if (reqParams != null) {
      data += reqParams.buffer.asUint8List();
    }
    conn.add(data);

    final resData = Uint8List.fromList(await conn.first);
    final res = ByteData.view(resData.buffer);
    conn.destroy();

    return req.decodeResponse(res);
  }
  Future<R> _uiReq<R>(Request<R> req, {String failure = 'Error'}) async {
    final watch = Stopwatch()..start();
    _reqInProgress.value = true;
    try {
      return await _makeReq(req);
    } catch (err, trace) {
      print(trace);
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
  Future<void> _loadNetworks() async {
    _pwdCtl.clear();
    _password = null;
    _networks = await _uiReq(GetNets());

    final current = await _uiReq(GetNet());
    if (current.runtimeType == bool && current) {
      _currentNet = null;
    } else {
      _currentNet = current;
    }
  }

  _extraInfo() =>
    Wrap(
      direction: Axis.vertical,
      spacing: 2.0,
      children: <Widget>[
        ValueListenableBuilder<String>(
          valueListenable: _description,
          builder: (context, description, child) => Text(description),
        ),
        Text(
          address.address,
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    );

  String _validateStr(String value) {
    if (value.isEmpty) {
      return 'Enter a value';
    }
    if (utf8.encode(value).length > 0xff) {
      return 'Value too long';
    }
  }
  _showPasswordDialog(BuildContext context, String ssid) => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Enter password for "$ssid"'),
      content: Form(
        key: _pwdSettingsKey,
        child: TextFormField(
          controller: _pwdCtl,
          validator: _validateStr,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Password',
          ),
        ),
      ),
      actions: <Widget>[
        FlatButton(
          child: Text('CANCEL'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        FlatButton(
          child: Text('SAVE'),
          onPressed: () {
            if (_pwdSettingsKey.currentState.validate()) {
              _password = _pwdCtl.text;
              Navigator.of(context).pop(true);
            }
          },
        ),
      ],
    ),
  );
  List<Widget> _buildNetworkItems(bool isAp, FormFieldState<String> field) {
    final currentNet = field.value;
    final items = List<Widget>();
    _networks.forEach((item) =>
      items.add(
        ListTile(
          enabled: !isAp,
          selected: currentNet == item.ssid,
          dense: true,
          leading: item.getIcon(),
          title: Text(item.ssid),
          subtitle: Text(
            _currentNet == item.ssid ?
            '${item.authMode.name} - Currently connected' : item.authMode.name,
          ),
          onTap: item.authMode == AuthMode.unknown ? null : () async {
            var shouldSet = true;
            if (item.authMode != AuthMode.open) {
              shouldSet = await _showPasswordDialog(field.context, item.ssid);
              _pwdCtl.clear();
            }
            if (!shouldSet) {
              return;
            }

            field.setState(() {
              field.setValue(item.ssid);
              _checkSettingsChanged();
            });
          },
        )
      )
    );

    return items;
  }
  _checkSettingsChanged() => _settingsChanged.value =
    _nameCtl.text != name || _descCtl.text != description ||
    _isApKey.currentState.value != (_currentNet == null) ||
    _cNetKey.currentState.value != _currentNet ||
    _password != null;
  _buildSettingsForm(BuildContext context) => Form(
    key: _settingsKey,
    onChanged: _checkSettingsChanged,
    child: Container(
      child: ListBody(
        children: <Widget>[
          TextFormField(
            controller: _nameCtl,
            validator: _validateStr,
            onSaved: (value) async {
              if (value == name) {
                return;
              }

              if (await _uiReq(SetName(value)) != null)
                name = value;
            },
            decoration: InputDecoration(
              labelText: 'Name',
            ),
          ),
          TextFormField(
            controller: _descCtl,
            validator: _validateStr,
            onSaved: (value) async {
              if (value == description) {
                return;
              }

              if (await _uiReq(SetDescription(value)) != null)
                description = value;
            },
            decoration: InputDecoration(
              labelText: 'Description',
            ),
          ),
          Container(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'WiFi network',
              style: Theme.of(context).textTheme.caption,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('Use built-in WiFi'),
              FormField(
                key: _isApKey,
                initialValue: _currentNet == null,
                builder: (field) => Switch(
                  value: field.value,
                  onChanged: (value) => field.setState(() {
                    field.setValue(value);
                    _checkSettingsChanged();
                    _cNetKey.currentState.setState(() {});
                  }),
                ),
                onSaved: (value) {
                  if (_isApKey.currentState.value == (_currentNet == null) &&
                    _cNetKey.currentState.value == _currentNet &&
                    _password == null) {
                    // WiFi settings not changed
                    return;
                  }

                  if (value) {
                    _uiReq(SetNet.ap());
                  } else {
                    _uiReq(SetNet(_cNetKey.currentState.value, _password ?? ''));
                  }
                },
              ),
            ],
          ),
          Container(
            width: double.maxFinite,
            height: 270,
            child: FormField(
              key: _cNetKey,
              initialValue: _currentNet,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Scrollbar(
                      child: ListView(
                        children: _buildNetworkItems(
                          _isApKey.currentState.value,
                          field
                        ),
                      ),
                    ),
                  ),
                  if (field.hasError) Container(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      field.errorText,
                      style: Theme.of(context).textTheme.caption.merge(
                        TextStyle(
                          color: Theme.of(context).errorColor
                        )
                      ),
                    ),
                  ),
                ],
              ),
              validator: (currentNet) {
                if (currentNet == null && !_isApKey.currentState.value) {
                  return 'Please select a network';
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
  _openSettings(BuildContext context) async {
    await _loadNetworks();
    _settingsChanged.value = false;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"$name" settings'),
        content: SingleChildScrollView(
          child: _buildSettingsForm(context),
        ),
        actions: <Widget>[
          FlatButton(
            child: Text('CANCEL'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _settingsChanged,
            builder: (context, changed, child) =>
              FlatButton(
                child: Text('SAVE'),
                onPressed: changed ? () async {
                    final form = _settingsKey.currentState;
                    if (form.validate()) {
                      Navigator.of(context).pop();
                      form.save();
                    }
                } : null,
              ),
          ),
        ],
      ),
    );
  }

  Widget build(BuildContext context, Animation<double> animation) =>
    SizeTransition(
      sizeFactor: animation,
      child: Card(
        child: ListTile(
          title: ValueListenableBuilder<String>(
            valueListenable: _name,
            builder: (context, name, child) => Text(name),
          ),
          subtitle: _extraInfo(),
          isThreeLine: true,
          trailing: ValueListenableBuilder<bool>(
            valueListenable: _reqInProgress,
            builder: (context, rip, child) => rip ?
              CircularProgressIndicator() :
                ValueListenableBuilder<bool>(
                  valueListenable: _state,
                  builder: (context, state, child) => Switch(
                    value: _state.value ?? false,
                    onChanged: editable ? setState : null,
                  ),
                ),
          ),
          onTap: editable ? () => setState(!_state.value) : null,
          onLongPress: editable ? () => _openSettings(context) : null,
        )
      )
    );
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

    final searchData = MAGIC + [0x00];
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
      if (!LIST_EQUALS(data.buffer.asUint8List(0, MAGIC.length), MAGIC)) {
        print('ignoring invalid beacon from ${msg.address}:${msg.port}');
        continue;
      }

      print('received beacon from ${msg.address}:${msg.port}');

      final nameLen = data.getUint8(MAGIC.length + 2);
      final name = utf8.decode(data.buffer.asUint8List(MAGIC.length + 2 + 1, nameLen));
      final description = utf8.decode(data.buffer.asUint8List(MAGIC.length + 2 + 1 + nameLen));
      final device = _devices.firstWhere(
        (dev) => dev.address == msg.address,
        orElse: () {
          final port = data.getUint16(MAGIC.length);

          var dev = Device(
            msg.address,
            port,
            name: name,
            description: description,
          );
          _devices.add(dev);
          _listKey.currentState.insertItem(_devices.length - 1, duration: DEV_DURATION);
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
              child: Center(child: Text('No devices found.'))
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
