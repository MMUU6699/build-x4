import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../config/supabase_config.dart';
import 'workspace_runtime.dart';

class DaytonaPtySession implements PtySession {
  DaytonaPtySession({required this.sandboxId, required this.runtime});

  final String sandboxId;
  final DaytonaWorkspaceRuntime runtime;
  final StreamController<Uint8List> _outputController =
      StreamController<Uint8List>.broadcast();
  final Completer<int> _exitCompleter = Completer<int>();

  @override
  Stream<Uint8List> get output => _outputController.stream;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  Future<void> write(Uint8List data) async {
    final command = utf8.decode(data);
    try {
      final res = await runtime.invokeDaytona(
        action: 'shell',
        sandboxId: sandboxId,
        params: {'command': command},
      );
      final stdout = (res['stdout'] as String?) ?? '';
      if (stdout.isNotEmpty) {
        _outputController.add(Uint8List.fromList(utf8.encode(stdout)));
      }
    } catch (e) {
      _outputController.add(Uint8List.fromList(utf8.encode('Error: $e\n')));
    }
  }

  @override
  Future<void> resize(int cols, int rows) async {
    // No-op for HTTP-based Daytona process bridge
  }

  @override
  Future<void> close() async {
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(0);
    }
    await _outputController.close();
  }
}

class DaytonaWorkspaceRuntime implements WorkspaceRuntime {
  DaytonaWorkspaceRuntime({this.defaultSandboxId});

  String? defaultSandboxId;
  final Map<String, bool> _cancelledRuns = <String, bool>{};

  @override
  bool get supportsPty => true;

  @override
  bool get supportsSystemTerminal => false;

  Future<Map<String, dynamic>> invokeDaytona({
    required String action,
    String? sandboxId,
    Map<String, dynamic>? params,
  }) async {
    final client = SupabaseConfig.client;
    final body = <String, dynamic>{
      'action': action,
      'sandboxId': sandboxId ?? defaultSandboxId,
      ...?params,
    };

    final res = await client.functions.invoke(
      'daytona-workspace',
      body: body,
      headers: {
        if (client.auth.currentSession?.accessToken != null)
          'Authorization': 'Bearer ${client.auth.currentSession!.accessToken}',
      },
    );

    if (res.status >= 400) {
      throw Exception('Daytona function error (${res.status}): ${res.data}');
    }

    if (res.data is Map<String, dynamic>) {
      return res.data as Map<String, dynamic>;
    } else if (res.data is String) {
      try {
        return jsonDecode(res.data as String) as Map<String, dynamic>;
      } catch (_) {
        return {'data': res.data};
      }
    }
    return <String, dynamic>{};
  }

  @override
  Future<RuntimeStatus> status() async {
    return const RuntimeStatus(
      ready: true,
      reason: null,
      engine: 'daytona',
      sandboxed: true,
    );
  }

  @override
  Stream<CommandEvent> run(CommandRequest request) async* {
    _cancelledRuns[request.runId] = false;
    yield const CommandStarted(pid: 1);

    final stopwatch = Stopwatch()..start();
    try {
      if (request.isCancelled?.call() == true ||
          _cancelledRuns[request.runId] == true) {
        yield CommandExited(
          exitCode: 130,
          timedOut: false,
          cancelled: true,
          interrupted: false,
          duration: stopwatch.elapsed,
        );
        return;
      }

      final res = await invokeDaytona(
        action: 'shell',
        params: {
          'command': request.command,
          'cwd': request.cwd,
          'env': request.env,
          'timeout': request.timeout.inSeconds,
        },
      );

      final stdout = (res['stdout'] as String?) ?? '';
      final stderr = (res['stderr'] as String?) ?? '';
      final exitCode = (res['exitCode'] as int?) ?? 0;

      if (stdout.isNotEmpty) {
        yield CommandOutput(
          OutputStreamKind.stdout,
          Uint8List.fromList(utf8.encode(stdout)),
        );
      }

      if (stderr.isNotEmpty) {
        yield CommandOutput(
          OutputStreamKind.stderr,
          Uint8List.fromList(utf8.encode(stderr)),
        );
      }

      yield CommandExited(
        exitCode: exitCode,
        timedOut: false,
        cancelled: _cancelledRuns[request.runId] == true,
        interrupted: false,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      yield CommandOutput(
        OutputStreamKind.stderr,
        Uint8List.fromList(utf8.encode('Daytona execution error: $e\n')),
      );
      yield CommandExited(
        exitCode: 1,
        timedOut: false,
        cancelled: false,
        interrupted: false,
        duration: stopwatch.elapsed,
      );
    } finally {
      stopwatch.stop();
      _cancelledRuns.remove(request.runId);
    }
  }

  @override
  Future<void> cancel(String runId) async {
    _cancelledRuns[runId] = true;
  }

  @override
  Future<PtySession> openPty({
    required List<Mount> mounts,
    required String cwd,
    required Map<String, String> env,
    required int cols,
    required int rows,
  }) async {
    return DaytonaPtySession(sandboxId: defaultSandboxId ?? '', runtime: this);
  }

  // File system & sandbox tools
  Future<String> readFile(String path, {String? sandboxId}) async {
    final res = await invokeDaytona(
      action: 'read_file',
      sandboxId: sandboxId,
      params: {'path': path},
    );
    return (res['content'] as String?) ?? '';
  }

  Future<void> writeFile(
    String path,
    String content, {
    String? sandboxId,
  }) async {
    await invokeDaytona(
      action: 'write_file',
      sandboxId: sandboxId,
      params: {'path': path, 'content': content},
    );
  }

  Future<String> editFile(
    String path, {
    String? targetContent,
    String? replacementContent,
    String? content,
    String? sandboxId,
  }) async {
    final res = await invokeDaytona(
      action: 'edit_file',
      sandboxId: sandboxId,
      params: {
        'path': path,
        'targetContent': targetContent,
        'replacementContent': replacementContent,
        'content': content,
      },
    );
    return (res['newContent'] as String?) ?? '';
  }

  Future<List<dynamic>> listDir(String path, {String? sandboxId}) async {
    final res = await invokeDaytona(
      action: 'list_dir',
      sandboxId: sandboxId,
      params: {'path': path},
    );
    return (res['files'] as List<dynamic>?) ?? <dynamic>[];
  }

  Future<List<String>> glob(
    String pattern, {
    String? path,
    String? sandboxId,
  }) async {
    final res = await invokeDaytona(
      action: 'glob',
      sandboxId: sandboxId,
      params: {'pattern': pattern, 'path': path},
    );
    final matches = res['matches'] as List<dynamic>?;
    return matches?.map((e) => e.toString()).toList() ?? <String>[];
  }

  Future<List<String>> grep(
    String query, {
    String? path,
    String? sandboxId,
  }) async {
    final res = await invokeDaytona(
      action: 'grep',
      sandboxId: sandboxId,
      params: {'query': query, 'path': path},
    );
    final matches = res['matches'] as List<dynamic>?;
    return matches?.map((e) => e.toString()).toList() ?? <String>[];
  }

  Future<String> createSandbox({
    String language = 'typescript',
    Map<String, dynamic>? envVars,
  }) async {
    final res = await invokeDaytona(
      action: 'create_sandbox',
      params: {'language': language, 'envVars': envVars},
    );
    final sId = res['sandboxId'] as String;
    defaultSandboxId = sId;
    return sId;
  }

  Future<void> startSandbox(String sandboxId) async {
    await invokeDaytona(action: 'start_sandbox', sandboxId: sandboxId);
  }

  Future<void> stopSandbox(String sandboxId) async {
    await invokeDaytona(action: 'stop_sandbox', sandboxId: sandboxId);
  }

  Future<void> deleteSandbox(String sandboxId) async {
    await invokeDaytona(action: 'delete_sandbox', sandboxId: sandboxId);
    if (defaultSandboxId == sandboxId) {
      defaultSandboxId = null;
    }
  }

  @override
  Future<void> openInSystemTerminal(String hostDir) async {}

  @override
  Future<void> revealInFileManager(String hostPath) async {}
}
