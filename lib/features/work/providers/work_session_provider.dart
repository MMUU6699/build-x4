import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/preferences/app_preferences.dart';
import '../../../core/services/workspace/work_event_persistence_service.dart';
import '../models/work_plan.dart';
import '../models/work_task_result.dart';
import '../models/work_tool_event.dart';
import '../services/manus_agent_loop_service.dart';
import '../../home/controllers/chat_controller.dart';

enum AppMode {
  chat,
  work;

  bool get isChat => this == AppMode.chat;
  bool get isWork => this == AppMode.work;
}

enum WorkSessionPhase {
  idle,
  pending,
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

  /// In ai-manus useSessionPhase.ts:
  /// showThinking is true ONLY when phase is running AND no tool currently has status 'running'/'calling'
  bool get showThinking {
    if (_phase != WorkSessionPhase.running) return false;
    final hasCallingTool = _timelineEvents.any(
      (e) => e.status == 'running' || e.status == 'calling',
    );
    return !hasCallingTool;
  }

  WorkPlan? _activePlan;
  WorkPlan? get activePlan => _activePlan;

  String? _currentThinking;
  String? get currentThinking => _currentThinking;

  final List<WorkToolEvent> _timelineEvents = [];
  List<WorkToolEvent> get timelineEvents => List.unmodifiable(_timelineEvents);

  int? _scrubbedIndex;
  int? get scrubbedIndex => _scrubbedIndex;

  bool _isComputerOpen = false;
  bool get isComputerOpen => _isComputerOpen;

  WorkTaskResult? _taskResult;
  WorkTaskResult? get taskResult => _taskResult;

  DateTime? _taskStartTime;
  int _workedDurationSeconds = 0;
  int get workedDurationSeconds => _workedDurationSeconds;

  String? _notifyMessage;
  String? get notifyMessage => _notifyMessage;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _lastPrompt;
  String? get lastPrompt => _lastPrompt;

  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  String? _pendingToolCallId;
  String? get pendingToolCallId => _pendingToolCallId;

  List<Map<String, dynamic>> _pendingMessages = [];
  List<Map<String, dynamic>> get pendingMessages =>
      List.unmodifiable(_pendingMessages);

  CancelToken? _cancelToken;
  StreamSubscription<ManusAgentEvent>? _agentSubscription;

  bool get isLive =>
      _scrubbedIndex == null ||
      _timelineEvents.isEmpty ||
      _scrubbedIndex == (_timelineEvents.length - 1);

  String _daytonaStatus = 'connected';
  String get daytonaStatus => _daytonaStatus;

  String _supabaseStatus = 'connected';
  String get supabaseStatus => _supabaseStatus;

  bool get isDaytonaConnected => _daytonaStatus == 'connected';

  Future<void> refreshIntegrations() async {
    final daytona = await _persistence.fetchIntegrationStatus('daytona');
    if (daytona != null && daytona['status'] != null) {
      _daytonaStatus = daytona['status'].toString();
    }
    _supabaseStatus = SupabaseConfig.isUnconfigured
        ? 'disconnected'
        : 'connected';
    notifyListeners();
  }

  WorkToolEvent? get currentEvent {
    if (_timelineEvents.isEmpty) return null;
    if (_scrubbedIndex != null &&
        _scrubbedIndex! >= 0 &&
        _scrubbedIndex! < _timelineEvents.length) {
      return _timelineEvents[_scrubbedIndex!];
    }
    return _timelineEvents.last;
  }

  void initFromPreferences() {
    final savedMode = preferences?.getString(_prefModeKey);
    if (savedMode == 'work') {
      _mode = AppMode.work;
      refreshIntegrations();
      notifyListeners();
    }
  }

  void setMode(AppMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    preferences?.setString(_prefModeKey, newMode.name);
    if (newMode.isWork) {
      refreshIntegrations();
    }
    notifyListeners();
  }

  void toggleMode() {
    setMode(_mode == AppMode.chat ? AppMode.work : AppMode.chat);
  }

  void openComputer({int? eventIndex}) {
    _isComputerOpen = true;
    if (eventIndex != null &&
        eventIndex >= 0 &&
        eventIndex < _timelineEvents.length) {
      _scrubbedIndex = eventIndex;
    }
    notifyListeners();
  }

  void closeComputer() {
    _isComputerOpen = false;
    notifyListeners();
  }

  void toggleComputer() {
    _isComputerOpen = !_isComputerOpen;
    notifyListeners();
  }

  void scrubTo(int index) {
    if (index >= 0 && index < _timelineEvents.length) {
      _scrubbedIndex = index;
      notifyListeners();
    }
  }

  void jumpToLive() {
    _scrubbedIndex = null;
    notifyListeners();
  }

  void skipBack() {
    if (_timelineEvents.isEmpty) return;
    final currentIndex = _scrubbedIndex ?? (_timelineEvents.length - 1);
    if (currentIndex > 0) {
      scrubTo(currentIndex - 1);
    }
  }

  void skipForward() {
    if (_timelineEvents.isEmpty) return;
    final currentIndex = _scrubbedIndex ?? (_timelineEvents.length - 1);
    if (currentIndex < _timelineEvents.length - 1) {
      scrubTo(currentIndex + 1);
    } else {
      jumpToLive();
    }
  }

  Future<void> loadSessionForConversation(String conversationId) async {
    _activeConversationId = conversationId;
    _timelineEvents.clear();
    _activePlan = null;
    _taskResult = null;
    _scrubbedIndex = null;
    _currentThinking = null;
    _pendingToolCallId = null;
    _pendingMessages.clear();
    _phase = WorkSessionPhase.idle;
    notifyListeners();

    try {
      final events = await _persistence.fetchToolEvents(conversationId);
      if (events.isNotEmpty) {
        _timelineEvents.addAll(events);
        _phase = WorkSessionPhase.completed;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> startWorkTask(
    String conversationId,
    String prompt, {
    ChatController? chatController,
  }) async {
    if (_phase == WorkSessionPhase.running) {
      await cancelWorkTask();
    }

    _activeConversationId = conversationId;
    _phase = WorkSessionPhase.running;
    _taskStartTime = DateTime.now();
    _workedDurationSeconds = 0;
    _currentThinking = null;
    _notifyMessage = null;
    _errorMessage = null;
    _lastPrompt = prompt;
    _cancelToken = CancelToken();
    _taskResult = null;
    _scrubbedIndex = null;
    _timelineEvents.clear();
    _pendingToolCallId = null;
    _pendingMessages.clear();
    notifyListeners();

    await _persistence.updateWorkSession(
      conversationId: conversationId,
      phase: _phase.name,
      startedAt: _taskStartTime,
    );

    final eventStream = _agentService.runAgentLoop(
      conversationId: conversationId,
      userRequest: prompt,
      initialPlan: _activePlan,
      cancelToken: _cancelToken,
    );

    _agentSubscription = eventStream.listen(
      (event) => _handleAgentEvent(event, conversationId, chatController),
      onError: (err) {
        _phase = WorkSessionPhase.error;
        _errorMessage = err.toString();
        _currentThinking = 'Error: $err';
        notifyListeners();
      },
      onDone: () {
        if (_phase == WorkSessionPhase.running) {
          _phase = WorkSessionPhase.completed;
        }
        _currentThinking = null;
        notifyListeners();
      },
      cancelOnError: false,
    );
  }

  Future<void> resumeWorkTaskWithUserAnswer(
    String answer, {
    ChatController? chatController,
  }) async {
    final cid = _activeConversationId;
    final toolCallId = _pendingToolCallId;
    final cachedMessages = List<Map<String, dynamic>>.from(_pendingMessages);
    if (cid == null || toolCallId == null) return;

    _phase = WorkSessionPhase.running;
    _currentThinking = 'Resuming task...';
    _pendingToolCallId = null;
    _pendingMessages.clear();
    notifyListeners();

    _cancelToken = CancelToken();

    final eventStream = _agentService.runAgentLoop(
      conversationId: cid,
      userRequest: answer,
      initialPlan: _activePlan,
      cancelToken: _cancelToken,
      existingMessages: cachedMessages,
      pendingToolCallId: toolCallId,
    );

    _agentSubscription = eventStream.listen(
      (event) => _handleAgentEvent(event, cid, chatController),
      onError: (err) {
        _phase = WorkSessionPhase.error;
        _errorMessage = err.toString();
        _currentThinking = 'Error: $err';
        notifyListeners();
      },
      onDone: () {
        if (_phase == WorkSessionPhase.running) {
          _phase = WorkSessionPhase.completed;
        }
        _currentThinking = null;
        notifyListeners();
      },
      cancelOnError: false,
    );
  }

  void _handleAgentEvent(
    ManusAgentEvent event,
    String conversationId,
    ChatController? chatController,
  ) {
    if (event is ManusThinkingEvent) {
      _currentThinking = event.text;
      notifyListeners();
    } else if (event is ManusPlanEvent) {
      _activePlan = event.plan;
      notifyListeners();
    } else if (event is ManusToolStartedEvent) {
      _currentThinking = event.toolEvent.brief;
      _timelineEvents.add(event.toolEvent);
      if (isLive) {
        _scrubbedIndex = null;
      }
      notifyListeners();
    } else if (event is ManusToolFinishedEvent) {
      final idx = _timelineEvents.indexWhere((e) => e.id == event.toolEvent.id);
      if (idx != -1) {
        _timelineEvents[idx] = event.toolEvent;
      } else {
        _timelineEvents.add(event.toolEvent);
      }
      notifyListeners();
    } else if (event is ManusMessageNotifyEvent) {
      _notifyMessage = event.message;
      _currentThinking = event.message;
      notifyListeners();
    } else if (event is ManusMessageAskEvent) {
      _phase = WorkSessionPhase.waiting;
      _pendingToolCallId = event.toolCallId;
      _pendingMessages = event.messages;
      _currentThinking = event.question;
      _notifyMessage = event.question;
      if (chatController != null && event.question.isNotEmpty) {
        unawaited(
          chatController.addMessage(role: 'assistant', content: event.question),
        );
      }
      notifyListeners();
    } else if (event is ManusTaskCompletedEvent) {
      _taskResult = event.result;
      _phase = WorkSessionPhase.completed;
      _currentThinking = null;
      if (_taskStartTime != null) {
        _workedDurationSeconds = DateTime.now()
            .difference(_taskStartTime!)
            .inSeconds;
        if (_workedDurationSeconds < 1) _workedDurationSeconds = 1;
      }
      if (chatController != null && event.result.summary.isNotEmpty) {
        unawaited(
          chatController.addMessage(
            role: 'assistant',
            content: event.result.summary,
          ),
        );
      }
      _persistence.updateWorkSession(
        conversationId: conversationId,
        phase: _phase.name,
        endedAt: DateTime.now(),
      );
      notifyListeners();
    } else if (event is ManusErrorEvent) {
      _phase = WorkSessionPhase.error;
      _errorMessage = event.error;
      _currentThinking = 'Error: ${event.error}';
      _persistence.updateWorkSession(
        conversationId: conversationId,
        phase: _phase.name,
        endedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  Future<void> resumeWithTakeoverFeedback(
    String summary, {
    bool persistLogin = true,
    String? currentUrl,
  }) async {
    final cid = _activeConversationId;
    if (cid == null) return;

    final feedbackPrompt = summary.isNotEmpty
        ? 'User completed browser takeover with notes: "$summary". Current URL: ${currentUrl ?? "unchanged"}. Continue task.'
        : 'User completed browser takeover. Current URL: ${currentUrl ?? "unchanged"}. Continue task.';

    await startWorkTask(cid, feedbackPrompt);
  }

  Future<void> cancelWorkTask() async {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('User stopped task');
    }
    await _agentSubscription?.cancel();
    _agentSubscription = null;
    _phase = WorkSessionPhase.idle;
    _currentThinking = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _agentSubscription?.cancel();
    _cancelToken?.cancel();
    super.dispose();
  }
}
