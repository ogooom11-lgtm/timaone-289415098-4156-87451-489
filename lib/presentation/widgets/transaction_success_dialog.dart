import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

Future<void> showCopyableTransactionSuccess(
  BuildContext context, {
  required String title,
  required String message,
  String copyLabel = 'نسخ المعلومات',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: SelectableText(message),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: message));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          icon: const Icon(Icons.copy_rounded),
          label: Text(copyLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('تم'),
        ),
      ],
    ),
  );
}
