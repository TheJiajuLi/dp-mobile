import 'package:flutter/material.dart';

class HdListItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const HdListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF0FF) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? const Color(0xFF6366F1) : Colors.transparent,
              width: 2.5,
            ),
            bottom: const BorderSide(color: Color(0xFFE5E5EA), width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selected
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFF444444),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
