import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

class AccountProfilePage extends StatefulWidget {
  const AccountProfilePage({super.key});

  @override
  State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _bioController;
  bool _isSaving = false;

  final List<String> _quickEmojis = [
    '⚡',
    '🚀',
    '💻',
    '🧠',
    '🎨',
    '🛠️',
    '✨',
    '🎯',
    '🛡️',
    '🔥',
    '🌟',
    '☕',
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<UserProvider>();
    _nameController = TextEditingController(text: user.name);
    _emailController = TextEditingController(text: user.email);
    _bioController = TextEditingController(text: user.roleOrBio);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final bio = _bioController.text.trim();

    if (name.isEmpty) {
      showAppSnackBar(
        context,
        message: 'يرجى إدخال اسم المستخدم',
        type: NotificationType.warning,
      );
      return;
    }

    setState(() => _isSaving = true);
    final user = context.read<UserProvider>();
    await user.setName(name);
    await user.setEmail(email);
    await user.setRoleOrBio(bio);
    if (mounted) {
      setState(() => _isSaving = false);
      showAppSnackBar(
        context,
        message: 'تم حفظ بيانات الملف الشخصي بنجاح',
        type: NotificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F7F4);
    final cardBg = isDark ? const Color(0xFF1E1E1D) : const Color(0xFFFFFFFF);
    final borderColor = isDark
        ? const Color(0xFF333330)
        : const Color(0xFFE6E4DD);
    final titleColor = isDark
        ? const Color(0xFFEDEDEC)
        : const Color(0xFF141413);
    final subtitleColor = isDark
        ? const Color(0xFF9E9D98)
        : const Color(0xFF666664);
    final user = context.watch<UserProvider>();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          size: 20,
          onTap: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'الملف الشخصي',
          style: TextStyle(
            fontSize: 17,
            fontWeight: AppFontWeights.semibold,
            color: titleColor,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Avatar Header Card
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.3 : 0.04,
                        ),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Avatar Circle
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF2C2C2A)
                              : const Color(0xFFF0EFEA),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child:
                            user.avatarType == 'emoji' &&
                                user.avatarValue != null
                            ? Text(
                                user.avatarValue!,
                                style: const TextStyle(fontSize: 40),
                              )
                            : Icon(
                                Lucide.User,
                                size: 40,
                                color: isDark
                                    ? const Color(0xFFEDEDEC)
                                    : const Color(0xFF141413),
                              ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        user.name,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'صلاحيات كاملة · Full Access',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Emoji Picker Row
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final emoji in _quickEmojis)
                            InkWell(
                              onTap: () => user.setAvatarEmoji(emoji),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: user.avatarValue == emoji
                                      ? (isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.2,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.1,
                                              ))
                                      : Colors.transparent,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          if (user.avatarType != null)
                            InkWell(
                              onTap: () => user.clearAvatar(),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Lucide.X,
                                  size: 16,
                                  color: subtitleColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Information Form Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.3 : 0.04,
                        ),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الاسم الكامل',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: subtitleColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        style: TextStyle(fontSize: 15.5, color: titleColor),
                        decoration: InputDecoration(
                          hintText: 'أدخل اسمك...',
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2C2C2A).withValues(alpha: 0.5)
                              : const Color(0xFFF0EFEA).withValues(alpha: 0.7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'المسمى الوظيفي / النبذة التعريفية',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: subtitleColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bioController,
                        style: TextStyle(fontSize: 15.5, color: titleColor),
                        decoration: InputDecoration(
                          hintText:
                              'مثال: Principal Flutter UI/UX & Full-Stack Engineer',
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2C2C2A).withValues(alpha: 0.5)
                              : const Color(0xFFF0EFEA).withValues(alpha: 0.7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'البريد الإلكتروني',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: subtitleColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(fontSize: 15.5, color: titleColor),
                        decoration: InputDecoration(
                          hintText: 'name@example.com',
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2C2C2A).withValues(alpha: 0.5)
                              : const Color(0xFFF0EFEA).withValues(alpha: 0.7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Save Button
                IosCardPress(
                  onTap: _isSaving ? null : _handleSave,
                  borderRadius: BorderRadius.circular(16),
                  baseColor: isDark ? Colors.white : const Color(0xFF141413),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white : const Color(0xFF141413),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: _isSaving
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isDark
                                  ? const Color(0xFF0A0A0A)
                                  : Colors.white,
                            ),
                          )
                        : Text(
                            'حفظ التغييرات',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF0A0A0A)
                                  : Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
