import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Small, centered status chip under the status bar.
abstract final class AppToast {
  static const _shell = Color(0xD9282C34);
  static const _text = Color(0xFFD1D5DB);
  static const _errorAccent = Color(0xFFE8941A);
  static const _successAccent = Color(0xFF5EEAD4);
  static const _infoAccent = Color(0xFF94A3B8);

  static void show(
    BuildContext context,
    String message, {
    bool isError = true,
    bool? isSuccess,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    final accent = isSuccess == true
        ? _successAccent
        : isError
            ? _errorAccent
            : _infoAccent;

    final mq = MediaQuery.of(context);
    const barHeight = 34.0;
    final top = mq.padding.top + 6;
    final maxW = math.min(300.0, mq.size.width - 40);

    messenger.showSnackBar(
      SnackBar(
        width: maxW,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        backgroundColor: _shell,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: mq.size.height - top - barHeight,
        ),
        duration: Duration(milliseconds: isError ? 2800 : 2000),
        dismissDirection: DismissDirection.up,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
