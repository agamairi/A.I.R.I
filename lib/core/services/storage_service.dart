/// Sqflite-based local storage service providing CRUD for all domain entities.
///
/// Tables: conversations, messages, notebooks, documents, chunks,
/// download_tasks, system_prompts, user_profile.
library;

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class StorageService {
  static const _dbName = 'airi.db';
  static const _dbVersion = 2;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async {
        await _createOrMigrate(db);
      },
      onUpgrade: (db, _, __) async {
        await _createOrMigrate(db);
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await _createOrMigrate(db);
      },
    );
  }

  Future<void> _createOrMigrate(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        modelId TEXT,
        notebookId TEXT,
        customSystemPrompt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        conversationId TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        imageAttachmentPath TEXT,
        FOREIGN KEY (conversationId) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversationId)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS notebooks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        systemPrompt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        chunkSize INTEGER DEFAULT 512,
        chunkOverlap INTEGER DEFAULT 64,
        topK INTEGER DEFAULT 5,
        strictGrounding INTEGER DEFAULT 0,
        citationsEnabled INTEGER DEFAULT 1,
        retrievalMode TEXT DEFAULT 'auto'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        notebookId TEXT NOT NULL,
        fileName TEXT NOT NULL,
        filePath TEXT NOT NULL,
        type TEXT NOT NULL,
        addedAt TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        errorMessage TEXT,
        FOREIGN KEY (notebookId) REFERENCES notebooks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chunks (
        id TEXT PRIMARY KEY,
        documentId TEXT NOT NULL,
        content TEXT NOT NULL,
        chunkIndex INTEGER NOT NULL,
        embedding TEXT,
        FOREIGN KEY (documentId) REFERENCES documents(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chunks_document ON chunks(documentId)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS download_tasks (
        id TEXT PRIMARY KEY,
        modelName TEXT NOT NULL,
        downloadUrl TEXT NOT NULL,
        savePath TEXT NOT NULL,
        status TEXT DEFAULT 'queued',
        progress REAL DEFAULT 0.0,
        totalBytes INTEGER,
        downloadedBytes INTEGER,
        errorMessage TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS system_prompts (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        targetId TEXT,
        content TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_profile (
        id INTEGER PRIMARY KEY DEFAULT 1,
        name TEXT DEFAULT '',
        preferences TEXT DEFAULT '',
        goals TEXT DEFAULT '',
        bio TEXT DEFAULT '',
        communicationStyle TEXT DEFAULT '',
        persistentNotes TEXT DEFAULT '',
        injectInAllChats INTEGER DEFAULT 0,
        injectInSelectedChats INTEGER DEFAULT 0,
        injectInNotebookMode INTEGER DEFAULT 0
      )
    ''');

    await _ensureColumn(db, 'conversations', 'modelId', 'TEXT');
    await _ensureColumn(db, 'conversations', 'notebookId', 'TEXT');
    await _ensureColumn(db, 'conversations', 'customSystemPrompt', 'TEXT');
    await _ensureColumn(db, 'messages', 'imageAttachmentPath', 'TEXT');

    await _ensureColumn(db, 'notebooks', 'systemPrompt', 'TEXT');
    await _ensureColumn(db, 'notebooks', 'chunkSize', 'INTEGER DEFAULT 512');
    await _ensureColumn(db, 'notebooks', 'chunkOverlap', 'INTEGER DEFAULT 64');
    await _ensureColumn(db, 'notebooks', 'topK', 'INTEGER DEFAULT 5');
    await _ensureColumn(
        db, 'notebooks', 'strictGrounding', 'INTEGER DEFAULT 0');
    await _ensureColumn(
        db, 'notebooks', 'citationsEnabled', 'INTEGER DEFAULT 1');
    await _ensureColumn(
        db, 'notebooks', 'retrievalMode', "TEXT DEFAULT 'auto'");

    await _ensureColumn(db, 'documents', 'status', "TEXT DEFAULT 'pending'");
    await _ensureColumn(db, 'documents', 'errorMessage', 'TEXT');

    await _ensureColumn(db, 'download_tasks', 'downloadUrl', "TEXT DEFAULT ''");
    await _ensureColumn(db, 'download_tasks', 'savePath', "TEXT DEFAULT ''");
    await _ensureColumn(
        db, 'download_tasks', 'status', "TEXT DEFAULT 'queued'");
    await _ensureColumn(db, 'download_tasks', 'progress', 'REAL DEFAULT 0.0');
    await _ensureColumn(db, 'download_tasks', 'totalBytes', 'INTEGER');
    await _ensureColumn(db, 'download_tasks', 'downloadedBytes', 'INTEGER');
    await _ensureColumn(db, 'download_tasks', 'errorMessage', 'TEXT');
    await _ensureColumn(db, 'download_tasks', 'createdAt', 'TEXT');

    await _ensureColumn(db, 'user_profile', 'name', "TEXT DEFAULT ''");
    await _ensureColumn(db, 'user_profile', 'preferences', "TEXT DEFAULT ''");
    await _ensureColumn(db, 'user_profile', 'goals', "TEXT DEFAULT ''");
    await _ensureColumn(db, 'user_profile', 'bio', "TEXT DEFAULT ''");
    await _ensureColumn(
        db, 'user_profile', 'communicationStyle', "TEXT DEFAULT ''");
    await _ensureColumn(
        db, 'user_profile', 'persistentNotes', "TEXT DEFAULT ''");
    await _ensureColumn(
      db,
      'user_profile',
      'injectInAllChats',
      'INTEGER DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'user_profile',
      'injectInSelectedChats',
      'INTEGER DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'user_profile',
      'injectInNotebookMode',
      'INTEGER DEFAULT 0',
    );

    // Ensure the single-row profile exists.
    await db.insert(
      'user_profile',
      {'id': 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Generic helpers
  // ---------------------------------------------------------------------------

  Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    return db.insert(table, values,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await database;
    return db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
