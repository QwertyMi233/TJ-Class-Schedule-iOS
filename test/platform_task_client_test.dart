import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/platform_task_client.dart';

void main() {
  FakeHttpClient canvasClient({bool partial = false, String? next}) =>
      FakeHttpClient((request) {
        switch (request.uri.path) {
          case '/api/v1/users/self/profile':
            return Reply({'id': 7});
          case '/api/v1/courses':
            return Reply([
              {'id': 1, 'name': '数学'},
              if (partial) {'id': 2, 'name': '英语'},
            ]);
          case '/api/v1/courses/1/assignments':
            return Reply([
              {
                'id': 10,
                'name': '习题',
                'due_at': '2026-10-08T00:00:00+08:00',
                'submission': {
                  'workflow_state': 'graded',
                  'submitted_at': null,
                },
              },
              {'id': 11, 'name': '隐藏', 'published': false},
            ], link: next);
          default:
            return Reply({}, status: 403);
        }
      });
  test('Canvas 使用个人截止时间与提交状态，部分失败不产生该课程快照', () async {
    final http = canvasClient(partial: true);
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    final batch = await client.collectCanvas('fixture-token');
    expect(batch.accountId, '7');
    expect(batch.tasks.single.completed, isFalse);
    expect(batch.tasks.single.dueAt, DateTime.utc(2026, 10, 7, 16));
    expect(batch.warnings, hasLength(1));
    expect(batch.successfulCourses, 1);
    expect(http.requests.every((r) => !r.followRedirects), isTrue);
    expect(http.requests.last.uri.host, 'canvas.tongji.edu.cn');
    expect(
      http.requests[2].uri.queryParameters['override_assignment_dates'],
      'true',
    );
  });
  test('单门课程401没有认证挑战时继续同步其他课程', () async {
    final http = FakeHttpClient((request) {
      final path = request.uri.path;
      if (path.endsWith('/profile')) return Reply({'id': 7});
      if (path == '/api/v1/courses') {
        return Reply([
          {'id': 1},
          {'id': 2},
        ]);
      }
      if (path.contains('/2/')) return Reply({}, status: 401);
      return Reply([
        {'id': 10, 'name': '习题'},
      ]);
    });
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    final batch = await client.collectCanvas('fixture-token');
    expect(batch.successfulCourses, 1);
    expect(batch.tasks, hasLength(1));
    expect(batch.warnings, hasLength(1));
  });
  test('Canvas只有401带认证挑战时要求重新连接', () async {
    for (final (status, challenge, expected) in [
      (401, false, false),
      (401, true, true),
      (403, false, false),
    ]) {
      final client = PlatformTaskClient(
        httpClient: FakeHttpClient(
          (_) => Reply({}, status: status, challenge: challenge),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.collectCanvas('fixture-token'),
        throwsA(
          isA<PlatformRequestException>().having(
            (error) => error.requiresReauth,
            'requiresReauth',
            expected,
          ),
        ),
      );
    }
  });
  test('Canvas 恶意跨域分页在发出请求前停止', () async {
    final http = canvasClient(
      next: '<https://evil.example/api/v1/steal>; rel="next"',
    );
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    await expectLater(
      client.collectCanvas('fixture-token'),
      throwsA(isA<PlatformRequestException>()),
    );
    expect(
      http.requests.every((r) => r.uri.host == 'canvas.tongji.edu.cn'),
      isTrue,
    );
  });
  test('Canvas 重复分页不会无限读取', () async {
    final http = canvasClient(
      next:
          '<https://canvas.tongji.edu.cn/api/v1/courses/1/assignments?include[]=submission&override_assignment_dates=true&per_page=100>; rel="next"',
    );
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    await expectLater(
      client.collectCanvas('fixture-token'),
      throwsA(isA<PlatformRequestException>()),
    );
    expect(http.requests, hasLength(3));
  });
  test('401 与登录跳转不会重试或跟随到其他站点', () async {
    for (final status in [401, 302]) {
      final http = FakeHttpClient((_) => Reply({}, status: status));
      final client = PlatformTaskClient(httpClient: http);
      await expectLater(
        client.collectCanvas('fixture-token'),
        throwsA(
          isA<PlatformRequestException>().having(
            (e) => e.statusCode,
            'HTTP status',
            status,
          ),
        ),
      );
      expect(http.requests, hasLength(1));
      expect(http.requests.single.followRedirects, isFalse);
      client.close();
    }
  });
  Map envelope(Object data) => {'code': 200, 'data': data};
  Reply haokeReply(FakeRequest request, {bool repeated = false}) {
    switch (request.uri.path) {
      case '/api/auth/queryCurrentUserInfo':
        return Reply(
          envelope({
            'userInfo': {'userId': 23},
          }),
        );
      case '/api/teach/instance/listMyClass':
        return Reply(
          envelope({
            'teachClassResponseList': [
              {'classId': 42, 'instanceId': 73, 'instanceName': '数学'},
            ],
          }),
        );
      case '/api/learn/task/queryClassInfo':
        return Reply(
          envelope({
            'columnList': [
              {
                'columnName': '课程',
                'subList': [
                  {
                    'columnId': 9,
                    'columnName': '课后作业',
                    'columnType': 30,
                    'iconPath': 'icon-1.svg',
                  },
                ],
              },
            ],
          }),
        );
      case '/api/learn/examine/examineList':
        return Reply(envelope({'rowList': [], 'totalRowCount': 0}));
      case '/api/learn/task/listTaskType':
        return Reply(
          envelope({
            'columnList': [
              {
                'learnShowType': 10,
                'typeList': [1, 2],
              },
            ],
          }),
        );
      case '/api/learn/task/listTask':
        return Reply(
          envelope({
            'totalRowCount': repeated ? 100 : 1,
            'rowList': [
              {
                'taskId': 1,
                'taskName': '习题',
                'myStatus': 30,
                'continueType': 20,
                'endTime': '2026-10-08 00:00:00',
              },
            ],
          }),
        );
      default:
        return Reply({}, status: 404);
    }
  }

  test('好课使用真实账号 ID，已退回优先于完成', () async {
    final http = FakeHttpClient((r) => haokeReply(r));
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    final batch = await client.collectHaoke('fixture-token');
    expect(batch.accountId, '23');
    expect(batch.tasks.single.id, 'haoke:23:42:1');
    expect(batch.tasks.single.completed, isFalse);
    expect(batch.tasks.single.submissionState, 'returned');
    final body = jsonDecode(
      http.requests
          .firstWhere((r) => r.uri.path.endsWith('/listTask'))
          .body
          .toString(),
    );
    expect(body['taskTypes'], isEmpty);
    expect(body.containsKey('columnId'), isFalse);
    expect(body['page'], {'pageNo': 1, 'pageSize': 50});
    expect(
      RegExp(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      ).hasMatch(body['requestId']),
      isTrue,
    );
  });
  test('好课读取全部学习清单，不按栏目名称或任务类型过滤', () async {
    final titles = [
      '1.8 基础测验1',
      '1.7 基础测验1',
      '课程视频',
      '阅读材料',
      '课堂讨论',
      '代码任务',
      '实验任务',
      '章节学习',
      '自适应学习',
    ];
    final http = FakeHttpClient((request) {
      if (!request.uri.path.endsWith('/listTask')) {
        if (request.uri.path.endsWith('/queryClassInfo')) {
          return Reply(envelope({'columnList': []}));
        }
        expect(request.uri.path.endsWith('/listTaskType'), isFalse);
        return haokeReply(request);
      }
      final body = jsonDecode(request.body.toString());
      expect(body['classId'], 42);
      expect(body.containsKey('columnId'), isFalse);
      expect(body['taskTypes'], isEmpty);
      expect(body['status'], 0);
      final start = body['page']['pageNo'] == 1 ? 0 : 5;
      final end = start == 0 ? 5 : 9;
      return Reply(
        envelope({
          'totalRowCount': 9,
          'rowList': [
            for (var i = start; i < end; i++)
              {
                'taskId': i + 1,
                'taskName': titles[i],
                'taskType': [50, 50, 10, 20, 30, 90, 70, 130, 120][i],
                'myStatus': i == 2 ? 30 : 10,
                'endTime': i == 0
                    ? '2026-10-11 00:00:00'
                    : i == 1
                    ? '9999-12-31 00:00:00'
                    : null,
              },
          ],
        }),
      );
    });
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    final batch = await client.collectHaoke('fixture-token');
    expect(batch.tasks, hasLength(9));
    expect(batch.tasks.first.dueAt, DateTime.utc(2026, 10, 10, 16));
    expect(batch.tasks[1].dueAt, isNull);
    expect(batch.tasks[2].completed, isTrue);
    expect(
      batch.tasks.every((task) => !task.url.contains('columnId=null')),
      isTrue,
    );
    expect(
      http.requests.where((request) => request.uri.path.endsWith('/listTask')),
      hasLength(2),
    );
  });
  test('好课重复分页停止，不保存不完整课程', () async {
    final http = FakeHttpClient((r) => haokeReply(r, repeated: true));
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    await expectLater(
      client.collectHaoke('fixture-token'),
      throwsA(isA<PlatformRequestException>()),
    );
    expect(
      http.requests.where((r) => r.uri.path.endsWith('/listTask')),
      hasLength(2),
    );
  });
  test('好课 503 只重试一次，401 和 403 不重试', () async {
    for (final status in [503, 401, 403]) {
      final http = FakeHttpClient((_) => Reply({}, status: status));
      final client = PlatformTaskClient(httpClient: http);
      await expectLater(
        client.collectHaoke('fixture-token'),
        throwsA(
          isA<PlatformRequestException>().having(
            (e) => e.statusCode,
            'HTTP status',
            status,
          ),
        ),
      );
      expect(http.requests, hasLength(status == 503 ? 2 : 1));
      client.close();
    }
  });
  test('免密码登录后独立验证账号，只读身份接口且不携带ticket', () async {
    final http = FakeHttpClient(
      (_) => Reply(
        envelope({
          'userInfo': {'userId': 42},
        }),
      ),
    );
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    expect(await client.verifyHaokeAccount('new-fixture'), '42');
    expect(
      http.requests.single.uri.toString(),
      'https://tongji.aihaoke.net/api/auth/queryCurrentUserInfo',
    );
    expect(
      http.requests.single.headers.value('Authorization'),
      'Bearer new-fixture',
    );
    expect(
      jsonDecode(http.requests.single.body.toString()).containsKey('ticket'),
      isFalse,
    );
    expect(http.requests.single.followRedirects, false);
  });
  test('账号验证拒绝业务401和缺失或非标量身份字段', () async {
    for (final value in [
      {'code': 401, 'data': {}},
      envelope({'userInfo': {}}),
      envelope({
        'userInfo': {'userId': {}},
      }),
      envelope({
        'userInfo': {'userId': ' '},
      }),
    ]) {
      final http = FakeHttpClient((_) => Reply(value));
      final client = PlatformTaskClient(httpClient: http);
      await expectLater(
        client.verifyHaokeAccount('fixture'),
        throwsA(isA<PlatformRequestException>()),
      );
      client.close();
    }
  });
  test('续期返回配对票据，并携带当前 token、ticket 和 requestId', () async {
    final http = FakeHttpClient(
      (_) =>
          Reply(envelope({'token': 'next-fixture', 'ticket': 'next-ticket'})),
    );
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    final next = await client.renewHaoke(
      const HaokeCredentials(token: 'fixture', ticket: 'fixture-ticket'),
    );
    expect(next.token, 'next-fixture');
    expect(next.ticket, 'next-ticket');
    final body = jsonDecode(http.requests.single.body.toString());
    expect(body['token'], 'fixture');
    expect(body['ticket'], 'fixture-ticket');
    expect(body['requestId'], isNotEmpty);
  });
  test('续期不会接受不完整票据或超大响应', () async {
    for (final value in [
      envelope({'token': 'fixture'}),
      envelope({'token': 'x' * 65536, 'ticket': 'fixture'}),
    ]) {
      final http = FakeHttpClient((_) => Reply(value));
      final client = PlatformTaskClient(httpClient: http);
      await expectLater(
        client.renewHaoke(
          const HaokeCredentials(token: 'fixture', ticket: 'fixture-ticket'),
        ),
        throwsA(isA<PlatformRequestException>()),
      );
      client.close();
    }
  });
  test('释放客户端后不能继续请求', () async {
    final http = canvasClient();
    final client = PlatformTaskClient(httpClient: http)..close();
    await expectLater(
      client.collectCanvas('fixture-token'),
      throwsA(isA<PlatformRequestException>()),
    );
    expect(http.requests, isEmpty);
  });
  test('网络异常分类不含原始凭证，程序错误不误判为可重试断网', () async {
    for (final (failure, kind) in [
      (TimeoutException('secret-token'), 'timeout'),
      (const SocketException('secret-token'), 'connection'),
      (const HandshakeException('secret-token'), 'tls'),
      (const HttpException('secret-token'), 'http_connection'),
    ]) {
      final client = PlatformTaskClient(
        httpClient: FakeHttpClient((_) => throw failure),
      );
      try {
        await expectLater(
          client.verifyHaokeAccount('fixture'),
          throwsA(
            isA<PlatformNetworkException>()
                .having((error) => error.kind, '分类', kind)
                .having((error) => error.retryable, '可以补试', true)
                .having(
                  (error) => error.toString().contains('secret-token'),
                  '没有敏感内容',
                  false,
                ),
          ),
        );
      } finally {
        client.close();
      }
    }
    final client = PlatformTaskClient(
      httpClient: FakeHttpClient((_) => throw StateError('bug')),
    );
    addTearDown(client.close);
    await expectLater(
      client.verifyHaokeAccount('fixture'),
      throwsA(
        isA<PlatformRequestException>().having(
          (error) => error.retryable,
          '程序错误不反复补试',
          false,
        ),
      ),
    );
  });
}

class Reply {
  Reply(this.data, {this.status = 200, this.link, this.challenge = false});
  final Object data;
  final int status;
  final String? link;
  final bool challenge;
}

class FakeHttpClient implements HttpClient {
  FakeHttpClient(this.handler);
  final Reply Function(FakeRequest) handler;
  final requests = <FakeRequest>[];
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = FakeRequest(method, url, handler);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRequest implements HttpClientRequest {
  FakeRequest(this.method, this.uri, this.handler);
  @override
  final String method;
  @override
  final Uri uri;
  final Reply Function(FakeRequest) handler;
  final body = StringBuffer();
  @override
  final headers = FakeHeaders();
  @override
  bool followRedirects = true;
  @override
  void write(Object? value) {
    body.write(value);
  }

  @override
  Future<HttpClientResponse> close() async => FakeResponse(handler(this));
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHeaders implements HttpHeaders {
  final values = <String, String>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = '$value';
  }

  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  FakeResponse(this.reply) {
    if (reply.link != null) headers.set('link', reply.link!);
    if (reply.challenge) headers.set('www-authenticate', 'Bearer');
  }
  final Reply reply;
  @override
  final headers = FakeHeaders();
  @override
  int get statusCode => reply.status;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(reply.data))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
