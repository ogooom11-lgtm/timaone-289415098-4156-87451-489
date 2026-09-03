import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  bool _checking = false;
  String _message = "اضغط فحص التحديث للبحث عن إصدار جديد";

  Future<void> _checkForUpdate() async {
    setState(() {
      _checking = true;
      _message = "جاري البحث عن تحديث...";
    });

    await Future<void>.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    setState(() {
      _checking = false;
      _message =
          "لا يوجد رابط Google Drive محفوظ داخل التطبيق حتى الآن، لذلك لا يوجد تحديث جديد.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تحديث التطبيق")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_alt,
                  size: 64,
                  color: AppColors.brandGold,
                ),
                const SizedBox(height: 16),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _checking ? null : _checkForUpdate,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text("فحص التحديث"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
