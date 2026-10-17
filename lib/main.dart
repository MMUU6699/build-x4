import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:window_manager/window_manager.dart';

import 'core/config/supabase_config.dart';
import 'core/providers/assistant_provider.dart';
import 'core/providers/hotkey_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/update_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/workspace_provider.dart';
import 'core/services/chat/chat_service.dart';
import 'core/services/linux_window_service.dart';
import 'core/services/logging/flutter_logger.dart';
import 'core/services/notification_service.dart';
import 'core/services/preferences/app_preferences.dart';
import 'core/services/workspace/daytona_workspace_runtime.dart';
import 'core/services/workspace/tool_run_registry.dart';
import 'core/services/workspace/workspace_binding_actions.dart';
import 'core/services/workspace/workspace_runtime.dart';
import 'desktop/desktop_tray_controller.dart';
import 'desktop/desktop_window_controller.dart';
import 'desktop/windows_paste_fix.dart';
import 'features/auth/widgets/auth_gate.dart';
import 'features/home/services/ask_user_interaction_service.dart';
import 'features/home/services/context_usage_service.dart';
import 'features/home/services/tool_approval_service.dart';
import 'features/workspace/pages/workspaces_page.dart';
import 'features/workspace/terminal/open_terminal.dart';
import 'features/workspace/widgets/files/conversation_files_panel.dart';
import 'features/workspace/workspace_navigation.dart';
import 'l10n/app_localizations.dart';
import 'shared/widgets/app_overlays.dart';
import 'shared/widgets/floating_ipad_padding.dart';
import 'theme/custom_theme.dart';
import 'theme/palettes.dart';
import 'theme/theme_factory.dart';
import 'utils/sandbox_path_resolver.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<ModalRoute<dynamic>> routeObserver =
    RouteObserver<ModalRoute<dynamic>>();
bool _didCheckUpdates = false;
bool _didEnsureAssistants = false;
bool _didWireWorkspace = false;

void _wireWorkspaceServices(BuildContext ctx) {
  try {
    final chat = ctx.read<ChatService>();
    final workspaces = ctx.read<WorkspaceProvider>();
    final assistants = ctx.read<AssistantProvider>();
    chat.newConversationExtras = (assistantId) {
      if (assistantId == null) {
        return const <String, dynamic>{};
      }
      return workspaceExtrasForNewConversation(
        assistant: assistants.getById(assistantId),
        workspaceById: workspaces.byId,
      );
    };
    WorkspaceNavigation.onOpenEnvironmentPage = (navContext) {};
    WorkspaceNavigation.onOpenTerminal = (navContext, {command}) {
      openTerminal(
        navContext,
        conversationId: chat.currentConversationId,
        command: command,
      );
    };
    WorkspaceNavigation.onOpenWorkspaceFiles = (navContext, {path}) {
      final id = chat.currentConversationId;
      if (id != null) {
        showConversationFilesPanel(navContext, conversationId: id);
      } else {
        Navigator.of(
          navContext,
        ).push(MaterialPageRoute<void>(builder: (_) => const WorkspacesPage()));
      }
    };
  } catch (_) {}
}

Future<void> main() async {
  await runZoned(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      WindowsPasteFix.instance.install();

      await SupabaseConfig.loadSavedGuestMode();
      try {
        await Supabase.initialize(
          url: SupabaseConfig.supabaseUrl,
          publishableKey: SupabaseConfig.supabaseAnonKey,
        );
      } catch (e) {
        debugPrint('Supabase initialize error: $e');
      }

      if (Platform.isAndroid || Platform.isIOS) {
        try {
          await NotificationService.ensureInitialized();
        } catch (_) {}
      }
      FlutterLogger.installGlobalHandlers();

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        await _initDesktopWindow();
      } else if (!kIsWeb) {
        await _initDesktopWindow();
      }

      await SandboxPathResolver.init();

      final preferences = AppPreferences();
      await preferences.load();

      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      runApp(MyApp(preferences: preferences));
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        FlutterLogger.logPrint(line);
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> _initDesktopWindow() async {
  if (kIsWeb) return;
  try {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await windowManager.ensureInitialized();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    final linuxHideTitleBar =
        LinuxWindowService.isSupported &&
        ((await SharedPreferences.getInstance()).getBool(
              LinuxWindowService.hideTitleBarKey,
            ) ??
            false);
    await DesktopWindowController.instance.initializeAndShow(
      title: 'Build X',
      linuxHideTitleBar: linuxHideTitleBar,
    );
  } catch (_) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppPreferences>.value(value: preferences),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => ToolApprovalService()),
        ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
        ChangeNotifierProvider(
          create: (ctx) =>
              AssistantProvider(chatService: ctx.read<ChatService>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final assistants = ctx.read<AssistantProvider>();
            final settings = SettingsProvider(
              preferences,
              onProviderModelsRetired:
                  assistants.clearModelSelectionsForProvider,
            );
            unawaited(
              settings.loaded.then((_) => settings.incrementAppLaunchCount()),
            );
            return settings;
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              WorkspaceProvider(assistants: ctx.read<AssistantProvider>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final provider = WorkspaceRuntimeProvider();
            provider.initialization = (() async {
              try {
                final daytona = DaytonaWorkspaceRuntime();
                provider.setRuntime(daytona);
              } catch (e) {
                debugPrint('Failed to initialize Daytona runtime: $e');
              }
            })();
            unawaited(provider.initialization);
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => ToolRunRegistry()),
        ChangeNotifierProvider(create: (_) => HotkeyProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(
          create: (ctx) => ContextUsageService(
            chatService: ctx.read<ChatService>(),
            settings: ctx.read<SettingsProvider>(),
            assistants: ctx.read<AssistantProvider>(),
          ),
        ),
      ],
      child: Builder(
        builder: (context) {
          final settings = context.watch<SettingsProvider>();
          settings.applyGlobalProxyOverridesIfNeeded();

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              final isDesktop =
                  !kIsWeb &&
                  (defaultTargetPlatform == TargetPlatform.windows ||
                      defaultTargetPlatform == TargetPlatform.macOS ||
                      defaultTargetPlatform == TargetPlatform.linux);
              if (!isDesktop) return;
              final wantsAppSystem =
                  (settings.appFontFamily?.isNotEmpty == true) &&
                  (settings.appFontLocalAlias == null ||
                      settings.appFontLocalAlias!.isEmpty);
              final wantsCodeSystem =
                  (settings.codeFontFamily?.isNotEmpty == true) &&
                  (settings.codeFontLocalAlias == null ||
                      settings.codeFontLocalAlias!.isEmpty);
              if (wantsAppSystem || wantsCodeSystem) {
                final sf = SystemFonts();
                if (wantsAppSystem) {
                  final fam = settings.appFontFamily!;
                  try {
                    await sf.loadFont(fam);
                  } catch (_) {}
                }
                if (wantsCodeSystem) {
                  final fam = settings.codeFontFamily!;
                  try {
                    if (fam != settings.appFontFamily) await sf.loadFont(fam);
                  } catch (_) {}
                }
              }
            } catch (_) {}
          });

          if (settings.showAppUpdates && !_didCheckUpdates) {
            _didCheckUpdates = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                await settings.loaded;
                if (!context.mounted || !settings.showAppUpdates) return;
                await context.read<UpdateProvider>().checkForUpdates();
              } catch (_) {}
            });
          }

          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              final isAndroid =
                  Theme.of(context).platform == TargetPlatform.android;
              final dynSupported =
                  isAndroid && (lightDynamic != null || darkDynamic != null);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  settings.setDynamicColorSupported(dynSupported);
                } catch (_) {}
              });

              WidgetsBinding.instance.addPostFrameCallback((_) async {
                try {
                  final isDesktop =
                      !kIsWeb &&
                      (defaultTargetPlatform == TargetPlatform.windows ||
                          defaultTargetPlatform == TargetPlatform.macOS ||
                          defaultTargetPlatform == TargetPlatform.linux);
                  if (isDesktop) {
                    await context.read<HotkeyProvider>().initialize();
                  }
                } catch (_) {}
              });

              final useDyn = isAndroid && settings.useDynamicColor;
              final custom = settings.selectedCustomTheme;
              final palette =
                  settings.themePaletteId == ThemePalettes.customPaletteId &&
                      custom != null
                  ? buildCustomThemePalette(custom)
                  : ThemePalettes.byId(settings.themePaletteId);

              final light = buildLightThemeForScheme(
                palette.light,
                dynamicScheme: useDyn ? lightDynamic : null,
                pureBackground: settings.usePureBackground,
                layeredSurfaces: settings.useLayeredSurfaces,
              );
              final dark = buildDarkThemeForScheme(
                palette.dark,
                dynamicScheme: useDyn ? darkDynamic : null,
                pureBackground: settings.usePureBackground,
                layeredSurfaces: settings.useLayeredSurfaces,
              );

              String? effectiveAppFontFamily() {
                final fam = settings.appFontFamily;
                if (fam == null || fam.isEmpty) return null;
                return fam;
              }

              final effectiveAppFont = effectiveAppFontFamily();

              ThemeData applyAppFont(ThemeData base) {
                if (effectiveAppFont == null || effectiveAppFont.isEmpty) {
                  return base;
                }
                TextStyle? withFamily(TextStyle? s) =>
                    s?.copyWith(fontFamily: effectiveAppFont);
                TextTheme apply(TextTheme t) => t.copyWith(
                  displayLarge: withFamily(t.displayLarge),
                  displayMedium: withFamily(t.displayMedium),
                  displaySmall: withFamily(t.displaySmall),
                  headlineLarge: withFamily(t.headlineLarge),
                  headlineMedium: withFamily(t.headlineMedium),
                  headlineSmall: withFamily(t.headlineSmall),
                  titleLarge: withFamily(t.titleLarge),
                  titleMedium: withFamily(t.titleMedium),
                  titleSmall: withFamily(t.titleSmall),
                  bodyLarge: withFamily(t.bodyLarge),
                  bodyMedium: withFamily(t.bodyMedium),
                  bodySmall: withFamily(t.bodySmall),
                  labelLarge: withFamily(t.labelLarge),
                  labelMedium: withFamily(t.labelMedium),
                  labelSmall: withFamily(t.labelSmall),
                );
                final bar = base.appBarTheme;
                final appBar = bar.copyWith(
                  titleTextStyle: (bar.titleTextStyle ?? const TextStyle())
                      .copyWith(fontFamily: effectiveAppFont),
                  toolbarTextStyle: (bar.toolbarTextStyle ?? const TextStyle())
                      .copyWith(fontFamily: effectiveAppFont),
                );
                return base.copyWith(
                  textTheme: apply(base.textTheme),
                  primaryTextTheme: apply(base.primaryTextTheme),
                  appBarTheme: appBar,
                );
              }

              final themedLight = applyAppFont(light);
              final themedDark = applyAppFont(dark);

              return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'Build X',
                navigatorKey: rootNavigatorKey,
                locale: settings.appLocaleForMaterialApp,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: themedLight,
                darkTheme: themedDark,
                themeMode: settings.themeMode,
                navigatorObservers: <NavigatorObserver>[routeObserver],
                home: const AuthGate(),
                builder: (ctx, child) {
                  final bright = Theme.of(ctx).brightness;
                  final overlay = bright == Brightness.dark
                      ? const SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness: Brightness.light,
                          statusBarBrightness: Brightness.dark,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarIconBrightness: Brightness.light,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        )
                      : const SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness: Brightness.dark,
                          statusBarBrightness: Brightness.light,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarIconBrightness: Brightness.dark,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        );

                  if (!_didEnsureAssistants) {
                    _didEnsureAssistants = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      try {
                        ctx.read<AssistantProvider>().ensureDefaults(ctx);
                      } catch (_) {}
                      try {
                        ctx.read<ChatService>().setDefaultConversationTitle(
                          AppLocalizations.of(
                            ctx,
                          )!.chatServiceDefaultConversationTitle,
                        );
                      } catch (_) {}
                      try {
                        ctx.read<UserProvider>().setDefaultNameIfUnset(
                          AppLocalizations.of(ctx)!.userProviderDefaultUserName,
                        );
                      } catch (_) {}
                    });
                  }

                  if (!_didWireWorkspace) {
                    _didWireWorkspace = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _wireWorkspaceServices(ctx);
                    });
                  }

                  final l10n = AppLocalizations.of(ctx);
                  if (l10n != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      try {
                        final isDesktop =
                            !kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.windows ||
                                defaultTargetPlatform == TargetPlatform.macOS ||
                                defaultTargetPlatform == TargetPlatform.linux);
                        if (!isDesktop) return;
                        final sp = ctx.read<SettingsProvider>();
                        await DesktopTrayController.instance.syncFromSettings(
                          l10n,
                          showTray: sp.desktopShowTray,
                          minimizeToTrayOnClose:
                              sp.desktopMinimizeToTrayOnClose,
                        );
                      } catch (_) {}
                    });
                  }

                  final appWithOverlays = FloatingIpadPadding(
                    child: AppOverlays(child: child ?? const SizedBox.shrink()),
                  );

                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: overlay,
                    child: effectiveAppFont == null
                        ? appWithOverlays
                        : DefaultTextStyle.merge(
                            style: TextStyle(fontFamily: effectiveAppFont),
                            child: appWithOverlays,
                          ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
