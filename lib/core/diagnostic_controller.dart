import 'dart:io';

import '../services/diagnostic_transfer.dart';
import 'app_controller.dart';
import 'diagnostics.dart';

extension AppDiagnosticActions on AppController {
  DiagnosticTransfer get _diagnosticTransfer => DiagnosticTransfer(
    directory: Directory('${store.root}/diagnostic-transfer'),
    readSecret: secrets.read,
    writeSecret: secrets.write,
  );

  Future<DiagnosticUploadConfig> loadDiagnosticUploadConfig() async {
    final config = await _diagnosticTransfer.loadConfig();
    diagnostics.registerCredentials([config.token]);
    return config;
  }

  Future<void> saveDiagnosticUploadConfig(String endpoint, String token) async {
    diagnostics.registerCredentials([token]);
    await _diagnosticTransfer.saveConfig(endpoint, token);
  }

  Future<DiagnosticBundle> prepareDiagnosticBundle(
    DiagnosticSelection selection,
  ) async {
    final generation = diagnostics.generation;
    Map<String, Object?> environment;
    try {
      environment = await native.diagnosticEnvironment();
    } catch (error) {
      environment = const {
        'platform': 'unknown',
        'networkType': 'unknown',
        'vpnActive': 'unknown',
      };
      diagnostics.log(
        DiagnosticLevel.warn,
        'diagnostics',
        'environment_unavailable',
        error: error,
        contextGeneration: generation,
      );
    }
    if (generation != diagnostics.generation) throw const DiagnosticCancelled();
    final bundle = await _diagnosticTransfer.createBundle(
      diagnostics,
      selection,
      environment: {...environment, 'dartVersion': Platform.version},
    );
    if (generation != diagnostics.generation) {
      await _diagnosticTransfer.clearPending();
      throw const DiagnosticCancelled();
    }
    return bundle;
  }

  Future<DiagnosticBundle?> pendingDiagnosticBundle() =>
      _diagnosticTransfer.loadPending();

  Future<void> uploadDiagnosticBundle(DiagnosticBundle bundle) =>
      diagnostics.runTask<void>(
        type: 'diagnosticUpload',
        title: '上传诊断包',
        body: () async {
          final config = await loadDiagnosticUploadConfig();
          DiagnosticScope.log(
            DiagnosticLevel.info,
            'diagnostics',
            'upload_started',
            data: {'reportId': bundle.reportId, 'bytes': bundle.bytes.length},
          );
          try {
            await _diagnosticTransfer.upload(bundle, config);
            DiagnosticScope.log(
              DiagnosticLevel.info,
              'diagnostics',
              'upload_completed',
              data: {'reportId': bundle.reportId},
            );
          } catch (error, stack) {
            DiagnosticScope.log(
              DiagnosticLevel.error,
              'diagnostics',
              'upload_failed',
              error: error,
              stackTrace: stack,
            );
            rethrow;
          }
        },
      );

  Future<void> clearAppDiagnostics() async {
    diagnostics.clear();
    await _diagnosticTransfer.clearPending();
  }
}
