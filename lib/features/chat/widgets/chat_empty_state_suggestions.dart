import 'package:flutter/material.dart';
import '../../../icons/lucide_adapter.dart';

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
