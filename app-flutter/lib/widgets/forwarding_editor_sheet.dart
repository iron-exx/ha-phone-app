import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../models/forwarding.dart';
import '../theme/app_colors.dart';

/// What the user picked: [rule] null = "Normal klingeln" (rule removed).
class ForwardingEdit {
  const ForwardingEdit(this.rule);
  final ForwardingRule? rule;
}

enum _Mode { normal, ringThen, always }

enum _Dest { voicemail, extension, hangup }

/// Bottom sheet to edit one status + direction: mode, destination
/// (Mailbox = own box, Nebenstelle from the directory, Ablehnen) and the
/// ring timeout. Returns null when dismissed.
class ForwardingEditorSheet extends StatefulWidget {
  const ForwardingEditorSheet({
    super.key,
    required this.title,
    required this.status,
    required this.direction,
    required this.rule,
    required this.extensions,
    required this.ownNumber,
  });

  final String title;
  final String status;
  final ForwardDirection direction;
  final ForwardingRule? rule;

  /// Selectable extensions (own extension excluded).
  final List<Contact> extensions;

  /// Own extension number = own mailbox; '' when unknown (Mailbox disabled).
  final String ownNumber;

  static Future<ForwardingEdit?> show(
    BuildContext context, {
    required String title,
    required String status,
    required ForwardDirection direction,
    required ForwardingRule? rule,
    required List<Contact> extensions,
    required String ownNumber,
  }) =>
      showModalBottomSheet<ForwardingEdit>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => ForwardingEditorSheet(
          title: title,
          status: status,
          direction: direction,
          rule: rule,
          extensions: extensions,
          ownNumber: ownNumber,
        ),
      );

  @override
  State<ForwardingEditorSheet> createState() => _ForwardingEditorSheetState();
}

class _ForwardingEditorSheetState extends State<ForwardingEditorSheet> {
  late _Mode _mode;
  late _Dest _dest;
  String? _extension;
  late int _timeout;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _mode = r == null ? _Mode.normal : (r.mode == ForwardMode.ringThenDest ? _Mode.ringThen : _Mode.always);
    _dest = switch (r?.destType) {
      ForwardDestType.extension => _Dest.extension,
      ForwardDestType.hangup => _Dest.hangup,
      ForwardDestType.voicemail => _Dest.voicemail,
      _ => widget.ownNumber.isEmpty ? _Dest.hangup : _Dest.voicemail,
    };
    if (r?.destType == ForwardDestType.extension) _extension = r!.destTarget;
    _timeout = (r?.ringTimeout ?? kDefaultRingTimeout).clamp(kMinRingTimeout, kMaxRingTimeout);
  }

  bool get _canSave => _mode == _Mode.normal || _dest != _Dest.extension || (_extension ?? '').isNotEmpty;

  ForwardingRule? _build() {
    if (_mode == _Mode.normal) return null;
    return ForwardingRule(
      status: widget.status,
      direction: widget.direction,
      mode: _mode == _Mode.ringThen ? ForwardMode.ringThenDest : ForwardMode.alwaysDest,
      destType: switch (_dest) {
        _Dest.voicemail => ForwardDestType.voicemail,
        _Dest.extension => ForwardDestType.extension,
        _Dest.hangup => ForwardDestType.hangup,
      },
      destTarget: switch (_dest) {
        _Dest.voicemail => widget.ownNumber,
        _Dest.extension => _extension ?? '',
        _Dest.hangup => '',
      },
      // Sent for "Sofort …" too: the PBX requires 5–120 s either way.
      ringTimeout: _timeout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
            for (final (mode, label) in const [
              (_Mode.normal, 'Normal klingeln'),
              (_Mode.ringThen, 'Erst klingeln, dann …'),
              (_Mode.always, 'Sofort …'),
            ])
              RadioListTile<_Mode>(
                key: ValueKey('forward-mode-${mode.name}'),
                value: mode,
                groupValue: _mode,
                title: Text(label),
                onChanged: (m) => setState(() => _mode = m ?? _mode),
              ),
            if (_mode != _Mode.normal) ..._destination(theme),
            if (_mode == _Mode.ringThen) ..._timeoutSlider(theme),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canSave ? () => Navigator.of(context).pop(ForwardingEdit(_build())) : null,
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _destination(ThemeData theme) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Ziel', style: theme.textTheme.labelLarge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              _chip(_Dest.voicemail, 'Mailbox', Icons.voicemail, enabled: widget.ownNumber.isNotEmpty),
              _chip(_Dest.extension, 'Nebenstelle', Icons.person_outline, enabled: widget.extensions.isNotEmpty),
              _chip(_Dest.hangup, 'Ablehnen', Icons.call_end, color: context.nw.end),
            ],
          ),
        ),
        if (_dest == _Dest.extension)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButtonFormField<String>(
              key: const ValueKey('forward-extension'),
              value: widget.extensions.any((c) => c.number == _extension) ? _extension : null,
              hint: const Text('Nebenstelle wählen'),
              isExpanded: true,
              items: [
                for (final c in widget.extensions)
                  DropdownMenuItem(
                    value: c.number,
                    child: Text(c.name.isEmpty ? c.number : '${c.number} · ${c.name}'),
                  ),
              ],
              onChanged: (n) => setState(() => _extension = n),
            ),
          ),
      ];

  Widget _chip(_Dest dest, String label, IconData icon, {bool enabled = true, Color? color}) => ChoiceChip(
        key: ValueKey('forward-dest-${dest.name}'),
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
        selected: _dest == dest,
        onSelected: enabled ? (_) => setState(() => _dest = dest) : null,
      );

  List<Widget> _timeoutSlider(ThemeData theme) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text('Klingeldauer: $_timeout s', style: tabular(theme.textTheme.labelLarge)),
        ),
        Slider(
          key: const ValueKey('forward-timeout'),
          value: _timeout.toDouble(),
          min: kMinRingTimeout.toDouble(),
          max: kMaxRingTimeout.toDouble(),
          divisions: (kMaxRingTimeout - kMinRingTimeout) ~/ 5,
          label: '$_timeout s',
          semanticFormatterCallback: (v) => '${v.round()} Sekunden',
          onChanged: (v) => setState(() => _timeout = v.round()),
        ),
      ];
}
