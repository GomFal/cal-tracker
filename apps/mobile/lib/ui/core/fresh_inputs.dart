part of 'design_system.dart';

class FreshUnderlineTextField extends StatelessWidget {
  const FreshUnderlineTextField({
    super.key,
    this.fieldKey,
    this.label,
    required this.controller,
    this.placeholder,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.textAlign = TextAlign.start,
    this.style,
    this.labelColor,
    this.lineColor,
    this.focusColor,
    this.errorText,
    this.suffix,
    this.prefix,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.readOnly = false,
    this.enabled = true,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
  });

  final Key? fieldKey;
  final String? label;
  final TextEditingController controller;
  final String? placeholder;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final TextAlign textAlign;
  final TextStyle? style;
  final Color? labelColor;
  final Color? lineColor;
  final Color? focusColor;
  final String? errorText;
  final Widget? suffix;
  final Widget? prefix;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final bool readOnly;
  final bool enabled;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null && label!.isNotEmpty) ...[
          Text(
            label!,
            style: textTheme.labelMedium?.copyWith(
              color: labelColor ?? palette.inkMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
        ],
        TextField(
          key: fieldKey,
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          textAlign: textAlign,
          maxLines: maxLines,
          minLines: minLines,
          readOnly: readOnly,
          enabled: enabled,
          obscureText: obscureText,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style:
              style ??
              textTheme.bodyLarge?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
          decoration: freshUnderlineInputDecoration(
            context,
            hintText: placeholder,
            errorText: errorText,
            suffix: suffix,
            prefix: prefix,
            labelColor: labelColor,
            lineColor: lineColor,
            focusColor: focusColor,
          ),
        ),
      ],
    );
  }
}

class FreshNumberUnitField extends StatelessWidget {
  const FreshNumberUnitField({
    super.key,
    this.fieldKey,
    required this.label,
    required this.controller,
    required this.unit,
    this.placeholder,
    this.keyboardType = const TextInputType.numberWithOptions(decimal: true),
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.style,
    this.labelColor,
    this.lineColor,
    this.focusColor,
    this.errorText,
    this.suffix,
    this.onChanged,
  });

  final Key? fieldKey;
  final String label;
  final TextEditingController controller;
  final String unit;
  final String? placeholder;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextStyle? style;
  final Color? labelColor;
  final Color? lineColor;
  final Color? focusColor;
  final String? errorText;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return FreshUnderlineTextField(
      fieldKey: fieldKey,
      label: label,
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      labelColor: labelColor,
      lineColor: lineColor,
      focusColor: focusColor,
      errorText: errorText,
      onChanged: onChanged,
      style:
          style ??
          textTheme.bodyLarge?.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
      suffix: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (suffix != null) ...[
              suffix!,
              const SizedBox(width: FreshSpacing.sm),
            ],
            Text(
              unit,
              style: textTheme.bodyMedium?.copyWith(
                color: palette.inkMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FreshMacroFieldData {
  const FreshMacroFieldData({
    required this.key,
    required this.label,
    required this.controller,
    required this.color,
    this.unit = 'g',
    this.onChanged,
  });

  final Key key;
  final String label;
  final TextEditingController controller;
  final Color color;
  final String unit;
  final ValueChanged<String>? onChanged;
}

class FreshMacroFields extends StatelessWidget {
  const FreshMacroFields({
    super.key,
    required this.fields,
    this.keyboardType = const TextInputType.numberWithOptions(decimal: true),
    this.inputFormatters,
    this.useMacroTextColor = false,
  });

  final List<FreshMacroFieldData> fields;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool useMacroTextColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          Expanded(
            child: FreshNumberUnitField(
              fieldKey: fields[i].key,
              label: fields[i].label,
              controller: fields[i].controller,
              unit: fields[i].unit,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              labelColor: fields[i].color,
              lineColor: fields[i].color.withValues(alpha: 0.45),
              textAlign: TextAlign.start,
              onChanged: fields[i].onChanged,
              style: textTheme.bodyLarge?.copyWith(
                color: useMacroTextColor ? fields[i].color : palette.ink,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (i < fields.length - 1) const SizedBox(width: FreshSpacing.md),
        ],
      ],
    );
  }
}

class FreshInlineAmountStepper extends StatelessWidget {
  const FreshInlineAmountStepper({
    super.key,
    required this.amountFieldKey,
    this.unitFieldKey,
    required this.amountController,
    this.unitController,
    this.unitText,
    required this.decrementLabel,
    required this.incrementLabel,
    this.decrementKey,
    this.incrementKey,
    required this.onDecrement,
    required this.onIncrement,
    this.onAmountChanged,
    this.onUnitChanged,
    this.keyboardType = const TextInputType.numberWithOptions(decimal: true),
  }) : assert(unitController != null || unitText != null);

  final Key amountFieldKey;
  final Key? unitFieldKey;
  final TextEditingController amountController;
  final TextEditingController? unitController;
  final String? unitText;
  final String decrementLabel;
  final String incrementLabel;
  final Key? decrementKey;
  final Key? incrementKey;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<String>? onAmountChanged;
  final ValueChanged<String>? onUnitChanged;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final valueStyle = textTheme.titleLarge?.copyWith(
      color: palette.ink,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        _FreshInlineTextAction(
          key: decrementKey,
          label: decrementLabel,
          onPressed: onDecrement,
        ),
        const SizedBox(width: FreshSpacing.md),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: palette.rule, width: 1.1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: FreshSpacing.xs),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 64,
                      child: TextField(
                        key: amountFieldKey,
                        controller: amountController,
                        keyboardType: keyboardType,
                        textAlign: TextAlign.end,
                        onChanged: onAmountChanged,
                        style: valueStyle,
                        decoration: freshBorderlessInputDecoration(context),
                      ),
                    ),
                    const SizedBox(width: FreshSpacing.xs),
                    if (unitController != null)
                      SizedBox(
                        width: 46,
                        child: TextField(
                          key: unitFieldKey,
                          controller: unitController,
                          textAlign: TextAlign.start,
                          onChanged: onUnitChanged,
                          style: valueStyle?.copyWith(color: palette.inkMuted),
                          decoration: freshBorderlessInputDecoration(context),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          unitText!,
                          style: textTheme.titleMedium?.copyWith(
                            color: palette.inkMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: FreshSpacing.md),
        _FreshInlineTextAction(
          key: incrementKey,
          label: incrementLabel,
          onPressed: onIncrement,
        ),
      ],
    );
  }
}

class FreshGoalInput extends StatelessWidget {
  const FreshGoalInput({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.unit,
    required this.decrementKey,
    required this.incrementKey,
    required this.onDecrement,
    required this.onIncrement,
    this.onChanged,
    this.errorText,
    this.decrementLabel = '−',
    this.incrementLabel = '+',
    this.inputFormatters,
    this.keyboardType = TextInputType.number,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String unit;
  final Key decrementKey;
  final Key incrementKey;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final String decrementLabel;
  final String incrementLabel;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _FreshInlineTextAction(
              key: decrementKey,
              label: decrementLabel,
              onPressed: onDecrement,
              large: true,
            ),
            const SizedBox(width: FreshSpacing.md),
            Expanded(
              child: FreshUnderlineTextField(
                fieldKey: fieldKey,
                label: '',
                controller: controller,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                textAlign: TextAlign.center,
                errorText: errorText,
                onChanged: onChanged,
                style: (textTheme.displayMedium ?? textTheme.displaySmall)
                    ?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 0,
                    ),
                suffix: Text(
                  unit,
                  style: textTheme.titleLarge?.copyWith(
                    color: palette.inkMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: FreshSpacing.md),
            _FreshInlineTextAction(
              key: incrementKey,
              label: incrementLabel,
              onPressed: onIncrement,
              large: true,
            ),
          ],
        ),
      ],
    );
  }
}

class FreshSteppedValueInput extends StatelessWidget {
  const FreshSteppedValueInput({
    super.key,
    required this.valueKey,
    required this.value,
    required this.unit,
    required this.decrementKey,
    required this.incrementKey,
    required this.onDecrement,
    required this.onIncrement,
    this.canDecrement = true,
    this.canIncrement = true,
    this.decrementLabel = '−',
    this.incrementLabel = '+',
  });

  final Key valueKey;
  final String value;
  final String unit;
  final Key decrementKey;
  final Key incrementKey;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final bool canDecrement;
  final bool canIncrement;
  final String decrementLabel;
  final String incrementLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        _FreshInlineTextAction(
          key: decrementKey,
          label: decrementLabel,
          onPressed: canDecrement ? onDecrement : null,
          large: true,
        ),
        const SizedBox(width: FreshSpacing.md),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.rule)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: FreshSpacing.sm),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      key: valueKey,
                      style: (textTheme.displayMedium ?? textTheme.displaySmall)
                          ?.copyWith(
                            color: palette.ink,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            letterSpacing: 0,
                          ),
                    ),
                    const SizedBox(width: FreshSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        unit,
                        style: textTheme.titleLarge?.copyWith(
                          color: palette.inkMuted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: FreshSpacing.md),
        _FreshInlineTextAction(
          key: incrementKey,
          label: incrementLabel,
          onPressed: canIncrement ? onIncrement : null,
          large: true,
        ),
      ],
    );
  }
}

class FreshSearchActionRow extends StatelessWidget {
  const FreshSearchActionRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.add_rounded,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FreshRadii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.rule)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(icon, color: palette.lime, size: 20),
                  const SizedBox(width: FreshSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.bodyLarge?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration freshUnderlineInputDecoration(
  BuildContext context, {
  String? hintText,
  String? errorText,
  Widget? suffix,
  Widget? prefix,
  Color? labelColor,
  Color? lineColor,
  Color? focusColor,
}) {
  final palette = context.freshPalette;
  final textTheme = Theme.of(context).textTheme;
  final normal = UnderlineInputBorder(
    borderSide: BorderSide(color: lineColor ?? palette.rule, width: 1.1),
  );
  return InputDecoration(
    hintText: hintText,
    errorText: errorText,
    prefixIcon: prefix == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(right: FreshSpacing.sm),
            child: prefix,
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: FreshSpacing.sm),
            child: suffix,
          ),
    suffixIconConstraints: suffix == null
        ? const BoxConstraints(minWidth: 0, minHeight: 0)
        : const BoxConstraints(minWidth: 56, minHeight: 48),
    filled: false,
    fillColor: Colors.transparent,
    labelStyle: labelColor == null
        ? null
        : TextStyle(color: labelColor, fontWeight: FontWeight.w700),
    floatingLabelStyle: labelColor == null
        ? null
        : TextStyle(color: labelColor, fontWeight: FontWeight.w800),
    isDense: true,
    contentPadding: const EdgeInsets.only(bottom: 9),
    hintStyle: textTheme.bodyLarge?.copyWith(
      color: palette.inkMuted,
      fontWeight: FontWeight.w500,
    ),
    border: normal,
    enabledBorder: normal,
    disabledBorder: normal,
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: focusColor ?? palette.lime, width: 2),
    ),
    errorBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: palette.coral, width: 1.4),
    ),
    focusedErrorBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: palette.coral, width: 2),
    ),
  );
}

InputDecoration freshBorderlessInputDecoration(BuildContext context) {
  return const InputDecoration(
    filled: false,
    isDense: true,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
  );
}

class _FreshInlineTextAction extends StatelessWidget {
  const _FreshInlineTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: palette.lime,
        overlayColor: palette.lime.withValues(alpha: 0.12),
        minimumSize: Size(large ? 44 : 48, 44),
        padding: EdgeInsets.symmetric(horizontal: large ? 12 : 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: large ? 28 : null,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FreshRadii.sm),
        ),
      ),
      child: Text(label),
    );
  }
}
