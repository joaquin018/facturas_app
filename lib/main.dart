import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';
import 'editor_vscode.dart';

const String exampleProjectCode = """Configuración General:
  Variables Globales:
    IVA: 21
    Retención: 15
    Mensaje: "Presupuesto válido por 30 días"

Instalación Eléctrica:
  Materiales:
    Caja Embutida: 1..20
    Cable 2.5mm: Rojo, Verde, Blanco
    Térmico 25A: 1..5

  Mano de Obra:
    Horas Oficial: variable
    Horas Ayudante: variable
    Precio Hora: 25
    Subtotal MO: (Horas Oficial + Horas Ayudante) * Precio Hora = Total

  Cálculos y Totales:
    Materiales Totales: Materiales.total = Suma Materiales
    Mano de Obra Total: Mano de Obra.total = Suma MO
    
    # Ejemplo de Condicional 'if' (Ruby style)
    Descuento Especial: Suma Materiales * 0.10 if Suma Materiales > 500 = Descuento
    
    Subtotal Neto: Suma Materiales + Suma MO - Descuento = Neto
    IVA Calculado: Neto * (IVA / 100) = IVA
    
    # Ejemplo de Propiedades de Sección (Python/Ruby style)
    Estadística: "Has usado {Materiales.count} tipos de materiales con un promedio de {Materiales.avg}"

Finalización:
  Resumen:
    Total Final: Neto + IVA = Total
    Aviso: "El total a pagar es {Total}. {Mensaje}"
    Extra: 50 unless Total > 2000 = Cargo Envío""";

void main() {
  runApp(const FacturasApp());
}

// --- DATABASE & PERSISTENCE ---

class SavedProject {
  final int? id;
  final String name;
  final String code;
  final String valuesJson;

  SavedProject({
    this.id,
    required this.name,
    required this.code,
    required this.valuesJson,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'code': code, 'valuesJson': valuesJson};
  }

  factory SavedProject.fromMap(Map<String, dynamic> map) {
    return SavedProject(
      id: map['id'],
      name: map['name'],
      code: map['code'],
      valuesJson: map['valuesJson'],
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('projects.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        valuesJson TEXT NOT NULL
      )
    ''');
  }

  Future<int> createProject(SavedProject project) async {
    final db = await instance.database;
    return await db.insert('projects', project.toMap());
  }

  Future<List<SavedProject>> getAllProjects() async {
    final db = await instance.database;
    final result = await db.query('projects', orderBy: 'id DESC');
    return result.map((json) => SavedProject.fromMap(json)).toList();
  }

  Future<int> updateProject(SavedProject project) async {
    final db = await instance.database;
    return await db.update(
      'projects',
      project.toMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  Future<int> deleteProject(int id) async {
    final db = await instance.database;
    return await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }
}

// --- APP ---

class FacturasApp extends StatelessWidget {
  const FacturasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Facturas App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF81D4FA),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const ProjectListScreen(),
    );
  }
}

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<SavedProject> _projects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshProjects();
  }

  Future<void> _refreshProjects() async {
    setState(() => _isLoading = true);
    var projects = await DatabaseHelper.instance.getAllProjects();

    if (projects.isEmpty) {
      final exampleProject = SavedProject(
        name: "Ejemplos de uso",
        code: exampleProjectCode,
        valuesJson: "{}",
      );
      await DatabaseHelper.instance.createProject(exampleProject);
      projects = await DatabaseHelper.instance.getAllProjects();
    }

    setState(() {
      _projects = projects;
      _isLoading = false;
    });
  }

  Future<void> _addProject() async {
    String projectName = "";
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text(
          "Crear Nuevo Proyecto",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Container(
          width: 300,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Nuevo Proyecto",
              hintStyle: TextStyle(color: Colors.grey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (val) => projectName = val,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    "Cancelar",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, projectName),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF81D4FA),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    "Crear",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      final defaultCode = """Inicio:
  General:
    Resultado: variable + variable = Total""";

      final newProject = SavedProject(
        name: result,
        code: defaultCode,
        valuesJson: "{}",
      );
      await DatabaseHelper.instance.createProject(newProject);
      _refreshProjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                "PROYECTOS",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _projects.isEmpty
                    ? const Center(
                        child: Text(
                          "No hay proyectos aún",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _projects.length,
                        itemBuilder: (context, index) {
                          final project = _projects[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: InkWell(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ProjectEditorWrapper(project: project),
                                  ),
                                );
                                _refreshProjects();
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF81D4FA,
                                        ).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.description,
                                        color: Color(0xFF81D4FA),
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: Text(
                                        project.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Color(0xFFFF5252),
                                      ),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            backgroundColor: const Color(
                                              0xFF1E1E1E,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(28),
                                            ),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(height: 10),
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    16,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFFF5252,
                                                    ).withValues(alpha: 0.1),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.warning_amber_rounded,
                                                    color: Color(0xFFFF5252),
                                                    size: 40,
                                                  ),
                                                ),
                                                const SizedBox(height: 24),
                                                const Text(
                                                  "¿Eliminar Proyecto?",
                                                  style: TextStyle(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  "Se eliminará permanentemente:\n\"${project.name}\"",
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 14,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                            actionsAlignment:
                                                MainAxisAlignment.center,
                                            actionsPadding:
                                                const EdgeInsets.only(
                                                  bottom: 24,
                                                  left: 16,
                                                  right: 16,
                                                ),
                                            actions: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            context,
                                                            false,
                                                          ),
                                                      style: TextButton.styleFrom(
                                                        backgroundColor: Colors
                                                            .white
                                                            .withValues(
                                                               alpha: 0.05,
                                                             ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                               vertical: 20,
                                                            ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                24,
                                                              ),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        "Atrás",
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            context,
                                                            true,
                                                          ),
                                                      style: TextButton.styleFrom(
                                                        backgroundColor:
                                                            const Color(
                                                              0xFFFF5252,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                               vertical: 20,
                                                            ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                24,
                                                              ),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        "Eliminar",
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          await DatabaseHelper.instance
                                              .deleteProject(project.id!);
                                          _refreshProjects();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProject,
        backgroundColor: const Color(0xFF81D4FA),
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.add, size: 32),
      ),
    );
  }
}

class ProjectEditorWrapper extends StatefulWidget {
  final SavedProject project;
  const ProjectEditorWrapper({super.key, required this.project});

  @override
  State<ProjectEditorWrapper> createState() => _ProjectEditorWrapperState();
}

class _ProjectEditorWrapperState extends State<ProjectEditorWrapper> {
  late String _pseudocode;
  late ProjectData _projectData;

  @override
  void initState() {
    super.initState();
    _pseudocode = widget.project.code;
    _projectData = PseudocodeParser.parse(_pseudocode, title: widget.project.name);
    _applySavedValues();
  }

  void _applySavedValues() {
    try {
      Map<String, dynamic> values = jsonDecode(widget.project.valuesJson);
      for (var tab in _projectData.tabs) {
        for (var section in tab.sections) {
          for (var item in section.items) {
            String key = "${tab.title}_${section.title}_${item.title}";
            if (values.containsKey(key)) {
              if (item.inputType == 'FORMULA') {
                Map<String, dynamic> internal = values[key] is Map
                    ? Map<String, dynamic>.from(values[key])
                    : {};
                item.variableValues = internal.map(
                  (k, v) => MapEntry(k, (v as num).toDouble()),
                );
              } else {
                item.currentValue = (values[key] as num).toDouble();
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error applying saved values: $e");
    }
  }

  Future<void> _saveChanges() async {
    Map<String, dynamic> values = {};
    for (var tab in _projectData.tabs) {
      for (var section in tab.sections) {
        for (var item in section.items) {
          String key = "${tab.title}_${section.title}_${item.title}";
          if (item.inputType == 'FORMULA') {
            values[key] = item.variableValues;
          } else {
            values[key] = item.currentValue;
          }
        }
      }
    }

    final updatedProject = SavedProject(
      id: widget.project.id,
      name: widget.project.name,
      code: _pseudocode,
      valuesJson: jsonEncode(values),
    );

    await DatabaseHelper.instance.updateProject(updatedProject);
  }

  void _updateProject(String newCode) {
    setState(() {
      _pseudocode = newCode;
      _projectData = PseudocodeParser.parse(newCode, title: widget.project.name);
      _saveChanges();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainSplitScreen(
      initialCode: _pseudocode,
      projectData: _projectData,
      onChanged: _updateProject,
    );
  }
}
