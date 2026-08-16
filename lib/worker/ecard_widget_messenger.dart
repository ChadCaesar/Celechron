import 'dart:io';

import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/http/zjuServices/ecard.dart';

import '../utils/utils.dart';

class ECardWidgetMessenger {
  static const _platform = MethodChannel('top.celechron.celechron/ecardWidget');

  /// Allows the iPhone companion to refresh a credential after Watch reports
  /// an explicit authentication failure. This reuses the same CAS flow as the
  /// iPhone ECardWidget instead of teaching native code a second login flow.
  static void installNativeHandler() {
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'refreshCredential') {
        return await update(notifyNative: false);
      }
      throw MissingPluginException('Unsupported ECard method: ${call.method}');
    });
  }

  static Future<bool> update({bool notifyNative = true}) async {
    var secureStorage = const FlutterSecureStorage();
    var username = await secureStorage.read(
        key: 'username', iOptions: secureStorageIOSOptions);
    var password = await secureStorage.read(
        key: 'password', iOptions: secureStorageIOSOptions);
    if (username == null || password == null) return false;

    // 如果是测试账号，则直接写入
    if (username == "3200000000") {
      await secureStorage.write(
          key: 'synjonesAuth',
          value: "3200000000",
          iOptions: secureStorageIOSOptions);
      await secureStorage.write(
          key: 'eCardAccount',
          value: "3200000000",
          iOptions: secureStorageIOSOptions);

      if (notifyNative && (Platform.isIOS || Platform.isAndroid)) {
        await _platform.invokeMethod('update');
      }
      return true;
    }

    var httpClient = HttpClient();
    httpClient.userAgent =
        "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)";

    try {
      var iPlanetDirectoryPro =
          await ZjuAm.getSsoCookie(httpClient, username, password)
              .catchError((e) => null);
      var synjonesAuth =
          await ECard.getSynjonesAuth(httpClient, iPlanetDirectoryPro);
      var eCardAccount = await ECard.getAccount(httpClient, synjonesAuth);
      await secureStorage.write(
          key: 'synjonesAuth',
          value: synjonesAuth,
          iOptions: secureStorageIOSOptions);
      await secureStorage.write(
          key: 'eCardAccount',
          value: eCardAccount,
          iOptions: secureStorageIOSOptions);

      if (notifyNative && PlatformFeatures.hasWidgetSupport) {
        await _platform.invokeMethod('update');
      }
      return true;
    } catch (e) {
      return false;
    } finally {
      httpClient.close(force: true);
    }
  }

  static Future<void> logout() async {
    var secureStorage = const FlutterSecureStorage();
    await secureStorage.delete(
        key: 'synjonesAuth', iOptions: secureStorageIOSOptions);
    await secureStorage.delete(
        key: 'eCardAccount', iOptions: secureStorageIOSOptions);

    if (PlatformFeatures.hasWidgetSupport) {
      await _platform.invokeMethod('logout');
    }
  }
}
