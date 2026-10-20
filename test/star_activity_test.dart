import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/star_activity_client.dart';
import 'package:offline_course_schedule/domain/star_activity.dart';

import 'platform_task_client_test.dart' show FakeHttpClient, Reply;

Map<String, dynamic> ticket({int id = 7, int hour = 18}) => {
  'id': id,
  'activityId': 12,
  'status': 0,
  'activity': {'id': 12, 'title': '校园讲座', 'addr': '同济楼 301'},
  'schedule': {
    'id': 31,
    'activityStartTime': DateTime.utc(
      2026,
      10,
      21,
      hour - 8,
    ).millisecondsSinceEpoch,
    'activityEndTime': DateTime.utc(
      2026,
      10,
      21,
      hour - 7,
    ).millisecondsSinceEpoch,
  },
};

void main() {
  test('入场券按北京时间转换为有来源和稳定编号的一次性备忘录', () {
    final activity = StarActivity.fromTicket(ticket());
    final memo = activity.toMemos('account').single;
    expect(memo.title, '校园讲座');
    expect(memo.location, '同济楼 301');
    expect(memo.source, 'star');
    expect(memo.date, DateTime(2026, 10, 21));
    expect(memo.startMinutes, 18 * 60);
    expect(memo.endMinutes, 19 * 60);
    expect(memo.isRecurring, isFalse);
    expect(activity.toMemos('account').single.id, memo.id);
    expect(activity.toMemos('other').single.id, isNot(memo.id));
  });

  test('跨午夜活动分到实际日期，改期不依赖标题去重', () {
    final row = ticket(hour: 23);
    row['schedule']['activityEndTime'] = DateTime.utc(
      2026,
      10,
      21,
      17,
    ).millisecondsSinceEpoch;
    final memos = StarActivity.fromTicket(row).toMemos('a');
    expect(memos, hasLength(2));
    expect(memos.first.endMinutes, 1440);
    expect(memos.last.date, DateTime(2026, 10, 22));
    expect(memos.last.startMinutes, 0);
    expect(memos.last.endMinutes, 60);
  });

  test('缺少活动时间不能猜测，完整快照必须失败', () {
    final row = ticket();
    row['schedule'] = {'id': 31};
    expect(() => StarActivity.fromTicket(row), throwsFormatException);
  });

  test('系列活动只取已报名场次的签到时间，并标注时间来源', () {
    final row = ticket();
    row['activity']['activityStartTime'] = DateTime.utc(
      2026,
      10,
      1,
    ).millisecondsSinceEpoch;
    row['activity']['activityEndTime'] = DateTime.utc(
      2026,
      12,
      31,
    ).millisecondsSinceEpoch;
    row['schedule'] = {
      'id': 31,
      'title': '第二场 AI 提示词',
      'signInStartTime': DateTime.utc(2026, 10, 21, 5).millisecondsSinceEpoch,
      'signInEndTime': DateTime.utc(2026, 10, 21, 7).millisecondsSinceEpoch,
    };
    final memo = StarActivity.fromTicket(row).toMemos('a').single;
    expect(memo.title, '校园讲座 · 第二场 AI 提示词（签到时段）');
    expect(memo.startMinutes, 13 * 60);
    expect(memo.endMinutes, 15 * 60);
  });

  test('审核中与审核退回的入场券不作为报名成功安排', () async {
    final client = StarActivityClient(
      httpClient: FakeHttpClient(
        (_) => Reply({
          'code': 0,
          'data': {
            'total': 4,
            'list': [
              for (var i = 0; i < 4; i++) {...ticket(id: i), 'status': i},
            ],
          },
        }),
      ),
    );
    addTearDown(client.close);
    expect((await client.activities('access')).map((a) => a.ticketId), [
      '0',
      '2',
    ]);
  });

  test('刷新令牌只发送给卓越星，关闭重定向并接收轮换令牌', () async {
    final http = FakeHttpClient(
      (request) => Reply({
        'code': 0,
        'data': {
          'accessToken': 'new-access',
          'refreshToken': 'new-refresh',
          'expiresTime': 1800000000000,
        },
      }),
    );
    final client = StarActivityClient(httpClient: http);
    addTearDown(client.close);
    final session = await client.renew('refresh +/?');
    expect(session.refreshToken, 'new-refresh');
    expect(session.accessToken, 'new-access');
    expect(http.requests.single.method, 'POST');
    expect(http.requests.single.uri.host, 'star.tongji.edu.cn');
    expect(
      http.requests.single.uri.queryParameters['refreshToken'],
      'refresh +/?',
    );
    expect(http.requests.single.followRedirects, isFalse);
  });

  test('分页读取全部入场券，失败不返回部分报名快照', () async {
    final http = FakeHttpClient((request) {
      final page = int.parse(request.uri.queryParameters['pageNo']!);
      return Reply({
        'code': 0,
        'data': {
          'total': 51,
          'list': page == 1
              ? [for (var id = 1; id <= 50; id++) ticket(id: id)]
              : [ticket(id: 51)],
        },
      });
    });
    final client = StarActivityClient(httpClient: http);
    addTearDown(client.close);
    expect(await client.activities('access'), hasLength(51));
    expect(http.requests, hasLength(2));
    expect(http.requests.first.headers.value('authorization'), 'Bearer access');

    final bad = StarActivityClient(
      httpClient: FakeHttpClient(
        (_) => Reply({
          'code': 0,
          'data': {
            'total': 2,
            'list': [ticket()],
          },
        }),
      ),
    );
    addTearDown(bad.close);
    await expectLater(
      bad.activities('access'),
      throwsA(isA<StarRequestException>()),
    );
  });

  test('失效和网络错误不包含请求中的凭据', () async {
    for (final code in [401, 500]) {
      final client = StarActivityClient(
        httpClient: FakeHttpClient(
          (_) => Reply({'code': code, 'msg': 'secret-refresh'}),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.renew('secret-refresh'),
        throwsA(
          isA<StarRequestException>()
              .having(
                (e) => e.toString(),
                'message',
                isNot(contains('secret-refresh')),
              )
              .having((e) => e.needsAuth, 'needsAuth', code == 401),
        ),
      );
    }
  });
}
