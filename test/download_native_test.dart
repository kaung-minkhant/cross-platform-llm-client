import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privatelm/services/download_native.dart';

/// Serves [body] slowly in small chunks, optionally honouring Range requests,
/// and records the Range header of every request.
class _FileServer {
  _FileServer(this.body, {this.supportsRange = true});

  final Uint8List body;
  final bool supportsRange;
  final ranges = <String?>[];
  late HttpServer _server;

  String get url => 'http://127.0.0.1:${_server.port}/model.gguf';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> _handle(HttpRequest req) async {
    final range = req.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range);
    var start = 0;
    final res = req.response;
    if (supportsRange && range != null) {
      start = int.parse(range.split('=')[1].split('-')[0]);
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(HttpHeaders.contentRangeHeader,
          'bytes $start-${body.length - 1}/${body.length}');
    }
    res.contentLength = body.length - start;
    const chunk = 1024;
    for (var i = start; i < body.length; i += chunk) {
      final end = i + chunk > body.length ? body.length : i + chunk;
      res.add(body.sublist(i, end));
      try {
        await res.flush();
      } catch (_) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 2));
    }
    await res.close();
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late Directory dir;
  late String savePath;
  final body = Uint8List.fromList(List.generate(64 * 1024, (i) => i % 251));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('download_test');
    savePath = '${dir.path}/model.gguf';
  });

  tearDown(() => dir.delete(recursive: true));

  test('downloads a file from scratch', () async {
    final server = _FileServer(body);
    await server.start();
    final result = await downloadModel(url: server.url, savePath: savePath);
    expect(result, savePath);
    expect(await File(savePath).readAsBytes(), body);
    expect(File('$savePath$partialDownloadSuffix').existsSync(), isFalse);
    await server.stop();
  });

  test('pause keeps progress and the next call resumes with Range', () async {
    final server = _FileServer(body);
    await server.start();

    var paused = false;
    final result = await downloadModel(
      url: server.url,
      savePath: savePath,
      onProgress: (received, _) {
        if (!paused && received >= 16 * 1024) {
          paused = true;
          pauseDownload('model.gguf');
        }
      },
    );
    expect(result, 'PAUSED');
    final partial = File('$savePath$partialDownloadSuffix');
    expect(partial.existsSync(), isTrue);
    final kept = partial.lengthSync();
    expect(kept, greaterThan(0));

    final resumed = await downloadModel(url: server.url, savePath: savePath);
    expect(resumed, savePath);
    expect(server.ranges.last, 'bytes=$kept-');
    expect(await File(savePath).readAsBytes(), body);
    await server.stop();
  });

  test('a stalled connection times out and keeps the partial file', () async {
    receiveIdleTimeout = const Duration(milliseconds: 500);
    addTearDown(() => receiveIdleTimeout = const Duration(seconds: 60));
    final stalled = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    stalled.listen((socket) async {
      socket.write('HTTP/1.1 200 OK\r\n'
          'Content-Length: ${body.length}\r\n\r\n');
      socket.add(body.sublist(0, 8 * 1024));
      await socket.flush(); // then send nothing more
    });
    await expectLater(
      downloadModel(
          url: 'http://127.0.0.1:${stalled.port}/model.gguf',
          savePath: savePath),
      throwsA(isA<Exception>()),
    );
    expect(File('$savePath$partialDownloadSuffix').lengthSync(), 8 * 1024);
    await stalled.close();
  });

  test('restarts cleanly when the server ignores Range', () async {
    final server = _FileServer(body, supportsRange: false);
    await server.start();
    // A stale partial from an earlier attempt.
    File('$savePath$partialDownloadSuffix')
        .writeAsBytesSync(List.filled(5000, 7));

    final result = await downloadModel(url: server.url, savePath: savePath);
    expect(result, savePath);
    expect(await File(savePath).readAsBytes(), body,
        reason: 'must not append a full response onto the partial file');
    await server.stop();
  });

  test('sends the token, but not to a different host after a redirect',
      () async {
    final authSeen = <String, String?>{};
    // "CDN": a different origin (port) that the first server redirects to.
    final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    cdn.listen((req) async {
      authSeen['cdn'] = req.headers.value(HttpHeaders.authorizationHeader);
      req.response.contentLength = body.length;
      req.response.add(body);
      await req.response.close();
    });
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((req) async {
      authSeen['origin'] = req.headers.value(HttpHeaders.authorizationHeader);
      req.response.statusCode = HttpStatus.found;
      req.response.headers
          .set(HttpHeaders.locationHeader, 'http://localhost:${cdn.port}/f');
      await req.response.close();
    });

    final result = await downloadModel(
      url: 'http://127.0.0.1:${origin.port}/model.gguf',
      savePath: savePath,
      authToken: 'hf_testtoken',
    );
    expect(result, savePath);
    expect(authSeen['origin'], 'Bearer hf_testtoken');
    expect(authSeen.containsKey('cdn'), isTrue, reason: 'redirect not followed');
    expect(authSeen['cdn'], isNull,
        reason: 'a signed CDN URL must not receive the Hugging Face token');
    await origin.close(force: true);
    await cdn.close(force: true);
  });

  test('a 401 explains the Hugging Face token problem', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.statusCode = HttpStatus.unauthorized;
      await req.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/model.gguf';
    await expectLater(
      downloadModel(url: url, savePath: savePath),
      throwsA(predicate((e) => '$e'.contains('Add an access token'))),
    );
    await expectLater(
      downloadModel(url: url, savePath: savePath, authToken: 'hf_x'),
      throwsA(predicate((e) => '$e'.contains('accepted this model'))),
    );
    await server.close(force: true);
  });

  test('a dropped connection keeps the partial file for resuming', () async {
    // Raw socket server: sends headers and part of the body, then hangs up.
    final dropping = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    dropping.listen((socket) async {
      socket.write('HTTP/1.1 200 OK\r\n'
          'Content-Length: ${body.length}\r\n'
          'Connection: close\r\n\r\n');
      socket.add(body.sublist(0, 20 * 1024));
      await socket.flush();
      socket.destroy();
    });
    await expectLater(
      downloadModel(
          url: 'http://127.0.0.1:${dropping.port}/model.gguf',
          savePath: savePath),
      throwsA(isA<Exception>()),
    );
    final partial = File('$savePath$partialDownloadSuffix');
    expect(partial.existsSync(), isTrue);
    expect(partial.lengthSync(), greaterThan(0));
    await dropping.close();

    final server = _FileServer(body);
    await server.start();
    expect(await downloadModel(url: server.url, savePath: savePath), savePath);
    expect(await File(savePath).readAsBytes(), body);
    await server.stop();
  });
}
