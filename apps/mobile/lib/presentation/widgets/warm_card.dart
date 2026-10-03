import 'package:flutter/material.dart';

/// 图片底卡片：AI 生成的暖色底图 + 半透明奶油色蒙版保证文字可读。
///
/// [background] 传图片资源路径；不传则使用纯色渐变兜底（图片缺失时仍可用）。
class WarmCard extends StatelessWidget {
  const WarmCard({
    super.key,
    this.background,
    this.fallbackGradient = const [
      Color(0xFFFFB98A),
      Color(0xFFFFF4EC),
    ],
    this.scrimAlpha = 0.35,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
  });

  final String? background;

  /// 图片缺失 / 未提供时的渐变兜底色（暖色）。
  final List<Color> fallbackGradient;

  /// 蒙版不透明度：底图越深可调越高。
  final double scrimAlpha;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final image = background;
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A5C).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: image == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: fallbackGradient,
                        ),
                      ),
                    )
                  : Image.asset(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: fallbackGradient,
                          ),
                        ),
                      ),
                    ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xFFFFFBF7).withValues(alpha: scrimAlpha),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
