import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/preferences/app_preferences.dart';
import '../../../core/services/workspace/work_event_persistence_service.dart';
import '../models/work_task_result.dart';
import '../models/work_tool_event.dart';
import '../models/work_turn.dart';
import '../services/manus_agent_loop_service.dart';

enum AppMode {
  chat,
  work;

  bool get isChat => this == AppMode.chat;
  bool get isWork => this == AppMode.work;
}

enum WorkSessionPhase {
  idle,
  running,
  waiting,
  completed,
  error;

  bool get isBusy => this == WorkSessionPhase.running;
  bool get isRunning => this == WorkSessionPhase.running;
  bool get isWaiting => this == WorkSessionPhase.waiting;
  bool get isCompleted => this == WorkSessionPhase.completed;
  bool get isIdle => this == WorkSessionPhase.idle;
}

/// Owns the Work thread: one [WorkTurn] per user prompt, live events, the
/// computer panel selection, and persisted history.
class WorkSessionProvider extends ChangeNotifier {
  WorkSessionProvider({
    ManusAgentLoopService? agentService,
    this.preferences,
    WorkEventPersistenceService? persistenceService,
  }) : _agentService = agentService ?? ManusAgentLoopService(),
       _persistence = persistenceService ?? const WorkEventPersistenceService();

  final ManusAgentLoopService _agentService;
  final AppPreferences? preferences;
  final WorkEventPersistenceService _persistence;

  static const String _prefModeKey = 'app_active_mode_v1';

  AppMode _mode = AppMode.chat;
  AppMode get mode => _mode;
  bool get isWorkMode => _mode == AppMode.work;

  WorkSessionPhase _phase = WorkSessionPhase.idle;
  WorkSessionPhase get phase => _phase;

  bool get isAgentRunning => _phase == WorkSessionPhase.running;
  bool get isBusy => _phase.isBusy;

  final List<WorkTurn> _turns = [];
  List<WorkTurn> get turns => List.unmodifiable(_turns);

  WorkTurn? get currentTurn => _turns.isEmpty ? null : _turns.last;

  bool get showThinking {
    final turn = currentTurn;
    if (_phase != WorkSessionPhase.running || turn == null) return false;
    return !turn.events.any(
      (event) => event.status == 'running' || event.status == 'calling',
    );
  }

  String? _currentThinking;
  String? get currentThinking => _currentThinking;

  bool _startingComputer = false;
  bool get isStartingComputer => _startingComputer;

  String? get notifyMessage => currentTurn?.introMessage;
  String? get errorMessage => currentTurn?.error;
  int get workedDurationSeconds => currentTurn?.durationSeconds ?? 0;
  WorkTaskResult? get taskResult => currentTurn?.result;
  String? get lastPrompt => currentTurn?.prompt;
  String? get pendingToolCallId => currentTurn?.pendingToolCallId;

  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  bool _isComputerOpen = false;
  bool get isComputerOpen => _isComputerOpen;

  String? _computerTurnId;
  String? _computerEventId;

  WorkTurn? get computerTurn {
    if (_turns.isEmpty) return null;
    final id = _computerTurnId;
    if (id == null) return _turns.last;
    for (final turn in _turns) {
      if (turn.id == id) return turn;
    }
    return _turns.last;
  }

  WorkToolEvent? get computerEvent {
    final turn = computerTurn;
    if (turn == null || turn.events.isEmpty) return null;
    final id = _computerEventId;
    if (id != null) {
      for (final event in turn.events) {
        if (event.id == id) return event;
      }
    }
    return turn.events.last;
  }

  WorkToolEvent? get currentEvent => computerEvent;

  final Map<String, String> _signedScreenshotUrls = {};

  /// Screenshot URL for the live session, or a signed URL for persisted turns.
  /// Returns null while signing is in flight or when the file is unavailable.
  String? screenshotUrlFor(WorkToolEvent event) {
    final live = event.screenshotUrl;
    if (live != null && live.isNotEmpty) return live;
    final path = event.screenshotPath;
    if (path == null || path.isEmpty) return null;
    return _signedScreenshotUrls[path];
  }

  CancelToken? _cancelToken;
  StreamSubscription<ManusAgentEvent>? _agentSubscription;
  Timer? _saveDebounce;
  int _turnSequence = 0;

  String _daytonaStatus = 'unknown';
  String get daytonaStatus => _daytonaStatus;

  String _supabaseStatus = 'unknown';
  String get supabaseStatus => _supabaseStatus;

  bool get isDaytonaConnected => _daytonaStatus == 'connected';
  bool get daytonaUnavailable => _daytonaStatus == 'disconnected';
  bool get daytonaChecking => _daytonaStatus == 'unknown';

  /// Work needs a real account: anonymous guest sessions must not own a
  /// sandbox, screenshots, or persisted turns.
  bool get isSignedInForWork {
    if (SupabaseConfig.isUnconfigured) return true;
    final user = SupabaseConfig.currentUser;
    return user != null && !user.isAnonymous;
  }

  /// Leave the anonymous guest session so the auth gate shows the sign-in page.
  Future<void> signInForWork() async {
    if (SupabaseConfig.isUnconfigured) return;
    try {
      await SupabaseConfig.client.auth.signOut();
    } finally {
      await SupabaseConfig.disableGuestMode();
    }
    notifyListeners();
  }

  Future<void> refreshIntegrations() async {
    final configured = !SupabaseConfig.isUnconfigured;
    final user = SupabaseConfig.currentUser;

    if (!configured) {
      _supabaseStatus = 'not_configured';
      _daytonaStatus = 'not_configured';
    } else if (user == null) {
      _supabaseStatus = 'signed_out';
      _daytonaStatus = 'signed_out';
    } else if (user.isAnonymous) {
      _supabaseStatus = 'anonymous';
      _daytonaStatus = 'signed_out';
    } else {
      _supabaseStatus = 'connected';
      try {
        final health = await _agentService.checkComputerHealth();
        _daytonaStatus = health['status']?.toString() ?? 'disconnected';
      } catch (e) {
        debugPrint('[WorkSessionProvider] computer health check failed: $e');
        _daytonaStatus = 'disconnected';
      }
    }

    await _persistence.recordIntegrationStatus(
      provider: 'supabase',
      status: _supabaseStatus,
      details: switch (_supabaseStatus) {
        'connected' => 'Authenticated user session',
        'anonymous' => 'Anonymous guest session',
        'signed_out' => 'No active session',
        _ => 'Supabase is not configured',
      },
    );
    if (!configured || user == null || user.isAnonymous) {
      await _persistence.recordIntegrationStatus(
        provider: 'daytona',
        status: _daytonaStatus,
        details: 'Work requires a signed-in account',
      );
    }
    notifyListeners();
  }

  void initFromPreferences() {
    final savedMode = preferences?.getString(_prefModeKey);
    if (savedMode == 'work') {
      _mode = AppMode.work;
      unawaited(refreshIntegrations());
      notifyListeners();
    }
  }

  void setMode(AppMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    preferences?.setString(_prefModeKey, newMode.name);
    if (newMode.isWork) {
      unawaited(refreshIntegrations());
    }
    notifyListeners();
  }

  void toggleMode() {
    setMode(_mode == AppMode.chat ? AppMode.work : AppMode.chat);
  }

  void openComputer({String? turnId, String? eventId}) {
    _computerTurnId = turnId;
    _computerEventId = eventId;
    _isComputerOpen = true;
    notifyListeners();
  }

  void closeComputer() {
    _isComputerOpen = false;
    _computerTurnId = null;
    _computerEventId = null;
    notifyListeners();
  }

  Future<void> loadSessionForConversation(String conversationId) async {
    if (conversationId == _activeConversationId && _turns.isNotEmpty) return;
    if (_phase == WorkSessionPhase.running) {
      await cancelWorkTask();
    }
    _activeConversationId = conversationId;
    _turns.clear();
    _computerTurnId = null;
    _computerEventId = null;
    _currentThinking = null;
    _phase = WorkSessionPhase.idle;
    notifyListeners();

    final loaded = await _persistence.fetchWorkTurns(conversationId);
    if (loaded.isEmpty) return;

    for (final turn in loaded) {
      _turns.add(_normalizeLoadedTurn(turn));
    }
    _phase = _phaseForTurn(_turns.last);
    for (final turn in _turns) {
      for (final event in turn.events) {
        final path = event.screenshotPath;
        if (path != null && path.isNotEmpty) {
          unawaited(_signScreenshot(path));
        }
      }
    }
    notifyListeners();
  }

  WorkTurn _normalizeLoadedTurn(WorkTurn turn) {
    if (turn.status != 'running') return turn;
    return turn.copyWith(
      status: 'error',
      error: 'The app closed before this task finished. Send it again.',
    );
  }

  WorkSessionPhase _phaseForTurn(WorkTurn turn) {
    return switch (turn.status) {
      'running' => WorkSessionPhase.running,
      'waiting' => WorkSessionPhase.waiting,
      'completed' => WorkSessionPhase.completed,
      'error' || 'stopped' => WorkSessionPhase.error,
      _ => WorkSessionPhase.idle,
    };
  }

  Future<void> startWorkTask(String conversationId, String prompt) async {
    if (_phase == WorkSessionPhase.running) {
      await cancelWorkTask();
    }

    _saveDebounce?.cancel();
    _agentSubscription?.cancel();
    _activeConversationId = conversationId;
    _phase = WorkSessionPhase.running;
    _currentThinking = null;
    _computerTurnId = null;
    _computerEventId = null;

    final turn = WorkTurn(
      id: 'turn_${DateTime.now().microsecondsSinceEpoch}_${_turnSequence++}',
      conversationId: conversationId,
      prompt: prompt,
      status: 'running',
      startedAt: DateTime.now(),
    );
    _turns.add(turn);
    notifyListeners();

    unawaited(_persistence.saveWorkTurn(turn));
    unawaited(
      _persistence.updateWorkSession(
        conversationId: conversationId,
        phase: 'running',
        startedAt: turn.startedAt,
      ),
    );

    _cancelToken = CancelToken();
    final eventStream = _agentService.runAgentLoop(
      conversationId: conversationId,
      userRequest: prompt,
      cancelToken: _cancelToken,
    );

    _agentSubscription = eventStream.listen(
      (event) => _handleAgentEvent(event, turn.id),
      onError: (Object err) {
        _finishWithError(turn.id, err.toString());
      },
      onDone: () {
        final active = _turnById(turn.id);
        if (active == null) return;
        if (active.status == 'running') {
          _finishWithError(
            turn.id,
            'The task ended without a final result. Nothing was reported as '
            'completed.',
          );
        } else {
          _currentThinking = null;
          notifyListeners();
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> resumeWorkTaskWithUserAnswer(String answer) async {
    final turn = currentTurn;
    final cid = _activeConversationId;
    final toolCallId = turn?.pendingToolCallId;
    if (turn == null ||
        cid == null ||
        toolCallId == null ||
        toolCallId.isEmpty ||
        turn.status != 'waiting') {
      return;
    }

    _phase = WorkSessionPhase.running;
    _currentThinking = 'Resuming task...';
    _updateTurn(turn.copyWith(status: 'running', pendingToolCallId: ''));
    notifyListeners();

    _cancelToken = CancelToken();
    final eventStream = _agentService.runAgentLoop(
      conversationId: cid,
      userRequest: answer,
      cancelToken: _cancelToken,
      pendingToolCallId: toolCallId,
    );

    _agentSubscription = eventStream.listen(
      (event) => _handleAgentEvent(event, turn.id),
      onError: (Object err) {
        _finishWithError(turn.id, err.toString());
      },
      onDone: () {
        final active = _turnById(turn.id);
        if (active != null && active.status == 'running') {
          _finishWithError(
            turn.id,
            'The task ended without a final result. Nothing was reported as '
            'completed.',
          );
        }
      },
      cancelOnError: false,
    );
  }

  void _handleAgentEvent(ManusAgentEvent event, String turnId) {
    final turn = _turnById(turnId);
    if (turn == null) return;

    if (event is ManusStartingEvent) {
      _currentThinking = null;
      _startingComputer = true;
      notifyListeners();
      return;
    }

    _startingComputer = false;

    if (event is ManusThinkingEvent) {
      _currentThinking = event.text;
      notifyListeners();
      return;
    }

    if (event is ManusToolStartedEvent) {
      _currentThinking = event.toolEvent.brief;
      final events = _upsertEvent(turn.events, event.toolEvent);
      _updateTurn(turn.copyWith(events: events));
      notifyListeners();
      return;
    }

    if (event is ManusToolFinishedEvent) {
      final events = _upsertEvent(turn.events, event.toolEvent);
      _updateTurn(turn.copyWith(events: events));
      final path = event.toolEvent.screenshotPath;
      if (path != null && path.isNotEmpty) {
        unawaited(_signScreenshot(path));
      }
      _queueSave();
      notifyListeners();
      return;
    }

    if (event is ManusMessageNotifyEvent) {
      _currentThinking = event.message;
      _updateTurn(turn.copyWith(introMessage: event.message));
      _queueSave();
      notifyListeners();
      return;
    }

    if (event is ManusMessageAskEvent) {
      _phase = WorkSessionPhase.waiting;
      _currentThinking = event.question;
      _updateTurn(
        turn.copyWith(
          status: 'waiting',
          question: event.question,
          pendingToolCallId: event.toolCallId,
        ),
      );
      _flushTurnSave();
      unawaited(
        _persistence.updateWorkSession(
          conversationId: turn.conversationId,
          phase: 'waiting',
        ),
      );
      notifyListeners();
      return;
    }

    if (event is ManusTaskCompletedEvent) {
      _phase = WorkSessionPhase.completed;
      _currentThinking = null;
      final duration = DateTime.now().difference(turn.startedAt).inSeconds;
      _updateTurn(
        turn.copyWith(
          status: 'completed',
          finalAnswer: event.result.summary,
          result: event.result,
          durationSeconds: duration < 1 ? 1 : duration,
          pendingToolCallId: '',
        ),
      );
      _flushTurnSave();
      unawaited(
        _persistence.updateWorkSession(
          conversationId: turn.conversationId,
          phase: 'completed',
          endedAt: DateTime.now(),
        ),
      );
      notifyListeners();
      return;
    }

    if (event is ManusErrorEvent) {
      _finishWithError(turnId, event.error);
    }
  }

  List<WorkToolEvent> _upsertEvent(
    List<WorkToolEvent> events,
    WorkToolEvent next,
  ) {
    final index = events.indexWhere((event) => event.id == next.id);
    if (index == -1) return [...events, next];
    final updated = List<WorkToolEvent>.from(events);
    updated[index] = next;
    return updated;
  }

  void _finishWithError(String turnId, String error) {
    final turn = _turnById(turnId);
    if (turn == null) return;
    _phase = WorkSessionPhase.error;
    _currentThinking = null;
    final duration = DateTime.now().difference(turn.startedAt).inSeconds;
    _updateTurn(
      turn.copyWith(
        status: 'error',
        error: error,
        durationSeconds: duration < 1 ? 1 : duration,
      ),
    );
    _flushTurnSave();
    unawaited(
      _persistence.updateWorkSession(
        conversationId: turn.conversationId,
        phase: 'error',
        endedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  WorkTurn? _turnById(String id) {
    for (final turn in _turns) {
      if (turn.id == id) return turn;
    }
    return null;
  }

  void _updateTurn(WorkTurn next) {
    final index = _turns.indexWhere((turn) => turn.id == next.id);
    if (index == -1) return;
    _turns[index] = next;
  }

  void _queueSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      final turn = currentTurn;
      if (turn != null) unawaited(_persistence.saveWorkTurn(turn));
    });
  }

  void _flushTurnSave() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    final turn = currentTurn;
    if (turn != null) unawaited(_persistence.saveWorkTurn(turn));
  }

  Future<void> _signScreenshot(String path) async {
    if (_signedScreenshotUrls.containsKey(path)) return;
    final url = await _persistence.createScreenshotUrl(path);
    if (url == null || url.isEmpty) return;
    _signedScreenshotUrls[path] = url;
    notifyListeners();
  }

  Future<void> cancelWorkTask() async {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('User stopped task');
    }
    await _agentSubscription?.cancel();
    _agentSubscription = null;

    final turn = currentTurn;
    if (turn != null && turn.status == 'running') {
      _updateTurn(
        turn.copyWith(
          status: 'stopped',
          error: 'Stopped by you.',
          pendingToolCallId: '',
        ),
      );
      _flushTurnSave();
    }
    _phase = WorkSessionPhase.idle;
    _currentThinking = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _agentSubscription?.cancel();
    _cancelToken?.cancel();
    super.dispose();
  }
}
