import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Uses the system Security framework directly, including in AOT/pub installs.
/// Only public keys and signatures cross the FFI boundary. Keys persist in the
/// user's keychain with a ThisDeviceOnly policy and Secure Enclave token.
class SecureEnclaveKey {
  SecureEnclaveKey()
      : _security = DynamicLibrary.open(
            '/System/Library/Frameworks/Security.framework/Security'),
        _cf = DynamicLibrary.open(
            '/System/Library/Frameworks/CoreFoundation.framework/'
            'CoreFoundation');

  final DynamicLibrary _security;
  final DynamicLibrary _cf;

  late final void Function(Pointer<Void>) _release = _cf.lookupFunction<
      Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CFRelease');
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>, int, Pointer<Void>, Pointer<Void>)
      _dictionary = _cf.lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>,
              Pointer<Pointer<Void>>, IntPtr, Pointer<Void>, Pointer<Void>),
          Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Pointer<Void>>,
              Pointer<Pointer<Void>>,
              int,
              Pointer<Void>,
              Pointer<Void>)>('CFDictionaryCreate');
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int)
      _dataCreate = _cf.lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, IntPtr),
          Pointer<Void> Function(
              Pointer<Void>, Pointer<Uint8>, int)>('CFDataCreate');
  late final int Function(Pointer<Void>) _dataLength = _cf.lookupFunction<
      IntPtr Function(Pointer<Void>),
      int Function(Pointer<Void>)>('CFDataGetLength');
  late final Pointer<Uint8> Function(Pointer<Void>) _dataBytes =
      _cf.lookupFunction<Pointer<Uint8> Function(Pointer<Void>),
          Pointer<Uint8> Function(Pointer<Void>)>('CFDataGetBytePtr');
  late final int Function(Pointer<Void>, Pointer<Void>) _equal =
      _cf.lookupFunction<Uint8 Function(Pointer<Void>, Pointer<Void>),
          int Function(Pointer<Void>, Pointer<Void>)>('CFEqual');
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
      _dictionaryValue = _cf.lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
          Pointer<Void> Function(
              Pointer<Void>, Pointer<Void>)>('CFDictionaryGetValue');
  late final _RefWithError _create = _security.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Pointer<Void>>)>('SecKeyCreateRandomKey');
  late final int Function(Pointer<Void>, Pointer<Pointer<Void>>) _copyMatching =
      _security.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
          int Function(
              Pointer<Void>, Pointer<Pointer<Void>>)>('SecItemCopyMatching');
  late final int Function(Pointer<Void>) _delete = _security.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('SecItemDelete');
  late final Pointer<Void> Function(Pointer<Void>) _attributes =
      _security.lookupFunction<Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)>('SecKeyCopyAttributes');
  late final Pointer<Void> Function(Pointer<Void>) _publicKey =
      _security.lookupFunction<Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)>('SecKeyCopyPublicKey');
  late final _RefWithError _external = _security.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>),
      Pointer<Void> Function(Pointer<Void>,
          Pointer<Pointer<Void>>)>('SecKeyCopyExternalRepresentation');
  late final Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>)
      _sign = _security.lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>,
              Pointer<Pointer<Void>>),
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>,
              Pointer<Pointer<Void>>)>('SecKeyCreateSignature');
  late final Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, int, Pointer<Pointer<Void>>) _access =
      _security.lookupFunction<
          Pointer<Void> Function(
              Pointer<Void>, Pointer<Void>, UintPtr, Pointer<Pointer<Void>>),
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int,
              Pointer<Pointer<Void>>)>('SecAccessControlCreateWithFlags');

  Pointer<Void> _constant(String name) =>
      _security.lookup<Pointer<Void>>(name).value;

  Pointer<Void> get _true => _cf.lookup<Pointer<Void>>('kCFBooleanTrue').value;

  Pointer<Void> _map(Map<Pointer<Void>, Pointer<Void>> values) {
    final keys = calloc<Pointer<Void>>(values.length);
    final entries = calloc<Pointer<Void>>(values.length);
    try {
      var i = 0;
      for (final entry in values.entries) {
        keys[i] = entry.key;
        entries[i++] = entry.value;
      }
      return _dictionary(
          nullptr,
          keys,
          entries,
          values.length,
          _cf.lookup<Void>('kCFTypeDictionaryKeyCallBacks'),
          _cf.lookup<Void>('kCFTypeDictionaryValueCallBacks'));
    } finally {
      calloc
        ..free(keys)
        ..free(entries);
    }
  }

  Pointer<Void> _data(List<int> bytes) {
    final buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return _dataCreate(nullptr, buffer, bytes.length);
    } finally {
      calloc.free(buffer);
    }
  }

  Uint8List _copyData(Pointer<Void> data) =>
      Uint8List.fromList(_dataBytes(data).asTypedList(_dataLength(data)));

  Never _fail(String operation, Pointer<Pointer<Void>> error) {
    var code = 0;
    if (error.value != nullptr) {
      code = _cf.lookupFunction<IntPtr Function(Pointer<Void>),
          int Function(Pointer<Void>)>('CFErrorGetCode')(error.value);
    }
    throw StateError('Secure Enclave $operation failed (OS status $code).');
  }

  Uint8List operate(String operation, String reference, List<int>? message) {
    final tag = _data(utf8.encode('dev.onepub.device.$reference'));
    final error = calloc<Pointer<Void>>();
    var key = nullptr.cast<Void>();
    try {
      if (operation == 'create') {
        // kSecAccessControlPrivateKeyUsage = 1 << 30.
        final access = _access(
            nullptr,
            _constant('kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly'),
            1 << 30,
            error);
        if (access == nullptr) {
          _fail('access control creation', error);
        }
        final privateAttributes = _map({
          _constant('kSecAttrIsPermanent'): _true,
          _constant('kSecAttrApplicationTag'): tag,
          _constant('kSecAttrAccessControl'): access,
        });
        final number = calloc<Int32>()..value = 256;
        final bits = _cf.lookupFunction<
                Pointer<Void> Function(Pointer<Void>, IntPtr, Pointer<Void>),
                Pointer<Void> Function(Pointer<Void>, int, Pointer<Void>)>(
            'CFNumberCreate')(nullptr, 3, number.cast()); // kCFNumberSInt32Type
        final attributes = _map({
          _constant('kSecAttrKeyType'):
              _constant('kSecAttrKeyTypeECSECPrimeRandom'),
          _constant('kSecAttrKeySizeInBits'): bits,
          _constant('kSecAttrTokenID'):
              _constant('kSecAttrTokenIDSecureEnclave'),
          _constant('kSecPrivateKeyAttrs'): privateAttributes,
        });
        try {
          key = _create(attributes, error);
        } finally {
          _release(attributes);
          _release(bits);
          calloc.free(number);
          _release(privateAttributes);
          _release(access);
        }
        if (key == nullptr) {
          _fail('key creation', error);
        }
      } else {
        final query = _map({
          _constant('kSecClass'): _constant('kSecClassKey'),
          _constant('kSecAttrApplicationTag'): tag,
          _constant('kSecAttrKeyType'):
              _constant('kSecAttrKeyTypeECSECPrimeRandom'),
          _constant('kSecAttrKeyClass'): _constant('kSecAttrKeyClassPrivate'),
          if (operation != 'delete') _constant('kSecReturnRef'): _true,
        });
        final result = calloc<Pointer<Void>>();
        try {
          final status = operation == 'delete'
              ? _delete(query)
              : _copyMatching(query, result);
          if (status != 0) {
            throw StateError(
                'Secure Enclave $operation failed (OS status $status).');
          }
          if (operation == 'delete') {
            return Uint8List(0);
          }
          key = result.value;
        } finally {
          calloc.free(result);
          _release(query);
        }
      }
      final attributes = _attributes(key);
      if (attributes == nullptr) {
        _fail('reading key attributes', error);
      }
      try {
        final token =
            _dictionaryValue(attributes, _constant('kSecAttrTokenID'));
        if (token == nullptr ||
            _equal(token, _constant('kSecAttrTokenIDSecureEnclave')) == 0) {
          throw StateError('Key is not held by the Secure Enclave.');
        }
      } finally {
        _release(attributes);
      }
      if (operation == 'sign') {
        final input = _data(message!);
        try {
          final signature = _sign(
              key,
              _constant('kSecKeyAlgorithmECDSASignatureMessageX962SHA256'),
              input,
              error);
          if (signature == nullptr) {
            _fail('signing', error);
          }
          try {
            return _copyData(signature);
          } finally {
            _release(signature);
          }
        } finally {
          _release(input);
        }
      }
      final public = _publicKey(key);
      if (public == nullptr) {
        _fail('reading public key', error);
      }
      try {
        final data = _external(public, error);
        if (data == nullptr) {
          _fail('exporting public key', error);
        }
        try {
          return _copyData(data);
        } finally {
          _release(data);
        }
      } finally {
        _release(public);
      }
    } finally {
      if (key != nullptr) {
        _release(key);
      }
      if (error.value != nullptr) {
        _release(error.value);
      }
      calloc.free(error);
      _release(tag);
    }
  }
}

typedef _RefWithError = Pointer<Void> Function(
    Pointer<Void>, Pointer<Pointer<Void>>);
