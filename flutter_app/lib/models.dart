class MacroLine {
  final String command;
  const MacroLine(this.command);
}

class Macro {
  final String id;
  final String name;
  final String? description;
  final List<MacroLine> lines;
  final bool isCustom;

  const Macro({
    required this.id,
    required this.name,
    this.description,
    required this.lines,
    this.isCustom = false,
  });
}

const List<Macro> predefinedMacros = [
  Macro(
    id: 'arm_on',
    name: 'ARM ON',
    description: 'Enable command execution on Leonardo',
    lines: [
      MacroLine('ARM:ON'),
    ],
  ),
  Macro(
    id: 'arm_off',
    name: 'ARM OFF',
    description: 'Disable command execution on Leonardo',
    lines: [
      MacroLine('ARM:OFF'),
    ],
  ),
  Macro(
    id: 'win_r',
    name: 'Open Run dialog (Win+R)',
    description: 'Windows Run dialog',
    lines: [
      MacroLine('HOTKEY:WIN+R'),
    ],
  ),
  Macro(
    id: 'ctrl_alt_t',
    name: 'Open Terminal (Ctrl+Alt+T)',
    description: 'Common Linux terminal shortcut',
    lines: [
      MacroLine('HOTKEY:CTRL+ALT+T'),
    ],
  ),
  Macro(
    id: 'email_template',
    name: 'Type Email Template',
    description: 'Quick multi-line email starter',
    lines: [
      MacroLine('TYPE:Hello,'),
      MacroLine('KEY:ENTER'),
      MacroLine('TYPE:Please find the update below.'),
      MacroLine('KEY:ENTER'),
      MacroLine('TYPE:Thanks.'),
    ],
  ),
  Macro(
    id: 'demo_hello_enter',
    name: 'Demo: Hello + Enter',
    description: 'Simple type and enter',
    lines: [
      MacroLine('TYPE:hello from phone'),
      MacroLine('KEY:ENTER'),
    ],
  ),
  Macro(
    id: 'demo_tab_x3',
    name: 'Demo: Tab x3',
    description: 'Tab three times with small delays',
    lines: [
      MacroLine('KEY:TAB'),
      MacroLine('DELAY:150'),
      MacroLine('KEY:TAB'),
      MacroLine('DELAY:150'),
      MacroLine('KEY:TAB'),
    ],
  ),
];
