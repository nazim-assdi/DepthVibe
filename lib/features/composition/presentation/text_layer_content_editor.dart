import 'package:material_ui/material_ui.dart';

class TextLayerContentEditor extends StatefulWidget {
  const TextLayerContentEditor({
    super.key,
    required this.initialText,
    required this.onSave,
  });

  final String initialText;
  final ValueChanged<String> onSave;

  @override
  State<TextLayerContentEditor> createState() => _TextLayerContentEditorState();
}

class _TextLayerContentEditorState extends State<TextLayerContentEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  bool _dirty = false;

  @override
  void didUpdateWidget(covariant TextLayerContentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText && !_dirty) {
      _controller.value = TextEditingValue(
        text: widget.initialText,
        selection: TextSelection.collapsed(offset: widget.initialText.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_controller.text);
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          textDirection: RegExp(r'[\u0590-\u08FF\uFB1D-\uFEFF]')
                  .hasMatch(_controller.text)
              ? TextDirection.rtl
              : TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'Text content',
            hintText: 'বাংলা, العربية, English, 中文, हिन्दी…',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() => _dirty = true),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: _dirty ? _save : null,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save Text'),
          ),
        ),
      ],
    );
  }
}
