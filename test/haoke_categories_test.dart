import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/platform_task_client.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/data/task_repository.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'platform_task_client_test.dart' show FakeHttpClient, Reply;

TaskRecord task(int categories, {String platform = 'haoke'}) => TaskRecord(
  id: 'haoke:23:42:1',
  title: '测试任务',
  course: '数学',
  platform: platform,
  source: platform,
  accountId: '23',
  createdAt: DateTime.utc(2026),
  haokeCategories: categories,
);

void main() {
  setUpAll(sqfliteFfiInit);
  test('五种图标全部32种组合、重叠栏目和未分类任务', () {
    for (var selected = 0; selected <= 31; selected++) {
      expect(
        task(0, platform: 'canvas').matchesHaokeCategories(selected),
        isTrue,
      );
      for (final category in [0, 1, 2, 4, 8, 16, 5]) {
        expect(
          task(category).matchesHaokeCategories(selected),
          selected == 31 || (category & selected) != 0,
        );
      }
    }
  });
  test('图标不受栏目改名影响，同图标合并且不混入内置话题', () {
    for (final name in ['作业', '阶段小测', '期中', '期末']) {
      expect(
        haokeColumnCategory({
          'columnType': 30,
          'columnName': name,
          'iconPath':
              'https://haoke-static.aihaoke.net/repository/column/icon-1.svg',
        }),
        1,
      );
    }
    expect(
      haokeColumnCategory({
        'columnType': 30,
        'columnName': '作业',
        'iconPath': 'icon-999.svg',
      }),
      0,
    );
    expect(
      haokeColumnCategory({
        'columnType': 20,
        'columnCode': 'topics',
        'iconPath': 'icon-6.svg',
      }),
      0,
    );
    expect(
      haokeColumnCategory({
        'columnType': 30,
        'iconPath': 'icon-151.svg?v=2#icon',
      }),
      2,
    );
  });
  test('按图标栏目成员区分相同题型，完整分页且读取考试与补考', () async {
    final http = FakeHttpClient((request) {
      final body = jsonDecode(request.body.toString());
      Object data;
      switch (request.uri.path) {
        case '/api/auth/queryCurrentUserInfo':
          data = {
            'userInfo': {'userId': 23},
          };
        case '/api/teach/instance/listMyClass':
          data = {
            'teachClassResponseList': [
              {'classId': 42, 'instanceId': 73, 'instanceName': '数学'},
            ],
          };
        case '/api/learn/task/queryClassInfo':
          data = {
            'columnList': [
              {
                'columnId': 11,
                'columnName': '期末',
                'columnType': 30,
                'iconPath': 'icon-1.svg',
              },
              {
                'columnId': 12,
                'columnName': '自定义资源',
                'columnType': 30,
                'iconPath': 'icon-151.svg',
              },
              {
                'columnId': 13,
                'columnName': '随堂内容',
                'columnType': 30,
                'iconPath': 'icon-2.svg',
              },
              {
                'columnId': 14,
                'columnName': '整理思路',
                'columnType': 30,
                'iconPath': 'icon-6.svg',
              },
              {
                'columnCode': 'examines',
                'columnName': '考试',
                'iconPath': 'icon-5.svg',
              },
            ],
          };
        case '/api/learn/examine/examineList':
          expect(body['teachClassId'], 42);
          expect(body['examineStatus'], 0);
          data = {
            'totalRowCount': 1,
            'rowList': [
              {
                'examineId': 1,
                'examineName': '考试',
                'submitFlag': 1,
                'endTime': '2026-10-11 00:00:00',
                'makeupExam': {
                  'examineId': 2,
                  'examineName': '补考',
                  'submitFlag': 0,
                },
              },
            ],
          };
        default:
          final ids = switch (body['columnId']) {
            11 => [1, 5],
            12 => [2],
            13 => [3, 5],
            14 => [6],
            _ => [1, 2, 3, 4, 5, 6],
          };
          expect(body['taskTypes'], isEmpty);
          expect(body['status'], 0);
          final start = ((body['page']['pageNo'] as int) - 1) * 2;
          data = {
            'totalRowCount': ids.length,
            'rowList': ids
                .skip(start)
                .take(2)
                .map(
                  (id) => {
                    'taskId': id,
                    'taskName': '任务$id',
                    'taskType': 50,
                    'myStatus': 10,
                  },
                )
                .toList(),
          };
      }
      return Reply({'code': 200, 'data': data});
    });
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    final result = await client.collectHaoke('fixture');
    expect(result.tasks, hasLength(8));
    expect(result.warnings, isEmpty);
    final rows = {for (final task in result.tasks) task.id: task};
    expect(rows['haoke:23:42:1']!.haokeCategories, 1);
    expect(rows['haoke:23:42:2']!.haokeCategories, 2);
    expect(rows['haoke:23:42:3']!.haokeCategories, 4);
    expect(rows['haoke:23:42:4']!.haokeCategories, 0);
    expect(rows['haoke:23:42:5']!.haokeCategories, 5);
    expect(rows['haoke:23:42:6']!.haokeCategories, 16);
    final exam = rows['haoke:23:42:exam:1']!;
    expect(exam.haokeCategories, 8);
    expect(exam.completed, isTrue);
    expect(exam.dueAt, DateTime.utc(2026, 10, 10, 16));
    expect(exam.url, contains('/examines/home?'));
    expect(rows['haoke:23:42:exam:2']!.completed, isFalse);
  });
  for (final version in [8, 9]) {
    test('v$version升级后保留任务及手动完成，旧小测选择合并为作业/小测', () async {
      final folder = await Directory.systemTemp.createTemp(
        'tj-category-migration-',
      );
      final path = '${folder.path}/schedule.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE app_settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE national_makeup_days(date TEXT PRIMARY KEY,replacement_week INTEGER,replacement_weekday INTEGER,is_holiday INTEGER NOT NULL DEFAULT 0,holiday_name TEXT)',
            );
            await db.execute('''CREATE TABLE memos (
              id TEXT PRIMARY KEY, term_id TEXT NOT NULL, title TEXT NOT NULL,
              location TEXT NOT NULL, color_value INTEGER NOT NULL,
              weekday INTEGER, start_period INTEGER, end_period INTEGER,
              start_week INTEGER, end_week INTEGER, week_type TEXT,
              explicit_weeks TEXT, date TEXT, start_minutes INTEGER, end_minutes INTEGER
            )''');
            await db.execute(
              'CREATE TABLE tasks(id TEXT PRIMARY KEY,title TEXT,course TEXT,platform TEXT,source TEXT,account_id TEXT,created_at TEXT,due_at TEXT,completed INTEGER,manual_completed INTEGER,url TEXT,note TEXT,synced_at TEXT,submission_state TEXT)',
            );
            if (version == 9) {
              await db.execute(
                'ALTER TABLE tasks ADD haoke_categories INTEGER NOT NULL DEFAULT 0',
              );
            }
          },
        ),
      );
      final row = task(
        4,
      ).copyWith(completed: true, manualCompleted: true).toRow();
      if (version == 8) row.remove('haoke_categories');
      await old.insert('tasks', row);
      await old.insert('app_settings', {
        'key': 'task_haoke_visible_categories',
        'value': '5',
      });
      await old.close();
      final db = await ScheduleDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      try {
        final repository = TaskRepository(db.database);
        final migrated = (await repository.loadAll()).single;
        expect(migrated.completed, isTrue);
        expect(migrated.haokeCategories, version == 9 ? 1 : 0);
        expect(await db.loadSetting('task_haoke_visible_categories'), '1');
        await repository.mergePlatform([task(5)]);
        final saved = (await repository.loadAll()).single;
        expect(saved.haokeCategories, 5);
        expect(saved.manualCompleted, isTrue);
        expect(saved.completed, isTrue);
      } finally {
        await db.close();
        // SQLite may leave journal files beside the closed database on macOS.
        await folder.delete(recursive: true);
      }
    });
  }
}
