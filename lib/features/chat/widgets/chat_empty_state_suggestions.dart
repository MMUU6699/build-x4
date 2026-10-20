import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../work/providers/work_session_provider.dart';

class SuggestionItem {
  final IconData icon;
  final String text;
  final String prompt;

  const SuggestionItem({
    required this.icon,
    required this.text,
    required this.prompt,
  });
}

class ChatEmptyStateSuggestions extends StatelessWidget {
  const ChatEmptyStateSuggestions({
    super.key,
    required this.onSelectSuggestion,
    this.topContentPadding = 16,
    this.bottomContentPadding = 16,
    this.footer,
  });

  final ValueChanged<String> onSelectSuggestion;
  final double topContentPadding;
  final double bottomContentPadding;
  final Widget? footer;

  static const List<SuggestionItem> _allSuggestions = [
    SuggestionItem(
      icon: Lucide.Brain,
      text: 'تحليل فكرة مشروع أو تطبيق جديد',
      prompt:
          'ساعدني في تحليل فكرة تطبيق أو مشروع جديد وتحديد القيمة المضافة والميزات الأساسية والجمهور المستهدف.',
    ),
    SuggestionItem(
      icon: Lucide.Code,
      text: 'كتابة ومراجعة كود برمجي باحترافية',
      prompt:
          'قم بمراجعة كود برمجي وكتابة كود نظيف (Clean Code) مع تطبيق أفضل الممارسات وتصحيح أي أخطاء.',
    ),
    SuggestionItem(
      icon: Lucide.ChartColumnBig,
      text: 'صياغة خطة عمل أو استراتيجية تسويقية',
      prompt:
          'ضع خطة عمل تفصيلية واستراتيجية تسويق مبتكرة لإطلاق خدمة أو منتج جديد بنجاح.',
    ),
    SuggestionItem(
      icon: Lucide.Pencil,
      text: 'كتابة مقال أو محتوى احترافي',
      prompt:
          'اكتب مقالاً شيقاً ومحتوى منشور تسويقي وتفاعلي عالي الجودة لوسائل التواصل الاجتماعي.',
    ),
    SuggestionItem(
      icon: Lucide.Search,
      text: 'شرح مفهوم علمي أو تقني معقد ببساطة',
      prompt:
          'اشرح لي مفهوماً تقنياً أو علمياً معقداً بأسلوب مبسط جداً مع أمثلة واقعية وملموسة.',
    ),
    SuggestionItem(
      icon: Lucide.Globe,
      text: 'ترجمة وصياغة نصوص متعددة اللغات بدقة',
      prompt:
          'قم بترجمة وصياغة هذا النص بدقة واحترافية عالية مع مراعاة السياق الثقافي والأسلوب المناسب.',
    ),
    SuggestionItem(
      icon: Lucide.FileText,
      text: 'تلخيص نصوص أو مستندات طويلة واستخراج النقاط',
      prompt:
          'لخص هذا النص الطويل واستخرج أهم النقاط الرئيسية والاستنتاجات العملية في نقاط مركزة.',
    ),
    SuggestionItem(
      icon: Lucide.Lightbulb,
      text: 'عصف ذهني وتوليد 10 أفكار مبتكرة',
      prompt:
          'شاركني في جلسة عصف ذهني وقدم 10 أفكار إبداعية خارج الصندوق لموضوع أو تحدي معين.',
    ),
    SuggestionItem(
      icon: Lucide.Zap,
      text: 'تحسين وتطوير أداء المنتجات الرقمية',
      prompt:
          'اقترح خطة عملية لتحسين أداء وتجربة استخدام تطبيق أو موقع رقمي وزيادة تفاعل المستخدمين.',
    ),
    SuggestionItem(
      icon: Lucide.Compass,
      text: 'التدريب على مقابلات العمل التقنية والإدارية',
      prompt:
          'تصرف كمحاور خبير وأجرِ معي مقابلة عمل تجريبية مع تقديم نصائح فورية لتحسين إجاباتي.',
    ),
    SuggestionItem(
      icon: Lucide.Palette,
      text: 'اقتراح تصاميم وتجارب مستخدم (UI/UX) ملهمة',
      prompt:
          'اقترح أفكاراً عصرية لتصميم واجهة وتجربة مستخدم (UI/UX) مع نظام ألوان وحركات سلسة.',
    ),
    SuggestionItem(
      icon: Lucide.Zap,
      text: 'حل المشكلات التقنية وتصحيح الأخطاء (Debugging)',
      prompt:
          'ساعدني في تشخيص وتتبع سبب هذه المشكلة البرمجية أو التقنية واقتراح حل جذري ودائم لها.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark
        ? const Color(0xFFA0A0A0)
        : const Color(0xFF555555);
    final textColor = isDark
        ? const Color(0xFFE0E0E0)
        : const Color(0xFF333333);

    final workSession = context.watch<WorkSessionProvider?>();
    final isWorkMode = workSession?.isWorkMode ?? false;
    final needsSignIn =
        isWorkMode && workSession != null && !workSession.isSignedInForWork;
    final computerConnected = workSession?.isDaytonaConnected ?? false;
    final computerChecking = workSession?.daytonaChecking ?? false;
    final computerUnavailable = workSession?.daytonaUnavailable ?? false;

    if (isWorkMode) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: bottomContentPadding,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  needsSignIn
                      ? 'Sign in to use Work'
                      : 'What can I do for you?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFDADADA)
                        : const Color(0xFF34322D),
                    letterSpacing: -0.5,
                  ),
                ),
                if (needsSignIn) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Work runs a private cloud computer. Sign in with a real '
                    'account so your sandbox, screenshots, and files stay '
                    'yours.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: isDark
                          ? const Color(0xFFA0A0A0)
                          : const Color(0xFF666664),
                    ),
                  ),
                  const SizedBox(height: 18),
                  IosTileButton(
                    label: 'Sign in',
                    icon: Lucide.User,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    onTap: () {
                      workSession.signInForWork();
                    },
                  ),
                ] else if (computerConnected) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Lucide.CheckCircle,
                        size: 16,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Computer connected',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFF6EE7B7)
                              : const Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ] else if (computerChecking) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Checking computer...',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFFA0A0A0)
                          : const Color(0xFF666664),
                    ),
                  ),
                ] else if (computerUnavailable) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A2B20)
                          : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF6B4520)
                            : const Color(0xFFFFB74D),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Lucide.TriangleAlert,
                          size: 16,
                          color: isDark
                              ? const Color(0xFFFFB74D)
                              : const Color(0xFFE65100),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Daytona Cloud Sandbox is disconnected',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? const Color(0xFFFFCC80)
                                : const Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (footer != null) ...[const SizedBox(height: 24), footer!],
              ],
            ),
          ),
        ),
      );
    }

    // Display only 4 compact suggestions directly above the ChatBox
    final displayedSuggestions = _allSuggestions.take(4).toList();

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: bottomContentPadding + 14,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in displayedSuggestions)
                InkWell(
                  onTap: () => onSelectSuggestion(item.prompt),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(item.icon, size: 20, color: iconColor),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            item.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (footer != null) ...[const SizedBox(height: 8), footer!],
            ],
          ),
        ),
      ),
    );
  }
}
