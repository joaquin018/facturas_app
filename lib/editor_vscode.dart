import 'package:flutter/material.dart';

// --- MODELS ---

class ProjectData {
  String title;
  List<TabGroup> tabs;

  ProjectData({this.title = "", List<TabGroup>? tabs})
    : tabs = tabs ?? [];
}

class TabGroup {
  String title;
  List<SectionData> sections;
  bool isSelected;

  TabGroup({
    required this.title,
    List<SectionData>? sections,
    this.isSelected = false,
  }) : sections = sections ?? [];
}

class SectionData {
  String title;
  List<ItemData> items;

  SectionData({required this.title, required this.items});
}

class ItemData {
  String title;
  List<String> options;
  String inputType; // 'NUMERICO', 'FORMULA', 'TEXTO'
  double currentValue;
  String? formula;
  String? textTemplate;
  Map<String, double> variableValues;

  ItemData({
    required this.title,
    List<String>? options,
    this.inputType = 'NUMERICO',
    this.currentValue = 0,
    this.formula,
    this.textTemplate,
    Map<String, double>? variableValues,
  }) : options = options ?? [],
       variableValues = variableValues ?? {};
}

class TabData {
  String title;
  bool isSelected;

  TabData({required this.title, this.isSelected = false});
}

enum ViewMode { edit, preview }

// --- PARSER ---

class PseudocodeParser {
  static ProjectData parse(String text, {String? title}) {
    ProjectData project = ProjectData(title: title ?? "Proyecto");
    List<String> lines = text.split('\n');
    TabGroup? currentTab;
    SectionData? currentSection;

    for (String line in lines) {
      if (line.trim().isEmpty) continue;
      if (line.trim().startsWith('#')) continue;

      // Count leading spaces for Python-style indentation
      int indent = 0;
      for (int i = 0; i < line.length; i++) {
        if (line[i] == ' ') {
          indent++;
        } else {
          break;
        }
      }

      String content = line.trim();

      if (indent == 0) {
        // Tab Level
        String title = content.endsWith(':')
            ? content.substring(0, content.length - 1).trim()
            : content;
        currentTab = TabGroup(
          title: title,
          sections: [],
          isSelected: project.tabs.isEmpty,
        );
        project.tabs.add(currentTab);
        currentSection = null;
      } else if (indent == 2) {
        // Section Level
        if (currentTab == null) {
          currentTab = TabGroup(title: 'General', sections: []);
          project.tabs.add(currentTab);
        }
        String title = content.endsWith(':')
            ? content.substring(0, content.length - 1).trim()
            : content;
        currentSection = SectionData(title: title, items: []);
        currentTab.sections.add(currentSection);
      } else {
        // Item Level (indent 4+)
        if (currentSection == null) {
          if (currentTab == null) {
            currentTab = TabGroup(title: 'General', sections: []);
            project.tabs.add(currentTab);
          }
          currentSection = SectionData(title: 'Ítems', items: []);
          currentTab.sections.add(currentSection);
        }

        // Split by the FIRST colon
        int colonIndex = content.indexOf(':');
        String itemTitle = content;
        String? formula;
        String? textTemplate;
        List<String> options = [];
        String type = 'NUMERICO';

        if (colonIndex != -1) {
          itemTitle = content.substring(0, colonIndex).trim();
          String logic = content.substring(colonIndex + 1).trim();
          
          if (logic.startsWith('"') && logic.endsWith('"')) {
            type = 'TEXTO';
            textTemplate = logic.substring(1, logic.length - 1);
          } else if (logic.contains('=')) {
            formula = logic;
            type = 'FORMULA';
          } else if (logic.contains('..')) {
            type = 'NUMERICO';
            var bounds = logic.split('..');
            if (bounds.length == 2) {
              int start = int.tryParse(bounds[0].trim()) ?? 0;
              int end = int.tryParse(bounds[1].trim()) ?? 0;
              if (start <= end) {
                options = [
                  for (int i = start; i <= end; i++) i.toString(),
                ];
              }
            }
          } else {
            options =
                logic.split(',').map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
          }
        }

        currentSection.items.add(
          ItemData(
            title: itemTitle,
            options: options,
            inputType: type,
            formula: formula,
            textTemplate: textTemplate,
          ),
        );
      }
    }

    return project;
  }
}

// --- CONTROLLER ---

class PseudocodeController extends TextEditingController {
  @override
  set value(TextEditingValue newValue) {
    // Smart Indentation Logic
    if (newValue.text.length > value.text.length &&
        newValue.selection.isCollapsed) {
      final oldOffset = value.selection.baseOffset;
      final newOffset = newValue.selection.baseOffset;

      if (oldOffset >= 0 && newOffset > oldOffset) {
        final insertedText = newValue.text.substring(oldOffset, newOffset);

        if (insertedText == '\n') {
          // Find the previous line
          final textBefore = newValue.text.substring(0, oldOffset);
          final lines = textBefore.split('\n');
          if (lines.isNotEmpty) {
            final lastLine = lines.last;
            final match = RegExp(r'^(\s*)').firstMatch(lastLine);
            String indent = match?.group(1) ?? '';

            // If previous line ends with ':', increase indent
            if (lastLine.trim().endsWith(':')) {
              indent += '  ';
            }

            final newText = newValue.text.replaceRange(
              newOffset,
              newOffset,
              indent,
            );
            super.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(
                offset: newOffset + indent.length,
              ),
            );
            return;
          }
        }
      }
    }
    super.value = newValue;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> children = [];
    final RegExp regExp = RegExp(
      r'(:)([^"=:\n]+)$|(:)|(#.*)|("[^"\n]*")|(\bif\b|\bunless\b)|(\b\d+(?:\.\d+)?\b)|([()])|([{}]).?|([!@#$%^&*_+=><?/.,\x27;\\\]\[\-])|(\b[a-zA-Z_áéíóúÁÉÍÓÚñÑ][a-zA-Z0-9_áéíóúÁÉÍÓÚñÑ]*\b)|(^[^ \s/#][^:\n]*)|(^ {2}[^ \s/#][^:\n]*)|(^ {4,}[^ #\n][^:\n]*)',
      multiLine: true,
      caseSensitive: false,
    );

    int lastMatchEnd = 0;

    text.splitMapJoin(
      regExp,
      onMatch: (Match match) {
        // Text before the match
        if (match.start > lastMatchEnd) {
          children.add(
            TextSpan(
              text: text.substring(lastMatchEnd, match.start),
              style: style,
            ),
          );
        }

        // The match itself
        if (match.group(1) != null) {
          // Colon + List (Options)
          children.add(
            TextSpan(
              text: match.group(1),
              style: style?.copyWith(color: Colors.white),
            ),
          );
          if (match.group(2) != null) {
            children.add(
              TextSpan(
                text: match.group(2),
                style: style?.copyWith(color: const Color(0xFFCE9178)), // Orange
              ),
            );
          }
        } else if (match.group(3) != null) {
          // Single Colon (for formulas or structural endings)
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(color: Colors.white),
            ),
          );
        } else if (match.group(4) != null) {
          // Comments #
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFF6A9955),
              ),
            ),
          );
        } else if (match.group(5) != null) {
          // Strings "..." with nested highlighting ONLY for {variables}
          String fullString = match.group(0)!;
          final List<TextSpan> stringChildren = [];

          final RegExp nestedRegExp = RegExp(r'\{[^{}]*\}');
          int lastNestedEnd = 0;

          fullString.splitMapJoin(
            nestedRegExp,
            onMatch: (Match nestedMatch) {
              if (nestedMatch.start > lastNestedEnd) {
                stringChildren.add(TextSpan(
                  text: fullString.substring(lastNestedEnd, nestedMatch.start),
                  style: style?.copyWith(color: const Color(0xFFCE9178)),
                ));
              }

              String block = nestedMatch.group(0)!;
              stringChildren.add(TextSpan(
                text: "{",
                style: style?.copyWith(
                  color: const Color(0xFFDAA520),
                  fontWeight: FontWeight.bold,
                ),
              ));
              if (block.length > 2) {
                stringChildren.add(TextSpan(
                  text: block.substring(1, block.length - 1),
                  style: style?.copyWith(color: const Color(0xFF9CDCFE)),
                ));
              }
              stringChildren.add(TextSpan(
                text: "}",
                style: style?.copyWith(
                  color: const Color(0xFFDAA520),
                  fontWeight: FontWeight.bold,
                ),
              ));

              lastNestedEnd = nestedMatch.end;
              return '';
            },
            onNonMatch: (String nm) => '',
          );

          if (lastNestedEnd < fullString.length) {
            stringChildren.add(TextSpan(
              text: fullString.substring(lastNestedEnd),
              style: style?.copyWith(color: const Color(0xFFCE9178)),
            ));
          }

          children.add(TextSpan(children: stringChildren));
        } else if (match.group(6) != null) {
          // Keywords if/unless
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFFC586C0), // Purple
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else if (match.group(7) != null) {
          // Numbers
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFFB5CEA8), // Light Green (VS Code Numbers)
              ),
            ),
          );
        } else if (match.group(8) != null) {
          // Parentheses ()
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFFFFD700), // Gold
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else if (match.group(9) != null) {
          // Braces {}
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFFDAA520), // Dark Gold
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else if (match.group(10) != null) {
          // White Symbols !@#$%^&*_-+=><?/.,';[]\
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else if (match.group(11) != null) {
          // Identifiers (Variables, Properties)
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFF9CDCFE), // Light Blue
              ),
            ),
          );
        } else if (match.group(12) != null) {
          // Tabs (Indent 0)
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFF569CD6), // Blue (VS Code class/def)
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          );
        } else if (match.group(13) != null) {
          // Sections (Indent 2)
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFF569CD6), // Blue (VS Code class/def)
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        } else if (match.group(14) != null) {
          // Item Names (Indent 4+)
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFF9CDCFE), // Light Blue
              ),
            ),
          );
        }

        lastMatchEnd = match.end;
        return '';
      },
      onNonMatch: (String nonMatch) {
        return '';
      },
    );

    // Remaining text
    if (lastMatchEnd < text.length) {
      children.add(TextSpan(text: text.substring(lastMatchEnd), style: style));
    }

    return TextSpan(style: style, children: children);
  }
}

// --- EDITOR MODULE ---

class MainSplitScreen extends StatefulWidget {
  final String initialCode;
  final ProjectData projectData;
  final Function(String) onChanged;

  const MainSplitScreen({
    super.key,
    required this.initialCode,
    required this.projectData,
    required this.onChanged,
  });

  @override
  State<MainSplitScreen> createState() => _MainSplitScreenState();
}

class _MainSplitScreenState extends State<MainSplitScreen> {
  ViewMode _viewMode = ViewMode.edit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _viewMode == ViewMode.edit
                  ? EditorScreen(
                      initialCode: widget.initialCode,
                      onChanged: widget.onChanged,
                      currentMode: _viewMode,
                      onModeChanged: (mode) => setState(() => _viewMode = mode),
                    )
                  : PreviewScreen(
                      data: widget.projectData,
                      isLive: true,
                      onBack: () => setState(() => _viewMode = ViewMode.edit),
                      showModeSelector: true,
                      onModeChanged: (mode) => setState(() => _viewMode = mode),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditorScreen extends StatefulWidget {
  final String initialCode;
  final Function(String) onChanged;
  final ViewMode currentMode;
  final Function(ViewMode) onModeChanged;

  const EditorScreen({
    super.key,
    required this.initialCode,
    required this.onChanged,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late PseudocodeController _controller;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _autocompleteOverlay;
  List<String> _suggestions = [];
  int _cursorPosition = 0;
  final List<Map<String, dynamic>> _keywords = [
    {'name': 'if', 'type': 'keyword'},
    {'name': 'unless', 'type': 'keyword'},
    {'name': 'variable', 'type': 'keyword'},
  ];

  @override
  void initState() {
    super.initState();
    _controller = PseudocodeController();
    _controller.text = widget.initialCode;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _hideAutocomplete();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    final selection = _controller.selection;

    widget.onChanged(text);

    if (selection.isCollapsed && selection.baseOffset >= 0) {
      _cursorPosition = selection.baseOffset;

      // Dynamic parsing of names
      List<Map<String, dynamic>> dynamicSuggestions = [];
      final lines = text.split('\n');
      for (var line in lines) {
        if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
        int indent = 0;
        for (int i = 0; i < line.length; i++) {
          if (line[i] == ' ') {
            indent++;
          } else {
            break;
          }
        }
        String content = line.trim();
        if (content.contains(':')) {
          content = content.split(':')[0].trim();
        }

        if (indent == 0) {
          dynamicSuggestions.add({'name': content, 'type': 'tab'});
        } else if (indent == 2) {
          dynamicSuggestions.add({'name': content, 'type': 'section'});
        } else if (indent >= 4) {
          dynamicSuggestions.add({'name': content, 'type': 'item'});
        }
      }

      final beforeCursor = text.substring(0, _cursorPosition);
      
      // Check for property suggestion (after a dot)
      final dotMatch = RegExp(r'([\wáéíóúñ]+)\.$').firstMatch(beforeCursor);
      if (dotMatch != null) {
        _suggestions = [
          'total',
          'avg',
          'count',
          'max',
          'min'
        ];
        _showAutocomplete(isProperty: true);
        return;
      }

      final lastWordMatch = RegExp(r'([\wáéíóúñ]+)$').firstMatch(beforeCursor);

      if (lastWordMatch != null) {
        final query = lastWordMatch.group(0)!.toLowerCase();
        
        List<Map<String, dynamic>> filtered = [
          ..._keywords,
          ...dynamicSuggestions,
        ].where((s) {
          final name = s['name'].toString().toLowerCase();
          return name.startsWith(query) && name != query;
        }).toList();

        if (filtered.isNotEmpty) {
          _suggestions = filtered.map((s) => s['name'].toString()).toList();
          _showAutocomplete(types: filtered.map((s) => s['type'].toString()).toList());
        } else {
          _hideAutocomplete();
        }
      } else {
        _hideAutocomplete();
      }
    } else {
      _hideAutocomplete();
    }
    setState(() {});
  }

  Offset _getCursorOffset() {
    final text = _controller.text;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.of(context).textScaler,
    );
    textPainter.layout();
    
    Offset caretOffset = textPainter.getOffsetForCaret(
      TextPosition(offset: _cursorPosition),
      Rect.zero,
    );
    
    // Add editor padding (left: 10, top: 20) and move down by one line height (approx 21)
    return Offset(caretOffset.dx + 10, caretOffset.dy + 20 + 22); 
  }

  void _showAutocomplete({List<String>? types, bool isProperty = false}) {
    _hideAutocomplete();
    
    final cursorOffset = _getCursorOffset();

    _autocompleteOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: 220,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: cursorOffset,
          child: Material(
            elevation: 12,
            color: const Color(0xFF252526),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_suggestions.length, (index) {
                  final s = _suggestions[index];
                  final type = isProperty ? 'property' : (types?[index] ?? 'variable');
                  
                  IconData icon;
                  Color iconColor;
                  switch (type) {
                    case 'keyword':
                      icon = Icons.vpn_key_rounded;
                      iconColor = const Color(0xFFC586C0);
                      break;
                    case 'section':
                      icon = Icons.folder_open_rounded;
                      iconColor = const Color(0xFF4EC9B0);
                      break;
                    case 'tab':
                      icon = Icons.tab_unselected_rounded;
                      iconColor = const Color(0xFF569CD6);
                      break;
                    case 'property':
                      icon = Icons.settings_input_component_rounded;
                      iconColor = const Color(0xFFDCDCAA);
                      break;
                    default:
                      icon = Icons.code_rounded;
                      iconColor = const Color(0xFF9CDCFE);
                  }

                  return InkWell(
                    onTap: () => _applySuggestion(s, isProperty: isProperty),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(icon, size: 14, color: iconColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            type.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_autocompleteOverlay!);
  }

  void _hideAutocomplete() {
    _autocompleteOverlay?.remove();
    _autocompleteOverlay = null;
  }

  void _applySuggestion(String suggestion, {bool isProperty = false}) {
    final text = _controller.text;
    final beforeCursor = text.substring(0, _cursorPosition);
    
    String newText;
    int newCursorPos;

    if (isProperty) {
      newText = text.substring(0, _cursorPosition) + 
                suggestion + 
                text.substring(_cursorPosition);
      newCursorPos = _cursorPosition + suggestion.length;
    } else {
      final lastWordMatch = RegExp(r'([\wáéíóúñ]+)$').firstMatch(beforeCursor);
      if (lastWordMatch != null) {
        newText = text.replaceRange(
          lastWordMatch.start,
          lastWordMatch.end,
          suggestion,
        );
        newCursorPos = lastWordMatch.start + suggestion.length;
      } else {
        newText = text.substring(0, _cursorPosition) +
                  suggestion +
                  text.substring(_cursorPosition);
        newCursorPos = _cursorPosition + suggestion.length;
      }
    }

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    _hideAutocomplete();
    widget.onChanged(newText);
  }

  @override
  Widget build(BuildContext context) {
    int lineCount = _controller.text.split('\n').length;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: Colors.black45,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ModeButton(
              title: 'Editar',
              isSelected: widget.currentMode == ViewMode.edit,
              onTap: () => widget.onModeChanged(ViewMode.edit),
            ),
            _ModeButton(
              title: 'Visualizar',
              isSelected: widget.currentMode == ViewMode.preview,
              onTap: () => widget.onModeChanged(ViewMode.preview),
            ),
          ],
        ),
      ),
      body: Container(
        color: const Color(0xFF1E1E1E),
        child: Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 45,
                  padding: const EdgeInsets.only(top: 20),
                  color: Colors.transparent,
                  child: Column(
                    children: List.generate(
                      lineCount,
                      (index) => SizedBox(
                        height: 21,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, color: Colors.white10),
                Expanded(
                  child: CompositedTransformTarget(
                    link: _layerLink,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 20,
                                bottom: 20,
                                left: 10,
                                right: 20,
                              ),
                              child: CustomPaint(
                                painter: _IndentGuidePainter(
                                  text: _controller.text,
                                  textStyle: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                  textScaler: MediaQuery.of(context).textScaler,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 20,
                              bottom: 20,
                              left: 10,
                              right: 20,
                            ),
                            child: SizedBox(
                              width: 2000,
                              child: TextField(
                                controller: _controller,
                                maxLines: null,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  color: Color(0xFFCE9178),
                                  height: 1.5,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: 'Escribe tu pseudocódigo aquí...',
                                  border: InputBorder.none,
                                  counterText: '',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF81D4FA).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF81D4FA) : Colors.transparent,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? const Color(0xFF81D4FA) : Colors.grey,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _IndentGuidePainter extends CustomPainter {
  final String text;
  final TextStyle textStyle;
  final TextScaler textScaler;

  _IndentGuidePainter({
    required this.text,
    required this.textStyle,
    required this.textScaler,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(text: '0' * 100, style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();

    final double charWidth = textPainter.width / 100;
    final double indentWidth = charWidth * 2;
    final double fontSize = textStyle.fontSize ?? 14;
    final double lineHeight =
        textScaler.scale(fontSize) * (textStyle.height ?? 1);

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    final lines = text.split('\n');
    final List<int> actualLevels = lines.map((line) {
      if (line.trim().isEmpty) return -1;
      final match = RegExp(r'^[ \t]*').firstMatch(line);
      final leadingWhitespace = match?.group(0) ?? '';
      final columns = leadingWhitespace.runes.fold<int>(
        0,
        (total, rune) => total + (rune == 9 ? 2 : 1),
      );
      return columns ~/ 2;
    }).toList();

    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      int indentLevels = actualLevels[lineIndex];

      if (indentLevels == -1) {
        int prev = -1;
        for (int j = lineIndex - 1; j >= 0; j--) {
          if (actualLevels[j] != -1) {
            prev = actualLevels[j];
            break;
          }
        }
        int next = -1;
        for (int j = lineIndex + 1; j < lines.length; j++) {
          if (actualLevels[j] != -1) {
            next = actualLevels[j];
            break;
          }
        }

        if (prev != -1 && next != -1) {
          indentLevels = prev < next ? prev : next;
        } else {
          indentLevels = 0;
        }
      }

      if (indentLevels <= 0) continue;

      final top = lineIndex * lineHeight;
      final bottom = (top + lineHeight).clamp(0.0, size.height);

      for (int level = 1; level <= indentLevels; level++) {
        final x = (level - 1) * indentWidth;
        if (x > size.width) break;

        final crispX = x.roundToDouble() + 0.5;
        canvas.drawLine(Offset(crispX, top), Offset(crispX, bottom), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IndentGuidePainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.textScaler != textScaler;
  }
}

// --- PREVIEW MODULE ---

class PreviewScreen extends StatefulWidget {
  final ProjectData data;
  final bool isLive;
  final VoidCallback? onBack;
  final bool showModeSelector;
  final Function(ViewMode)? onModeChanged;

  const PreviewScreen({
    super.key,
    required this.data,
    this.isLive = false,
    this.onBack,
    this.showModeSelector = false,
    this.onModeChanged,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  Map<String, double> sectionTotals = {};
  late String _activeTabTitle;

  @override
  void initState() {
    super.initState();
    _activeTabTitle = widget.data.tabs.isNotEmpty
        ? widget.data.tabs[0].title
        : '';
    _calculateTotals();
  }

  void _calculateTotals() {
    Map<String, double> newTotals = {};

    for (var tab in widget.data.tabs) {
      for (var section in tab.sections) {
        for (var item in section.items) {
          if (item.inputType == 'FORMULA' && item.formula != null) {
            item.currentValue = _evaluateItemFormula(item, newTotals);
          }
        }
      }
    }

    for (var tab in widget.data.tabs) {
      for (var section in tab.sections) {
        if (!_isFormula(section.title)) {
          double total = 0;
          for (var item in section.items) {
            total += item.currentValue;
          }
          newTotals[section.title.toLowerCase()] = total;
        }
      }
    }

    for (var tab in widget.data.tabs) {
      for (var section in tab.sections) {
        if (_isFormula(section.title)) {
          newTotals[section.title.toLowerCase()] = _evaluateFormula(
            section.title,
            newTotals,
          );
        }
      }
    }

    setState(() {
      sectionTotals = newTotals;
    });
  }

  double _evaluateItemFormula(ItemData item, Map<String, double> knownTotals) {
    String rawFormula = item.formula!.split('=')[0].trim();
    String expression = rawFormula;
    bool conditionMet = true;

    // Ruby style 'if' / 'unless'
    if (rawFormula.contains(' if ')) {
      var parts = rawFormula.split(' if ');
      expression = parts[0].trim();
      conditionMet = _evaluateCondition(parts[1].trim(), knownTotals);
    } else if (rawFormula.contains(' unless ')) {
      var parts = rawFormula.split(' unless ');
      expression = parts[0].trim();
      conditionMet = !_evaluateCondition(parts[1].trim(), knownTotals);
    }

    if (!conditionMet) return 0;

    List<String> operators = RegExp(
      r'[\+\-\*/]',
    ).allMatches(expression).map((m) => m.group(0)!).toList();
    List<String> operands = expression.split(RegExp(r'[\+\-\*/]'));

    double result = 0;

    for (int i = 0; i < operands.length; i++) {
      String op = operands[i].trim().toLowerCase();
      double val = 0;

      if (op == 'variable' || item.variableValues.containsKey(op)) {
        val = item.variableValues[op] ?? 0;
      } else if (op.contains('(') && op.endsWith(')')) {
        var parts = op.split('(');
        String secName = parts[0].trim().toLowerCase();
        String itemName = parts[1].replaceAll(')', '').trim().toLowerCase();
        val = _resolveScopedItem(secName, itemName);
      } else if (op.contains('.')) {
        // Python/Ruby Style Property access: Section.total, Section.avg, etc.
        var parts = op.split('.');
        String target = parts[0].trim().toLowerCase();
        String prop = parts[1].trim().toLowerCase();
        val = _resolveProperty(target, prop, knownTotals);
      } else {
        val = double.tryParse(op) ?? _resolveGlobalIdentifier(op, knownTotals);
      }

      if (i == 0) {
        result = val;
      } else {
        String operator = operators[i - 1];
        if (operator == '+') result += val;
        if (operator == '-') result -= val;
        if (operator == '*') result *= val;
        if (operator == '/') result = val == 0 ? 0 : result / val;
      }
    }

    return result;
  }

  bool _evaluateCondition(String condition, Map<String, double> knownTotals) {
    // Simple condition evaluator: a > b, a < b, a == b, a >= b, a <= b
    final reg = RegExp(r'(>=|<=|==|>|<)');
    final match = reg.firstMatch(condition);
    if (match == null) return false;

    String op = match.group(0)!;
    var parts = condition.split(op);
    double v1 = _resolveAtomic(parts[0].trim().toLowerCase(), knownTotals);
    double v2 = _resolveAtomic(parts[1].trim().toLowerCase(), knownTotals);

    if (op == '>') return v1 > v2;
    if (op == '<') return v1 < v2;
    if (op == '==') return v1 == v2;
    if (op == '>=') return v1 >= v2;
    if (op == '<=') return v1 <= v2;
    return false;
  }

  double _resolveAtomic(String name, Map<String, double> knownTotals) {
    if (double.tryParse(name) != null) return double.parse(name);
    if (name.contains('.')) {
      var parts = name.split('.');
      return _resolveProperty(parts[0], parts[1], knownTotals);
    }
    return _resolveGlobalIdentifier(name, knownTotals);
  }

  double _resolveProperty(
    String target,
    String prop,
    Map<String, double> knownTotals,
  ) {
    // target could be a section or an item title
    SectionData? section;
    for (var tab in widget.data.tabs) {
      for (var s in tab.sections) {
        if (s.title.toLowerCase() == target) {
          section = s;
          break;
        }
      }
    }

    if (section != null) {
      if (prop == 'total') return knownTotals[target] ?? 0;
      if (prop == 'count') return section.items.length.toDouble();
      if (prop == 'avg') {
        double total = knownTotals[target] ?? 0;
        return section.items.isEmpty ? 0 : total / section.items.length;
      }
      if (prop == 'max') {
        double maxVal = -double.infinity;
        for (var item in section.items) {
          if (item.currentValue > maxVal) maxVal = item.currentValue;
        }
        return maxVal == -double.infinity ? 0 : maxVal;
      }
    }
    return 0;
  }

  double _resolveGlobalIdentifier(
    String name,
    Map<String, double> knownTotals,
  ) {
    if (knownTotals.containsKey(name)) return knownTotals[name]!;
    for (var tab in widget.data.tabs) {
      for (var section in tab.sections) {
        for (var item in section.items) {
          if (item.title.toLowerCase() == name) return item.currentValue;
        }
      }
    }
    return 0;
  }

  double _resolveScopedItem(String secName, String itemName) {
    for (var tab in widget.data.tabs) {
      for (var section in tab.sections) {
        if (section.title.toLowerCase() == secName) {
          for (var item in section.items) {
            if (item.title.toLowerCase() == itemName) return item.currentValue;
          }
        }
      }
    }
    return 0;
  }

  bool _isFormula(String title) {
    return title.contains('+') ||
        title.contains('-') ||
        title.contains('*') ||
        title.contains('/');
  }

  double _evaluateFormula(String formula, Map<String, double> knownTotals) {
    List<String> parts = formula.split(RegExp(r'[\+\-\*/]'));
    List<String> operators = RegExp(
      r'[\+\-\*/]',
    ).allMatches(formula).map((m) => m.group(0)!).toList();

    if (parts.isEmpty) return 0;

    double result = knownTotals[parts[0].trim().toLowerCase()] ?? 0;

    for (int i = 0; i < operators.length; i++) {
      if (i + 1 >= parts.length) break;
      double nextVal = knownTotals[parts[i + 1].trim().toLowerCase()] ?? 0;
      String op = operators[i];

      if (op == '+') {
        result += nextVal;
      } else if (op == '-') {
        result -= nextVal;
      } else if (op == '*') {
        result *= nextVal;
      } else if (op == '/') {
        result = nextVal != 0 ? result / nextVal : 0;
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = widget.data.tabs.firstWhere(
      (t) => t.title == _activeTabTitle,
      orElse: () => widget.data.tabs.isNotEmpty
          ? widget.data.tabs[0]
          : TabGroup(title: ''),
    );

    return Scaffold(
      appBar: widget.showModeSelector
          ? AppBar(
              toolbarHeight: 50,
              backgroundColor: Colors.black45,
              automaticallyImplyLeading: false,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ModeButton(
                    title: 'Editar',
                    isSelected: false,
                    onTap: () => widget.onModeChanged?.call(ViewMode.edit),
                  ),
                  _ModeButton(
                    title: 'Visualizar',
                    isSelected: true,
                    onTap: () => widget.onModeChanged?.call(ViewMode.preview),
                  ),
                ],
              ),
            )
          : (widget.isLive
                ? AppBar(
                    toolbarHeight: 40,
                    backgroundColor: Colors.black26,
                    title: const Text(
                      'Vista Previa en Vivo',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    automaticallyImplyLeading: false,
                  )
                : AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(
                      widget.data.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                  )),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...activeTab.sections.map((section) {
              double? totalValue = sectionTotals[section.title.toLowerCase()];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  SectionHeader(
                    title: section.title,
                    value: _isFormula(section.title) && totalValue != null
                        ? totalValue.toStringAsFixed(0)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  ...section.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: item.inputType == 'TEXTO'
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                                horizontal: 12.0,
                              ),
                              child: Text(
                                _resolveTextTemplate(item),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            )
                          : ProjectCard(
                              title: item.title,
                              item: item,
                              onFormulaChanged: () =>
                                  setState(() => _calculateTotals()),
                              chips: item.options.isEmpty ? null : item.options,
                              selectedIndex: item.options.isEmpty ? null : 0,
                              allGlobalNames: _getAllGlobalNames(),
                              showInput: item.inputType == 'NUMERICO',
                              initialValue: item.currentValue.toStringAsFixed(0),
                              onChanged: (val) {
                                setState(() {
                                  item.currentValue = double.tryParse(val) ?? 0;
                                  _calculateTotals();
                                });
                              },
                            ),
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomBar(
        tabs: widget.data.tabs
            .map(
              (t) => TabData(
                title: t.title,
                isSelected: t.title == _activeTabTitle,
              ),
            )
            .toList(),
        onTabTap: (title) {
          setState(() {
            _activeTabTitle = title;
          });
        },
      ),
    );
  }

  Set<String> _getAllGlobalNames() {
    Set<String> names = {};
    for (var tab in widget.data.tabs) {
      for (var section in tab.sections) {
        names.add(section.title.toLowerCase());
        for (var item in section.items) {
          names.add(item.title.toLowerCase());
        }
      }
    }
    return names;
  }

  String _resolveTextTemplate(ItemData item) {
    if (item.textTemplate == null) return "";
    String result = item.textTemplate!;
    final reg = RegExp(r'\{([^}]+)\}');
    final matches = reg.allMatches(result).toList();

    // Replace from back to front to keep offsets correct
    for (var match in matches.reversed) {
      String varName = match.group(1)!.trim().toLowerCase();
      double val = _resolveGlobalIdentifier(varName, sectionTotals);
      result = result.replaceRange(
        match.start,
        match.end,
        val.toStringAsFixed(2).replaceAll('.00', ''),
      );
    }
    return result;
  }
}

// --- WIDGETS ---

class SectionHeader extends StatelessWidget {
  final String title;
  final String? value;
  const SectionHeader({super.key, required this.title, this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF81D4FA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF81D4FA),
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        if (value != null)
          Text(
            value!,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
      ],
    );
  }
}

class ProjectCard extends StatefulWidget {
  final String title;
  final List<String>? chips;
  final int? selectedIndex;
  final bool showInput;
  final String initialValue;
  final Set<String> allGlobalNames;
  final Function(String) onChanged;

  final ItemData item;
  final Function() onFormulaChanged;

  const ProjectCard({
    super.key,
    required this.title,
    required this.item,
    required this.onFormulaChanged,
    this.chips,
    this.selectedIndex,
    this.allGlobalNames = const {},
    this.showInput = false,
    this.initialValue = '0',
    required this.onChanged,
  });

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    if (widget.initialValue == '0') {
      _controller.selection = TextSelection.fromPosition(
        const TextPosition(offset: 1),
      );
    }
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(ProjectCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.showInput)
                Container(
                  width: 80,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: widget.onChanged,
                    style: TextStyle(
                      color: _controller.text == '0' ? Colors.white38 : Colors.white,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
            ],
          ),
          if (widget.chips != null && widget.chips!.isNotEmpty) ...[
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.chips!.asMap().entries.map((entry) {
                  bool isSelected = entry.key == widget.selectedIndex;
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: isSelected
                          ? const Color(0xFF81D4FA)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () {},
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (widget.item.inputType == 'FORMULA' &&
              widget.item.formula != null) ...[
            const SizedBox(height: 16),
            _buildFormulaRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildFormulaRow() {
    String formulaText = widget.item.formula!.split('=')[0];
    List<String> operators = RegExp(
      r'[\+\-\*/]',
    ).allMatches(formulaText).map((m) => m.group(0)!).toList();
    List<String> operands = formulaText.split(RegExp(r'[\+\-\*/]'));

    List<Widget> children = [];

    for (int i = 0; i < operands.length; i++) {
      String op = operands[i].trim();
      String lowerOp = op.toLowerCase();

      bool isLocalVariable =
          lowerOp == 'variable' ||
          (double.tryParse(op) == null &&
              !lowerOp.contains('(') &&
              !widget.allGlobalNames.contains(lowerOp));

      if (isLocalVariable) {
        children.add(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lowerOp != 'variable')
                Text(
                  op,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              Container(
                width: 65,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF81D4FA).withValues(alpha: 0.3),
                  ),
                ),
                child: TextField(
                  controller: TextEditingController(
                    text:
                        widget.item.variableValues[lowerOp] == null ||
                                widget.item.variableValues[lowerOp] == 0
                            ? ''
                            : widget.item.variableValues[lowerOp]!
                                .toStringAsFixed(0),
                  )..selection = TextSelection.fromPosition(
                    TextPosition(
                      offset:
                          widget.item.variableValues[lowerOp] == null ||
                                  widget.item.variableValues[lowerOp] == 0
                              ? 0
                              : widget.item.variableValues[lowerOp]!
                                  .toStringAsFixed(0)
                                  .length,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: '0 ',
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                  onChanged: (val) {
                    widget.item.variableValues[lowerOp] =
                        double.tryParse(val) ?? 0;
                    widget.onFormulaChanged();
                  },
                ),
              ),
            ],
          ),
        );
      } else {
        children.add(
          Text(op, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        );
      }

      if (i < operators.length) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              operators[i],
              style: const TextStyle(
                color: Color(0xFF81D4FA),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }
    }

    children.add(
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text("=", style: TextStyle(color: Colors.grey)),
      ),
    );

    children.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF81D4FA).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          widget.item.currentValue.toStringAsFixed(0),
          style: const TextStyle(
            color: Color(0xFF81D4FA),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
    );
  }
}

class CustomBottomBar extends StatelessWidget {
  final List<TabData> tabs;
  final Function(String) onTabTap;
  const CustomBottomBar({
    super.key,
    required this.tabs,
    required this.onTabTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: Row(
        children: tabs
            .map(
              (tab) => Expanded(
                child: BottomTab(
                  title: tab.title,
                  isSelected: tab.isSelected,
                  onTap: () => onTabTap(tab.title),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class BottomTab extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const BottomTab({
    super.key,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFF2D2D2D) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? const Color(0xFF81D4FA) : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
