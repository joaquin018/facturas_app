import 'package:flutter/material.dart';

// --- MODELS ---

class ProjectData {
  String title;
  List<TabGroup> tabs;

  ProjectData({this.title = "Nuevo Proyecto", List<TabGroup>? tabs})
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
  String inputType; // 'NUMERICO', 'TEXTO', 'NADA', 'FORMULA'
  double currentValue;
  String? formula;
  List<double> internalValues;

  ItemData({
    required this.title,
    List<String>? options,
    this.inputType = 'NADA',
    this.currentValue = 0,
    this.formula,
    List<double>? internalValues,
  }) : options = options ?? [],
       internalValues = internalValues ?? [];
}

class TabData {
  String title;
  bool isSelected;

  TabData({required this.title, this.isSelected = false});
}

enum ViewMode { edit, preview }

// --- PARSER ---

class PseudocodeParser {
  static ProjectData parse(String text) {
    ProjectData project = ProjectData();
    List<String> lines = text.split('\n');
    TabGroup? currentTab;
    SectionData? currentSection;

    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      String lowerLine = line.toLowerCase();

      if (lowerLine.startsWith('proyecto:')) {
        project.title = line.substring(9).trim();
      } else if (lowerLine.startsWith('tabs:')) {
        String title = line.substring(5).trim();
        currentTab = TabGroup(
          title: title,
          sections: [],
          isSelected: project.tabs.isEmpty, // Select first tab by default
        );
        project.tabs.add(currentTab);
        currentSection = null; // Reset section when tab changes
      } else if (lowerLine.startsWith('seccion:')) {
        if (currentTab == null) {
          // Fallback if no tab is declared yet
          currentTab = TabGroup(title: 'General', sections: []);
          project.tabs.add(currentTab);
        }
        currentSection = SectionData(
          title: line.substring(8).trim(),
          items: [],
        );
        currentTab.sections.add(currentSection);
      } else if (lowerLine.startsWith('item:')) {
        if (currentSection == null) continue;

        // Split by pipe |
        List<String> parts = line.substring(5).split('|');
        String title = parts[0].trim();
        List<String> options = [];
        String type = 'NADA';

        for (var part in parts) {
          String lowerPart = part.toLowerCase();
          if (lowerPart.contains('opciones:')) {
            options = part
                .split(':')
                .last
                .split(',')
                .map((e) => e.trim())
                .toList();
          } else if (lowerPart.contains('tipo:')) {
            type = part.split(':').last.trim().toUpperCase();
          }
        }

        String? formula;
        if (title.contains('=') &&
            (title.contains('+') ||
                title.contains('-') ||
                title.contains('*') ||
                title.contains('/'))) {
          formula = title;
          type = 'FORMULA';
          // Count 'variable' occurrences to initialize internalValues
          int varCount = RegExp(r'\bvariable\b').allMatches(formula).length;
          List<double> internalValues = List.filled(varCount, 0.0);

          currentSection.items.add(
            ItemData(
              title: title,
              options: options,
              inputType: type,
              formula: formula,
              internalValues: internalValues,
            ),
          );
        } else {
          currentSection.items.add(
            ItemData(title: title, options: options, inputType: type),
          );
        }
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
      r'(proyecto:|seccion:|item:|tabs:)|(opciones:|tipo:)|(\|)|(//.*)|([\+\-\*/])',
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
          // Main Keywords (proyecto, seccion, etc)
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFF569CD6),
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else if (match.group(2) != null) {
          // Sub Keywords (opciones, tipo)
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(color: const Color(0xFF9CDCFE)),
            ),
          );
        } else if (match.group(3) != null) {
          // Separator |
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(color: Colors.white24),
            ),
          );
        } else if (match.group(4) != null) {
          // Comments //
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: const Color(0xFF6A9955),
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        } else if (match.group(5) != null) {
          // Math Operators + - * /
          children.add(
            TextSpan(
              text: match.group(0),
              style: style?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
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

  final List<String> _keywords = [
    'proyecto:',
    'seccion:',
    'item:',
    'tabs:',
    'opciones:',
    'tipo:',
    'numerico',
    'texto',
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

      List<String> sectionVariables =
          RegExp(r'seccion:\s*(.+)', caseSensitive: false)
              .allMatches(text)
              .map((m) => m.group(1)!.trim())
              .where(
                (name) =>
                    name.isNotEmpty &&
                    !name.contains('+') &&
                    !name.contains('-'),
              )
              .toList();

      List<String> allSuggestions = [..._keywords, ...sectionVariables];

      final beforeCursor = text.substring(0, _cursorPosition);
      final lastWordMatch = RegExp(
        r'([\wáéíóúñ]+):?$',
      ).firstMatch(beforeCursor);

      if (lastWordMatch != null) {
        final query = lastWordMatch.group(0)!.toLowerCase();
        _suggestions = allSuggestions
            .where(
              (k) =>
                  k.toLowerCase().startsWith(query) && k.toLowerCase() != query,
            )
            .toSet()
            .toList();

        if (_suggestions.isNotEmpty) {
          _showAutocomplete();
        } else {
          _hideAutocomplete();
        }
      } else {
        if (beforeCursor.isEmpty ||
            beforeCursor.endsWith('\n') ||
            beforeCursor.endsWith(' ')) {
          _suggestions = ['proyecto:', 'seccion:', 'item:', 'tabs:'];
          _showAutocomplete();
        } else {
          _hideAutocomplete();
        }
      }
    } else {
      _hideAutocomplete();
    }
    setState(() {});
  }

  void _showAutocomplete() {
    _hideAutocomplete();

    _autocompleteOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: 200,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(50, 40),
          child: Material(
            elevation: 8,
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _suggestions
                  .map(
                    (s) => ListTile(
                      dense: true,
                      title: Text(
                        s,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                      ),
                      onTap: () => _applySuggestion(s),
                    ),
                  )
                  .toList(),
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

  void _applySuggestion(String suggestion) {
    final text = _controller.text;
    final beforeCursor = text.substring(0, _cursorPosition);
    final lastWordMatch = RegExp(r'([\wáéíóúñ]+):?$').firstMatch(beforeCursor);

    String newText;
    int newCursorPos;

    if (lastWordMatch != null) {
      newText = text.replaceRange(
        lastWordMatch.start,
        lastWordMatch.end,
        suggestion,
      );
      newCursorPos = lastWordMatch.start + suggestion.length;
    } else {
      newText =
          text.substring(0, _cursorPosition) +
          suggestion +
          text.substring(_cursorPosition);
      newCursorPos = _cursorPosition + suggestion.length;
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
    String formulaText = item.formula!.split('=')[0].trim();
    List<String> operators = RegExp(
      r'[\+\-\*/]',
    ).allMatches(formulaText).map((m) => m.group(0)!).toList();
    List<String> operands = formulaText.split(RegExp(r'[\+\-\*/]'));

    int varIndex = 0;
    double result = 0;

    for (int i = 0; i < operands.length; i++) {
      String op = operands[i].trim().toLowerCase();
      double val = 0;

      if (op == 'variable') {
        if (varIndex < item.internalValues.length) {
          val = item.internalValues[varIndex++];
        }
      } else if (op.contains('(') && op.endsWith(')')) {
        var parts = op.split('(');
        String secName = parts[0].trim().toLowerCase();
        String itemName = parts[1].replaceAll(')', '').trim().toLowerCase();
        val = _resolveScopedItem(secName, itemName);
      } else {
        val = double.tryParse(op) ?? _resolveGlobalIdentifier(op, knownTotals);
      }

      if (i == 0) {
        result = val;
      } else {
        String operator = operators[i - 1];
        if (operator == '+') {
          result += val;
        } else if (operator == '-') {
          result -= val;
        } else if (operator == '*') {
          result *= val;
        } else if (operator == '/') {
          result = val != 0 ? result / val : 0;
        }
      }
    }
    return result;
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
                      child: ProjectCard(
                        title: item.title,
                        item: item,
                        onFormulaChanged: () =>
                            setState(() => _calculateTotals()),
                        chips: item.options.isEmpty ? null : item.options,
                        selectedIndex: item.options.isEmpty ? null : 0,
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
                    style: const TextStyle(color: Colors.white),
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
    int varIndex = 0;

    for (int i = 0; i < operands.length; i++) {
      String op = operands[i].trim();
      if (op.toLowerCase() == 'variable') {
        final int currentIdx = varIndex++;
        children.add(
          Container(
            width: 60,
            height: 35,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF81D4FA).withValues(alpha: 0.3),
              ),
            ),
            child: TextField(
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (val) {
                setState(() {
                  widget.item.internalValues[currentIdx] =
                      double.tryParse(val) ?? 0;
                  widget.onFormulaChanged();
                });
              },
            ),
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
