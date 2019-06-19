import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

final MULTICAST_GROUP = InternetAddress('224.0.0.220');
const DISCOVERY_PORT = 40420;
final PROTO_MAGIC = ascii.encode('SKIT');

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
