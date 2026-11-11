import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/article_jobs.dart';

void main() {
  test('vanished paths exclude jobs still present', () {
    const a = ArticleJob(path: 'a', url: 'https://a.test', status: 'queued');
    const b = ArticleJob(
      path: 'b',
      url: 'https://b.test',
      status: 'processing',
    );
    const c = ArticleJob(path: 'c', url: 'https://c.test', status: 'queued');
    expect(vanishedJobPaths([a, b, a], [b, c]), {'a'});
    expect(vanishedJobPaths([], [a]), isEmpty);
  });

  test('only done jobs with a non-empty string origin return it', () {
    expect(
      doneJobOrigin('{"status":"done","origin":"today.typ"}'),
      'today.typ',
    );
    expect(doneJobOrigin('{"status":"queued","origin":"today.typ"}'), isNull);
    expect(doneJobOrigin('bad json'), isNull);
    expect(doneJobOrigin('{"status":"done"}'), isNull);
    expect(doneJobOrigin('{"status":"done","origin":""}'), isNull);
    expect(doneJobOrigin('{"status":"done","origin":42}'), isNull);
    expect(doneJobOrigin('[]'), isNull);
  });
}
