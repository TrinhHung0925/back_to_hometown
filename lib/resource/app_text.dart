// ignore_for_file: must_be_immutable, use_super_parameters

import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppText extends StatelessWidget {
  final String text;
  final FontWeight? fontWeight;
  late double? fontSize;
  final Color? color;
  final int? maxLines;
  final int? maxLength;
  final String? fontFamily;
  final TextAlign? textAlign;
  final EdgeInsets? margin;
  EdgeInsets? padding;
  List<Color>? listColorsGradient;
  AlignmentGeometry? beginGradient;
  AlignmentGeometry? endGradient;
  final FontStyle? fontStyle;
  final double? lineHeight;
  final double? letterSpacing;
  final TextDecoration? decoration;
  final List<Shadow>? shadow;
  final BoxConstraints? constraints;
  final TextOverflow? overflow;
  final Decoration? boxDecoration;
  final Alignment? alignment;
  final double? height;
  final Paint? foreground;

  AppText.manrope(
    this.text, {
    Key? key,
    this.fontWeight = FontWeight.w400,
    this.fontSize,
    this.maxLines,
    this.color = AppColors.ff000000,
    this.fontFamily = 'Manrope',
    this.textAlign,
    this.maxLength,
    this.margin,
    this.padding,
    this.fontStyle,
    this.lineHeight,
    this.decoration,
    this.letterSpacing,
    this.shadow,
    this.constraints,
    this.boxDecoration,
    this.foreground,
    this.overflow = TextOverflow.ellipsis,
    this.alignment,
    this.height,
    this.listColorsGradient,
    this.beginGradient,
    this.endGradient,
  }) : super(key: key) {
    fontSize ??= 14;
  }

  @override
  Widget build(BuildContext context) {
    var disT = text;
    var length = maxLength ?? 0;
    if (length > 0 && text.length > length) {
      disT = text.substring(0, length);
    }
    double sizeText = fontSize ?? 14;
    Widget child = listColorsGradient != null
        ? ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                begin: beginGradient ?? Alignment.centerLeft,
                end: endGradient ?? Alignment.centerRight,
                colors: listColorsGradient!,
              ).createShader(bounds);
            },
            child: Text(
              disT,
              maxLines: maxLines,
              style: TextStyle(
                fontWeight: fontWeight,
                fontSize: sizeText,
                color: color,
                fontFamily: fontFamily,
                fontStyle: fontStyle,
                height: lineHeight,
                decoration: decoration,
                letterSpacing: letterSpacing,
                shadows: shadow,
                foreground: foreground,
              ),
              textAlign: textAlign,
              overflow: overflow,
            ),
          )
        : Text(
            disT,
            maxLines: maxLines,
            style: TextStyle(
              fontWeight: fontWeight,
              fontSize: sizeText,
              color: color,
              fontFamily: fontFamily,
              fontStyle: fontStyle,
              height: lineHeight,
              decoration: decoration,
              letterSpacing: letterSpacing,
              shadows: shadow,
              foreground: foreground,
            ),
            textAlign: textAlign,
            overflow: overflow,
          );
    if (alignment != null) {
      child = Align(alignment: alignment!, widthFactor: 1, child: child);
    }
    return Container(
      margin: margin,
      padding: padding,
      decoration: boxDecoration,
      constraints: constraints,
      height: height,
      child: child,
    );
  }
}
