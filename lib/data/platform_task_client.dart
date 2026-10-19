import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/task_record.dart';

class PlatformRequestException implements Exception {
  const PlatformRequestException(
    this.message, [
    this.statusCode,
    this.retryable = false,
    bool? requiresReauth,
  ]) : requiresReauth =
           requiresReauth ?? (statusCode == 401 || statusCode == 403);
  final String message;
  final int? statusCode;
  final bool retryable;
  final bool requiresReauth;
  @override
  String toString() => message;
}

class PlatformNetworkException extends PlatformRequestException {
  const PlatformNetworkException(this.kind)
    : super('网络不稳定，请稍后再试', 503, true, false);
  final String kind;
}

class HaokeCredentials {
  const HaokeCredentials({required this.token, required this.ticket});
  final String token;
  final String ticket;
}

class PlatformTaskBatch {
  const PlatformTaskBatch({
    required this.accountId,
    required this.tasks,
    required this.warnings,
    required this.successfulCourses,
    required this.syncedAt,
  });
  final String accountId;
  final List<TaskRecord> tasks;
  final List<String> warnings;
  final int successfulCourses;
  final DateTime syncedAt;
}

({String state, bool completed}) canvasSubmissionStatus(dynamic submission) {
  final row = submission is Map ? submission : const {};
  final state = row['excused'] == true
      ? 'excused'
      : (row['workflow_state'] as String?) ?? 'unknown';
  final recorded =
      row['submitted_at'] is String &&
      DateTime.tryParse(row['submitted_at']) != null;
  return (
    state: state,
    completed:
        state == 'excused' ||
        state == 'submitted' ||
        state == 'pending_review' ||
        (state != 'unsubmitted' && recorded),
  );
}

DateTime? haokeDeadline(dynamic value) {
  if (value == null || value == '' || '$value'.startsWith('9999')) return null;
  var text = '$value'.trim().replaceFirst(' ', 'T');
  if (!RegExp(r'Z$|[+-]\d\d:\d\d$').hasMatch(text)) text += '+08:00';
  final time = DateTime.tryParse(text);
  if (time == null) throw const PlatformRequestException('好课截止时间格式无法识别');
  return time.toUtc();
}

int haokeColumnCategory(Map column) {
  if ('${column['columnType']}' != '30' && column['columnCode'] != 'examines') {
    return 0;
  }
  final icon = '${column['iconPath'] ?? ''}'
      .split(RegExp(r'[?#]'))
      .first
      .split('/')
      .last;
  return const {
        'icon-1.svg': 1,
        'icon-151.svg': 2,
        'icon-2.svg': 4,
        'icon-6.svg': 16,
        'icon-5.svg': 8,
      }[icon] ??
      0;
}

TaskRecord normalizeHaokeTask(
  Map row,
  Map course,
  Map column,
  String accountId,
  DateTime syncedAt,
) {
  if (row['taskId'] == null ||
      row['taskName'] is! String ||
      (row['taskName'] as String).trim().isEmpty) {
    throw const PlatformRequestException('好课任务缺少编号或标题');
  }
  final returned = '${row['continueType']}' == '20';
  final completed =
      !returned &&
      ('${row['myStatus']}' == '20' ||
          '${row['myStatus']}' == '30' ||
          '${row['exemptFlag']}' == '1');
  final url = Uri.https(
    'tongji.aihaoke.net',
    '/student/course/${course['classId']}/task',
    {
      'instanceId': '${course['instanceId']}',
      if (column['columnId'] != null) 'columnId': '${column['columnId']}',
      'taskType': '${column['columnCode'] ?? 'task'}',
      if (column['uniqueId'] != null) 'uniqueId': '${column['uniqueId']}',
    },
  );
  return TaskRecord(
    id: 'haoke:$accountId:${course['classId']}:${row['taskId']}',
    title: _truncate((row['taskName'] as String).trim(), 200),
    course: _truncate((course['instanceName'] as String).trim(), 100),
    platform: 'haoke',
    source: 'haoke',
    accountId: accountId,
    createdAt: syncedAt,
    syncedAt: syncedAt,
    haokeCategories: (column['haokeCategories'] as int?) ?? 0,
    dueAt: haokeDeadline(row['endTime']),
    completed: completed,
    url: url.toString(),
    submissionState: returned
        ? 'returned'
        : completed
        ? 'submitted'
        : 'unsubmitted',
    note:
        '好课接口同步 · ${returned
            ? '已退回，需重新提交'
            : row['myStatus'] == 20
            ? '待评价'
            : completed
            ? '已完成'
            : '待提交或待核对'}',
  );
}

String _truncate(String text, int limit) =>
    text.length <= limit ? text : text.substring(0, limit);

class PlatformTaskClient {
  PlatformTaskClient({HttpClient? httpClient})
    : _http = httpClient ?? HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 15);
  }
  final HttpClient _http;
  bool _closed = false;
  static final _random = Random.secure();

  void close() {
    _closed = true;
    _http.close(force: true);
  }

  static String _requestId() {
    final bytes = List.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<({dynamic data, String? link})> _request(
    Uri uri,
    String token,
    DateTime deadline, {
    Map<String, dynamic>? body,
    int limit = 2000000,
  }) async {
    if (_closed || !deadline.isAfter(DateTime.now())) {
      throw const PlatformRequestException('同步已取消或超时，已有作业保留', 503);
    }
    final budget = Duration(
      milliseconds: min(
        15000,
        deadline.difference(DateTime.now()).inMilliseconds,
      ),
    );
    HttpClientRequest? request;
    StreamIterator<List<int>>? iterator;
    final timer = Stopwatch()..start();
    Duration remaining() {
      final milliseconds = budget.inMilliseconds - timer.elapsedMilliseconds;
      if (milliseconds <= 0) throw TimeoutException('平台读取超时');
      return Duration(milliseconds: milliseconds);
    }

    try {
      request = await _http
          .openUrl(body == null ? 'GET' : 'POST', uri)
          .timeout(remaining());
      request.followRedirects = false;
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.set('Accept', 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.headers.set('X-Language', 'zh-CN');
        request.write(jsonEncode({...body, 'requestId': _requestId()}));
      }
      final response = await request.close().timeout(remaining());
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final status = response.statusCode;
        final canvas = uri.host == 'canvas.tongji.edu.cn';
        final requiresReauth =
            status == 401 &&
            (response.headers.value('www-authenticate')?.isNotEmpty ?? false);
        throw PlatformRequestException(
          status == 401
              ? canvas && !requiresReauth
                    ? 'Canvas 读取权限不足（401，未返回凭证认证失败标识），请核对课程权限；自动检查继续'
                    : canvas
                    ? 'Canvas 拒绝当前 Token（401），请核对到期或撤销情况并更新；学校允许时可将新个人令牌到期日期留空。已有作业保留'
                    : '平台拒绝当前凭证（401），请重新连接；已有作业保留'
              : status == 403
              ? '平台拒绝访问（403），请核对权限；不能据此认定凭证到期'
              : status == 429
              ? '请求过于频繁，请稍后刷新'
              : '平台读取失败（HTTP $status）',
          status,
          [500, 502, 503, 504].contains(status),
          canvas ? requiresReauth : null,
        );
      }
      final bytes = <int>[];
      iterator = StreamIterator(response);
      while (await iterator.moveNext().timeout(remaining())) {
        if (bytes.length + iterator.current.length > limit) {
          throw const PlatformRequestException('平台响应超过读取上限', 413);
        }
        bytes.addAll(iterator.current);
      }
      return (
        data: jsonDecode(utf8.decode(bytes)),
        link: response.headers.value('link'),
      );
    } on PlatformRequestException {
      rethrow;
    } on FormatException {
      throw const PlatformRequestException('平台响应不是有效 JSON', 502);
    } on TimeoutException {
      throw const PlatformNetworkException('timeout');
    } on HandshakeException {
      throw const PlatformNetworkException('tls');
    } on SocketException {
      throw const PlatformNetworkException('connection');
    } on HttpException {
      throw const PlatformNetworkException('http_connection');
    } catch (_) {
      throw const PlatformRequestException('暂时无法更新，请稍后再试', 503);
    } finally {
      await iterator?.cancel();
      request?.abort();
    }
  }

  Future<PlatformTaskBatch> collectCanvas(String token) async {
    if (token.isEmpty || token.length > 2048 || RegExp(r'\s').hasMatch(token)) {
      throw const PlatformRequestException('请输入有效的 Canvas Token', 400);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    final origin = Uri.parse('https://canvas.tongji.edu.cn');
    Future<({dynamic data, String? link})> request(String path) {
      final uri = origin.resolve(path);
      if (uri.origin != origin.origin ||
          uri.userInfo.isNotEmpty ||
          !uri.path.startsWith('/api/v1/')) {
        throw const PlatformRequestException('分页地址不属于同济 Canvas API', 502);
      }
      return _request(uri, token, deadline);
    }

    Future<List<dynamic>> pages(String path) async {
      final rows = <dynamic>[];
      final seen = <String>{};
      String? next = path;
      while (next != null) {
        final canonical = origin.resolve(next).toString();
        if (!seen.add(canonical) || seen.length > 50) {
          throw const PlatformRequestException('分页重复或超过上限', 502);
        }
        final response = await request(next);
        if (response.data is! List) {
          throw const PlatformRequestException('Canvas 列表格式发生变化', 502);
        }
        rows.addAll(response.data as List);
        if (rows.length > 10000) {
          throw const PlatformRequestException('列表超过同步上限', 413);
        }
        next = RegExp(
          r'<([^>]+)>;\s*rel="next"',
        ).firstMatch(response.link ?? '')?.group(1);
      }
      return rows;
    }

    final profile = (await request('/api/v1/users/self/profile')).data;
    if (profile is! Map || !RegExp(r'^\d+$').hasMatch('${profile['id']}')) {
      throw const PlatformRequestException('无法确认 Canvas 账号', 502);
    }
    final accountId = '${profile['id']}';
    final courses = await pages(
      '/api/v1/courses?enrollment_type=student&enrollment_state=active&per_page=100',
    );
    if (courses.length > 100) {
      throw const PlatformRequestException('课程数量超过 100 门', 413);
    }
    final tasks = <String, TaskRecord>{};
    final warnings = <String>[];
    final syncedAt = DateTime.now().toUtc();
    var successful = 0;
    for (final course in courses) {
      if (course is! Map || !RegExp(r'^\d+$').hasMatch('${course['id']}')) {
        throw const PlatformRequestException('Canvas 课程编号无效', 502);
      }
      try {
        final rows = await pages(
          '/api/v1/courses/${course['id']}/assignments?include[]=submission&override_assignment_dates=true&per_page=100',
        );
        final courseTasks = <String, TaskRecord>{};
        for (final row in rows) {
          if (row is! Map ||
              !RegExp(r'^\d+$').hasMatch('${row['id']}') ||
              row['name'] is! String) {
            throw const PlatformRequestException('Canvas 作业字段无效', 502);
          }
          if (row['published'] == false) continue;
          final status = canvasSubmissionStatus(row['submission']);
          final due = row['due_at'] == null
              ? null
              : DateTime.tryParse('${row['due_at']}');
          if (row['due_at'] != null && due == null) {
            throw const PlatformRequestException('Canvas 截止时间无效', 502);
          }
          final id = 'canvas:$accountId:${course['id']}:${row['id']}';
          courseTasks[id] = TaskRecord(
            id: id,
            title: _truncate(row['name'], 200),
            course: _truncate(
              '${course['name'] ?? course['course_code'] ?? '课程 ${course['id']}'}',
              100,
            ),
            platform: 'canvas',
            source: 'canvas',
            accountId: accountId,
            createdAt: syncedAt,
            syncedAt: syncedAt,
            dueAt: due?.toUtc(),
            completed: status.completed,
            submissionState: status.state,
            url:
                '${origin.origin}/courses/${course['id']}/assignments/${row['id']}',
            note: status.state == 'unknown'
                ? '接口未提供个人提交状态，请在原平台核对。'
                : '由 Canvas 官方 API 同步；完整要求与最终状态请在原平台核对。',
          );
        }
        if (tasks.length + courseTasks.length > 3000) {
          throw const PlatformRequestException('作业超过 3000 项', 413);
        }
        tasks.addAll(courseTasks);
        successful++;
      } on PlatformRequestException catch (error) {
        if (error.requiresReauth ||
            [413, 429].contains(error.statusCode) ||
            !deadline.isAfter(DateTime.now()) ||
            _closed) {
          rethrow;
        }
        warnings.add('课程 ${course['id']}：${error.message}');
      } on ArgumentError {
        warnings.add('课程 ${course['id']}：作业字段无效');
      }
    }
    if (courses.isNotEmpty && successful == 0) {
      throw const PlatformRequestException('所有课程读取失败，原列表保留', 502);
    }
    return PlatformTaskBatch(
      accountId: accountId,
      tasks: tasks.values.toList(),
      warnings: warnings,
      successfulCourses: successful,
      syncedAt: syncedAt,
    );
  }

  Future<PlatformTaskBatch> collectHaoke(String token) async {
    if (token.trim().isEmpty || token.length > 4096) {
      throw const PlatformRequestException('请输入有效的好课令牌', 400);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 110));
    const paths = [
      '/api/teach/instance/listMyClass',
      '/api/learn/task/listTask',
      '/api/auth/queryCurrentUserInfo',
      '/api/learn/task/queryClassInfo',
      '/api/learn/examine/examineList',
    ];
    Future<Map> postOnce(String path, Map<String, dynamic> body) async {
      if (!paths.contains(path)) {
        throw const PlatformRequestException('接口不在只读名单内', 400);
      }
      final value = (await _request(
        Uri.https('tongji.aihaoke.net', path),
        token.trim(),
        deadline,
        body: body,
      )).data;
      if (value is! Map) {
        throw const PlatformRequestException('好课响应格式发生变化', 502);
      }
      if (value['code'] != 200) {
        final code = int.tryParse('${value['code']}');
        throw PlatformRequestException(
          code == 401
              ? '好课拒绝当前令牌，请重新连接'
              : code == 403
              ? '好课拒绝访问，请核对账号权限'
              : '好课接口读取失败',
          code ?? 502,
          [500, 502, 503, 504].contains(code),
        );
      }
      if (value['data'] is! Map) {
        throw const PlatformRequestException('好课响应缺少 data', 502);
      }
      return value['data'] as Map;
    }

    Future<Map> post(String path, Map<String, dynamic> body) async {
      try {
        return await postOnce(path, body);
      } on PlatformRequestException catch (error) {
        if (!error.retryable || _closed || !deadline.isAfter(DateTime.now())) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return postOnce(path, body);
      }
    }

    // This official read response was verified to expose data.userInfo.userId.
    final identity = await post('/api/auth/queryCurrentUserInfo', {});
    final user = identity['userInfo'];
    if (user is! Map ||
        user['userId'] == null ||
        '${user['userId']}'.isEmpty ||
        '${user['userId']}'.length > 100) {
      throw const PlatformRequestException('无法确认好课账号，请重新连接', 502);
    }
    final accountId = '${user['userId']}';
    final listing = await post(paths[0], {'instanceName': ''});
    if (listing['teachClassResponseList'] is! List) {
      throw const PlatformRequestException('好课课程列表格式发生变化', 502);
    }
    final courses = <String, Map>{};
    for (final row in listing['teachClassResponseList'] as List) {
      if (row is! Map) throw const PlatformRequestException('好课课程字段无效', 502);
      courses['${row['classId']}'] = row;
    }
    final tasks = <String, TaskRecord>{};
    final warnings = <String>[];
    final syncedAt = DateTime.now().toUtc();
    var successful = 0;
    for (final course in courses.values) {
      try {
        final classId = int.tryParse('${course['classId']}');
        if (classId == null ||
            classId <= 0 ||
            course['instanceName'] is! String ||
            (course['instanceName'] as String).trim().isEmpty) {
          throw const PlatformRequestException('好课课程字段无效', 502);
        }
        final courseTasks = <String, TaskRecord>{};
        Future<List<Map>> readList(
          String path,
          Map<String, dynamic> body,
          String idKey,
        ) async {
          final rows = <Map>[];
          final fingerprints = <String>{};
          for (var pageNo = 1; pageNo <= 200; pageNo++) {
            final data = await post(path, {
              ...body,
              'page': {'pageNo': pageNo, 'pageSize': 50},
            });
            final total = int.tryParse('${data['totalRowCount']}');
            if (data['rowList'] is! List || total == null || total < 0) {
              throw const PlatformRequestException('好课分页格式发生变化', 502);
            }
            final page = data['rowList'] as List;
            if (page.any((row) => row is! Map)) {
              throw const PlatformRequestException('好课任务字段无效', 502);
            }
            final fingerprint = jsonEncode(
              page.map((row) => row[idKey]).toList(),
            );
            if (page.isNotEmpty && !fingerprints.add(fingerprint)) {
              throw const PlatformRequestException('好课重复返回同一页', 502);
            }
            rows.addAll(page.cast<Map>());
            if (rows.length >= total) return rows;
            if (page.isEmpty) {
              throw const PlatformRequestException('未读取全部好课分页', 502);
            }
          }
          throw const PlatformRequestException('未读取全部好课分页', 502);
        }

        final body = <String, dynamic>{
          'classId': classId,
          'orderType': 0,
          'searchText': '',
          'status': 0,
          'taskTypes': <dynamic>[],
          'requireFlag': null,
          'exemptFlag': null,
        };
        // Preserve all learning tasks; classify by official column membership.
        for (final row in await readList(paths[1], body, 'taskId')) {
          final task = normalizeHaokeTask(
            row,
            course,
            const {},
            accountId,
            syncedAt,
          );
          courseTasks[task.id] = task;
        }
        final info = await post('/api/learn/task/queryClassInfo', {
          'classId': classId,
        });
        if (info['columnList'] is! List) {
          throw const PlatformRequestException('好课课程栏目格式发生变化', 502);
        }
        Future<void> visit(List columns) async {
          for (final column in columns.cast<Map>()) {
            final category = haokeColumnCategory(column);
            if (category != 0 &&
                column['columnCode'] != 'examines' &&
                column['columnId'] != null) {
              for (final row in await readList(paths[1], {
                ...body,
                'columnId': column['columnId'],
              }, 'taskId')) {
                final task = normalizeHaokeTask(
                  row,
                  course,
                  column,
                  accountId,
                  syncedAt,
                );
                courseTasks[task.id] = task.copyWith(
                  haokeCategories:
                      (courseTasks[task.id]?.haokeCategories ?? 0) | category,
                );
              }
            } else if (category == 8 && column['columnCode'] == 'examines') {
              final exams = await readList('/api/learn/examine/examineList', {
                'teachClassId': classId,
                'instanceId': course['instanceId'],
                'searchText': '',
                'examineStatus': 0,
              }, 'examineId');
              for (final parent in exams) {
                for (final row in [
                  parent,
                  if (parent['makeupExam'] is Map &&
                      parent['makeupExam']['examineId'] != null)
                    parent['makeupExam'] as Map,
                ]) {
                  if (row['examineId'] == null ||
                      row['examineName'] is! String) {
                    throw const PlatformRequestException('好课考试缺少编号或标题', 502);
                  }
                  final completed = '${row['submitFlag']}' == '1';
                  final url = Uri.https(
                    'tongji.aihaoke.net',
                    '/student/course/$classId/examines/home',
                    {
                      'instanceId': '${course['instanceId']}',
                      'examineId': '${row['examineId']}',
                    },
                  );
                  final task = TaskRecord(
                    id: 'haoke:$accountId:$classId:exam:${row['examineId']}',
                    title: _truncate(row['examineName'], 200),
                    course: _truncate(course['instanceName'], 100),
                    platform: 'haoke',
                    source: 'haoke',
                    accountId: accountId,
                    createdAt: syncedAt,
                    syncedAt: syncedAt,
                    dueAt: haokeDeadline(row['endTime']),
                    completed: completed,
                    submissionState: completed ? 'submitted' : 'unsubmitted',
                    haokeCategories: 8,
                    url: url.toString(),
                    note: '好课考试同步 · ${completed ? '已提交' : '待参加或待核对'}',
                  );
                  courseTasks[task.id] = task;
                }
              }
            }
            if (column['subList'] is List) await visit(column['subList']);
          }
        }

        await visit(info['columnList']);
        tasks.addAll(courseTasks);
        successful++;
      } on PlatformRequestException catch (error) {
        if ([401, 403, 413, 429].contains(error.statusCode) ||
            _closed ||
            !deadline.isAfter(DateTime.now())) {
          rethrow;
        }
        warnings.add(
          '${_truncate('${course['instanceName']}', 100)}：${error.message}',
        );
      } on ArgumentError {
        warnings.add('${_truncate('${course['instanceName']}', 100)}：作业字段无效');
      }
    }
    if (courses.isNotEmpty && successful == 0) {
      throw const PlatformRequestException('所有好课课程读取失败，原列表保留', 502);
    }
    return PlatformTaskBatch(
      accountId: accountId,
      tasks: tasks.values.toList(),
      warnings: warnings,
      successfulCourses: successful,
      syncedAt: syncedAt,
    );
  }

  Future<String> verifyHaokeAccount(String token) async {
    if (token.isEmpty || token.length > 4096) {
      throw const PlatformRequestException('好课登录信息未就绪');
    }
    final response = await _request(
      Uri.https('tongji.aihaoke.net', '/api/auth/queryCurrentUserInfo'),
      token,
      DateTime.now().add(const Duration(seconds: 15)),
      body: {},
      limit: 65536,
    );
    final value = response.data;
    if (value is! Map || value['code'] != 200) {
      final code = value is Map ? int.tryParse('${value['code']}') : null;
      throw PlatformRequestException('好课登录验证未完成，请稍后刷新或重新连接', code ?? 502);
    }
    final data = value['data'];
    final user = data is Map ? data['userInfo'] : null;
    final account = user is Map ? user['userId'] : null;
    if ((account is! String && account is! int) ||
        '$account'.trim().isEmpty ||
        '$account'.length > 100) {
      throw const PlatformRequestException('无法确认好课账号，请重新连接', 502);
    }
    return '$account';
  }

  Future<HaokeCredentials> readHaokeCredentials(String token) async {
    if (token.isEmpty || token.length > 4096) {
      throw const PlatformRequestException('好课登录信息未就绪');
    }
    final response = await _request(
      Uri.https('tongji.aihaoke.net', '/api/auth/queryCurrentUserInfo'),
      token,
      DateTime.now().add(const Duration(seconds: 15)),
      body: {},
      limit: 65536,
    );
    final value = response.data;
    final data = value is Map && value['code'] == 200 ? value['data'] : null;
    if (data is! Map ||
        data['token'] is! String ||
        data['ticket'] is! String ||
        (data['token'] as String).isEmpty ||
        (data['ticket'] as String).isEmpty ||
        (data['token'] as String).length > 4096 ||
        (data['ticket'] as String).length > 4096) {
      throw const PlatformRequestException('好课未返回完整登录凭证，请重新登录');
    }
    return HaokeCredentials(token: data['token'], ticket: data['ticket']);
  }

  Future<HaokeCredentials> renewHaoke(HaokeCredentials credentials) async {
    if (credentials.token.isEmpty ||
        credentials.ticket.isEmpty ||
        credentials.token.length > 4096 ||
        credentials.ticket.length > 4096) {
      throw const PlatformRequestException('好课续期凭证缺失，请重新连接', 401);
    }
    final response = await _request(
      Uri.https('tongji.aihaoke.net', '/api/auth/tokenLogin'),
      credentials.token,
      DateTime.now().add(const Duration(seconds: 15)),
      body: {'token': credentials.token, 'ticket': credentials.ticket},
      limit: 65536,
    );
    final value = response.data;
    if (value is! Map || value['code'] != 200) {
      final code = value is Map ? int.tryParse('${value['code']}') : null;
      throw PlatformRequestException(
        '好课续期被拒绝，请稍后刷新或重新登录',
        [401, 403].contains(code) ? code : 503,
        [429, 500, 502, 503, 504].contains(code),
      );
    }
    final data = value['data'];
    if (data is! Map ||
        data['token'] is! String ||
        data['ticket'] is! String ||
        (data['token'] as String).isEmpty ||
        (data['ticket'] as String).isEmpty ||
        (data['token'] as String).length > 4096 ||
        (data['ticket'] as String).length > 4096) {
      throw const PlatformRequestException('好课续期未返回完整凭证', 502);
    }
    return HaokeCredentials(token: data['token'], ticket: data['ticket']);
  }
}
