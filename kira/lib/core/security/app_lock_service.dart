/// App-level lock screen backed by biometric authentication and/or a
/// user-chosen PIN.
///
/// Uses the [local_auth] plugin to query device capabilities and perform
/// biometric checks.  The PIN hash is stored in [FlutterSecureStorage] so it
/// never leaves the platform keystore.
///
/// Typical usage:
/// ```dart
/// final lock = AppLockService();
/// if (await lock.isEnabled) {
///   final ok = await lock.authenticate(reason: 'Unlock Kira');
///   if (!ok) exit(0);
/// }
/// ```
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Keys used in [FlutterSecureStorage] for lock-related state.
abstract final class _Keys {
  static const lockEnabled = 'kira_app_lock_enabled';
  static const pinHash = 'kira_app_lock_pin_hash';
  static const biometricEnabled = 'kira_app_lock_biometric';
  static const failedAttempts = 'kira_app_lock_failed_attempts';
  static const lockoutUntil = 'kira_app_lock_lockout_until';
}

class AppLockService {
  AppLockService({
    LocalAuthentication? localAuth,
    FlutterSecureStorage? secureStorage,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        _storage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility:
                    KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _storage;

  /// Maximum consecutive failed PIN attempts before a timed lockout.
  static const int maxFailedAttempts = 5;

  /// Duration of the lockout after [maxFailedAttempts] failures.
  static const Duration lockoutDuration = Duration(minutes: 5);

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Whether any form of app lock (PIN or biometric) is currently enabled.
  Future<bool> get isEnabled async {
    final value = await _storage.read(key: _Keys.lockEnabled);
    return value == 'true';
  }

  /// Whether the device supports biometric authentication.
  Future<bool> get isBiometricAvailable async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Returns the list of enrolled biometric types on this device.
  Future<List<BiometricType>> get availableBiometrics async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  /// Whether the user has opted in to biometric unlock.
  Future<bool> get isBiometricEnabled async {
    final value = await _storage.read(key: _Keys.biometricEnabled);
    return value == 'true';
  }

  /// Whether the user has set a PIN.
  Future<bool> get isPinSet async {
    final hash = await _storage.read(key: _Keys.pinHash);
    return hash != null && hash.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Enable / disable
  // ---------------------------------------------------------------------------

  /// Sets a PIN and enables the app lock.
  ///
  /// The PIN is hashed with SHA-256 before storage -- we never persist the
  /// cleartext value.
  Future<void> enableWithPin(String pin) async {
    if (pin.length < 4) {
      throw AppLockException('PIN must be at least 4 digits.');
    }
    final hash = _hashPin(pin);
    await _storage.write(key: _Keys.pinHash, value: hash);
    await _storage.write(key: _Keys.lockEnabled, value: 'true');
    await _resetFailedAttempts();
  }

  /// Enables biometric authentication (requires a PIN to be set first as a
  /// fallback).
  Future<void> enableBiometric() async {
    if (!(await isPinSet)) {
      throw AppLockException(
        'A PIN must be set before enabling biometric unlock.',
      );
    }
    if (!(await isBiometricAvailable)) {
      throw AppLockException(
        'Biometric authentication is not available on this device.',
      );
    }
    await _storage.write(key: _Keys.biometricEnabled, value: 'true');
    await _storage.write(key: _Keys.lockEnabled, value: 'true');
  }

  /// Disables biometric unlock (PIN remains active).
  Future<void> disableBiometric() async {
    await _storage.write(key: _Keys.biometricEnabled, value: 'false');
  }

  /// Disables the app lock entirely, removing the stored PIN.
  Future<void> disable() async {
    await Future.wait([
      _storage.delete(key: _Keys.lockEnabled),
      _storage.delete(key: _Keys.pinHash),
      _storage.delete(key: _Keys.biometricEnabled),
      _storage.delete(key: _Keys.failedAttempts),
      _storage.delete(key: _Keys.lockoutUntil),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Authenticate
  // ---------------------------------------------------------------------------

  /// Attempts biometric authentication.
  ///
  /// Returns `true` on success.  Does **not** fall back to PIN -- the caller
  /// should display the PIN entry UI when this returns `false`.
  Future<bool> authenticateWithBiometric({
    required String reason,
  }) async {
    if (!(await isBiometricEnabled)) return false;
    if (await _isLockedOut()) return false;

    try {
      final success = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (success) {
        await _resetFailedAttempts();
      }
      return success;
    } catch (_) {
      return false;
    }
  }

  /// Validates a user-entered PIN.
  ///
  /// Returns `true` on success.  After [maxFailedAttempts] consecutive
  /// failures the account is temporarily locked out for [lockoutDuration].
  Future<bool> authenticateWithPin(String pin) async {
    if (await _isLockedOut()) {
      throw AppLockException(
        'Too many failed attempts. Please wait before trying again.',
      );
    }

    final storedHash = await _storage.read(key: _Keys.pinHash);
    if (storedHash == null) {
      throw AppLockException('No PIN has been set.');
    }

    final inputHash = _hashPin(pin);
    if (inputHash == storedHash) {
      await _resetFailedAttempts();
      return true;
    }

    await _incrementFailedAttempts();
    return false;
  }

  /// Convenience method that tries biometric first, then falls back to
  /// returning `false` so the caller can show the PIN screen.
  Future<bool> authenticate({required String reason}) async {
    if (!(await isEnabled)) return true; // Lock not active -- allow through.

    if (await isBiometricEnabled) {
      final biometricOk = await authenticateWithBiometric(reason: reason);
      if (biometricOk) return true;
    }

    // Caller should show PIN entry.
    return false;
  }

  // ---------------------------------------------------------------------------
  // PIN change
  // ---------------------------------------------------------------------------

  /// Changes the PIN.  Requires the current PIN for verification.
  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final ok = await authenticateWithPin(currentPin);
    if (!ok) {
      throw AppLockException('Current PIN is incorrect.');
    }
    if (newPin.length < 4) {
      throw AppLockException('New PIN must be at least 4 digits.');
    }
    final hash = _hashPin(newPin);
    await _storage.write(key: _Keys.pinHash, value: hash);
  }

  // ---------------------------------------------------------------------------
  // Lockout helpers
  // ---------------------------------------------------------------------------

  Future<bool> _isLockedOut() async {
    final until = await _storage.read(key: _Keys.lockoutUntil);
    if (until == null) return false;
    final lockoutEnd = DateTime.tryParse(until);
    if (lockoutEnd == null) return false;
    return DateTime.now().toUtc().isBefore(lockoutEnd);
  }

  Future<void> _incrementFailedAttempts() async {
    final raw = await _storage.read(key: _Keys.failedAttempts);
    final current = int.tryParse(raw ?? '0') ?? 0;
    final next = current + 1;
    await _storage.write(key: _Keys.failedAttempts, value: next.toString());

    if (next >= maxFailedAttempts) {
      final lockoutEnd =
          DateTime.now().toUtc().add(lockoutDuration).toIso8601String();
      await _storage.write(key: _Keys.lockoutUntil, value: lockoutEnd);
    }
  }

  Future<void> _resetFailedAttempts() async {
    await _storage.delete(key: _Keys.failedAttempts);
    await _storage.delete(key: _Keys.lockoutUntil);
  }

  // ---------------------------------------------------------------------------
  // Hashing
  // ---------------------------------------------------------------------------

  /// Derives a SHA-256 hex digest from the raw PIN string.
  ///
  /// In a production deployment this would use a proper password KDF such as
  /// Argon2id, but SHA-256 is acceptable here because:
  ///   1. The hash is stored in the platform keystore (already encrypted).
  ///   2. The PIN is short-lived and used only to gate UI access, not to
  ///      derive encryption keys.
  static String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

class AppLockException implements Exception {
  final String message;
  const AppLockException(this.message);

  @override
  String toString() => 'AppLockException: $message';
}
