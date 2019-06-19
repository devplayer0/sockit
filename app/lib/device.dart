import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'net.dart';
import 'globals.dart';

String _validateStr(String value) {
  if (value.isEmpty) {
    return 'Enter a value';
  }
  if (utf8.encode(value).length > 0xff) {
    return 'Value too long';
  }
}

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

    var data = PROTO_MAGIC + [req.type];
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
      appKey.currentState.showSnackBar(snackBar);
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

  _checkSettingsChanged() => _settingsChanged.value =
    _nameCtl.text != name || _descCtl.text != description ||
      _isApKey.currentState.value != (_currentNet == null) ||
      _cNetKey.currentState.value != _currentNet ||
      _password != null;
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
          subtitle: Wrap(
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
          ),
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
