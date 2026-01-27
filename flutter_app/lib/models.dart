class MacroLine {
  final String template;
  const MacroLine(this.template);
}

class Macro {
  final String id;
  final String name;
  final String? description;
  final List<MacroLine> lines;

  const Macro({
    required this.id,
    required this.name,
    this.description,
    required this.lines,
  });
}

const List<Macro> predefinedMacros = [
  Macro(
    id: 'arm_on',
    name: 'ARM ON',
    description: 'Enable command execution on Leonardo',
    lines: [
      MacroLine('TOKEN={TOKEN};ARM:ON\n'),
    ],
  ),
  Macro(
    id: 'arm_off',
    name: 'ARM OFF',
    description: 'Disable command execution on Leonardo',
    lines: [
      MacroLine('TOKEN={TOKEN};ARM:OFF\n'),
    ],
  ),
  Macro(
    id: 'win_r',
    name: 'Open Run dialog (Win+R)',
    description: 'Windows Run dialog',
    lines: [
      MacroLine('TOKEN={TOKEN};HOTKEY:WIN+R\n'),
    ],
  ),
  Macro(
    id: 'ctrl_alt_t',
    name: 'Open Terminal (Ctrl+Alt+T)',
    description: 'Common Linux terminal shortcut',
    lines: [
      MacroLine('TOKEN={TOKEN};HOTKEY:CTRL+ALT+T\n'),
    ],
  ),
  Macro(
    id: 'email_template',
    name: 'Type Email Template',
    description: 'Quick multi-line email starter',
    lines: [
      MacroLine('TOKEN={TOKEN};TYPE:Hello,\n'),
      MacroLine('TOKEN={TOKEN};KEY:ENTER\n'),
      MacroLine('TOKEN={TOKEN};TYPE:Please find the update below.\n'),
      MacroLine('TOKEN={TOKEN};KEY:ENTER\n'),
      MacroLine('TOKEN={TOKEN};TYPE:Thanks.\n'),
    ],
  ),
  Macro(
    id: 'demo_hello_enter',
    name: 'Demo: Hello + Enter',
    description: 'Simple type and enter',
    lines: [
      MacroLine('TOKEN={TOKEN};TYPE:hello from phone\n'),
      MacroLine('TOKEN={TOKEN};KEY:ENTER\n'),
    ],
  ),
  Macro(
    id: 'demo_tab_x3',
    name: 'Demo: Tab x3',
    description: 'Tab three times with small delays',
    lines: [
      MacroLine('TOKEN={TOKEN};KEY:TAB\n'),
      MacroLine('TOKEN={TOKEN};DELAY:150\n'),
      MacroLine('TOKEN={TOKEN};KEY:TAB\n'),
      MacroLine('TOKEN={TOKEN};DELAY:150\n'),
      MacroLine('TOKEN={TOKEN};KEY:TAB\n'),
    ],
  ),
];
