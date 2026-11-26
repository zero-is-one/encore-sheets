import 'dart:convert';

import 'package:encoresheets/cloud_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Google Drive browses all folder pages and downloads PDFs', () async {
    final session = CloudProviderSession(
      DirectCloudProvider.googleDrive,
      'test-token',
      client: MockClient((request) async {
        expect(request.url.host, 'www.googleapis.com');
        expect(request.headers['authorization'], 'Bearer test-token');
        final query = request.url.queryParameters;
        if (query['alt'] == 'media') {
          expect(request.url.path, '/drive/v3/files/score-id');
          return http.Response('%PDF-1.7', 200);
        }
        expect(query['q'], "'folder-id' in parents and trashed = false");
        if (query['pageToken'] == 'next') {
          return http.Response(
            '{"files":[{"id":"score-id","name":"Score.pdf","mimeType":"application/pdf"}]}',
            200,
          );
        }
        return http.Response(
          '{"nextPageToken":"next","files":['
          '{"id":"folder-2","name":"Folder","mimeType":"application/vnd.google-apps.folder"},'
          '{"id":"text","name":"Other","mimeType":"text/plain"}]}',
          200,
        );
      }),
    );
    addTearDown(session.close);
    final items = await session.folder('folder-id');
    expect(items.map((item) => item.name), ['Folder', 'Score.pdf']);
    final pdf = await session.download(items.last);
    expect(pdf.name, 'Score.pdf');
    expect(await pdf.length(), 8);
  });

  test('Google Drive uploads a new PDF via multipart create', () async {
    final session = CloudProviderSession(
      DirectCloudProvider.googleDrive,
      'test-token',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/upload/drive/v3/files');
        expect(request.url.queryParameters['uploadType'], 'multipart');
        final contentType = request.headers['content-type']!;
        expect(contentType, startsWith('multipart/related; boundary='));
        final boundary = contentType.split('boundary=').last;
        final parts = utf8.decode(request.bodyBytes).split('--$boundary');
        expect(jsonDecode(parts[1].split('\r\n\r\n').last), {
          'name': 'Étude.pdf',
          'parents': ['root'],
        });
        expect(
          parts[2],
          contains('Content-Type: application/pdf\r\n\r\n%PDF-1.7'),
        );
        expect(parts.last, '--\r\n');
        return http.Response('{}', 201);
      }),
    );
    addTearDown(session.close);
    await session.upload(
      'root',
      'Étude.pdf',
      XFile.fromData(utf8.encode('%PDF-1.7')),
    );
  });

  test('OneDrive follows Graph pages and downloads without sending the token to storage', () async {
    final session = CloudProviderSession(
      DirectCloudProvider.oneDrive,
      'test-token',
      client: MockClient((request) async {
        if (request.url.host == 'storage.1drv.com') {
          expect(request.headers['authorization'], isNull);
          return http.Response('%PDF-1.7', 200);
        }
        expect(request.url.host, 'graph.microsoft.com');
        expect(request.headers['authorization'], 'Bearer test-token');
        expect(request.followRedirects, isFalse);
        if (request.url.path == '/v1.0/me/drive/items/abc!123') {
          expect(
            request.url.queryParameters[r'$select'],
            'id,@microsoft.graph.downloadUrl',
          );
          return http.Response(
            '{"@microsoft.graph.downloadUrl":"https://storage.1drv.com/signed"}',
            200,
          );
        }
        expect(request.url.path, '/v1.0/me/drive/root/children');
        if (request.url.queryParameters[r'$skiptoken'] == 'next') {
          return http.Response(
            '{"value":[{"id":"abc!123","name":"Score.PDF","file":{}}]}',
            200,
          );
        }
        return http.Response(
          '{"value":[],"@odata.nextLink":'
          '"https://graph.microsoft.com/v1.0/me/drive/root/children?\$skiptoken=next"}',
          200,
        );
      }),
    );
    addTearDown(session.close);
    final result = await session.download(
      (await session.folder('root')).single,
    );
    expect(result.name, 'Score.PDF');
  });

  test(
    'OneDrive refuses an external continuation or signed download URL',
    () async {
      final session = CloudProviderSession(
        DirectCloudProvider.oneDrive,
        'test-token',
        client: MockClient((request) async {
          expect(request.url.host, 'graph.microsoft.com');
          return request.url.path.endsWith('/children')
              ? http.Response(
                  '{"@odata.nextLink":"https://example.org/v1.0/next"}',
                  200,
                )
              : http.Response(
                  '{"@microsoft.graph.downloadUrl":"https://example.org/file"}',
                  200,
                );
        }),
      );
      addTearDown(session.close);
      await expectLater(
        session.folder('root'),
        throwsA(isA<CloudTransferError>()),
      );
      await expectLater(
        session.download((id: 'file-id', name: 'Score.pdf', folder: false)),
        throwsA(isA<CloudTransferError>()),
      );
    },
  );

  test(
    'OneDrive requests create-only upload and surfaces a name conflict',
    () async {
      final session = CloudProviderSession(
        DirectCloudProvider.oneDrive,
        'test-token',
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.pathSegments, [
            'v1.0',
            'me',
            'drive',
            'items',
            'folder-id:',
            'Étude #4.pdf:',
            'content',
          ]);
          expect(
            request.url.queryParameters['@microsoft.graph.conflictBehavior'],
            'fail',
          );
          expect(request.headers['if-none-match'], '*');
          expect(request.body, '%PDF-1.7');
          return http.Response('{}', 409);
        }),
      );
      addTearDown(session.close);
      await expectLater(
        session.upload(
          'folder-id',
          'Étude #4.pdf',
          XFile.fromData(utf8.encode('%PDF-1.7')),
        ),
        throwsA(
          isA<CloudTransferError>().having(
            (error) => error.message,
            'message',
            contains('Choose another name'),
          ),
        ),
      );
    },
  );

  test(
    'pasting a cut Dropbox PDF uses a remote move without overwriting',
    () async {
      final session = CloudProviderSession(
        DirectCloudProvider.dropbox,
        'test-token',
        client: MockClient((request) async {
          expect(request.url.path, '/2/files/move_v2');
          expect(jsonDecode(request.body), {
            'from_path': '/old/sonata.pdf',
            'to_path': '/new/Sonata.pdf',
            'autorename': true,
          });
          return http.Response('{}', 200);
        }),
      );
      addTearDown(session.close);
      await session.transfer(
        sourceId: '/old/sonata.pdf',
        filename: 'Sonata.pdf',
        folderId: '/new',
        move: true,
      );
    },
  );

  test(
    'Dropbox follows folder cursors and escapes PDF download paths',
    () async {
      final session = CloudProviderSession(
        DirectCloudProvider.dropbox,
        'test-token',
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer test-token');
          if (request.url.path.endsWith('/download')) {
            final argument = request.headers['dropbox-api-arg']!;
            expect(argument.codeUnits.every((unit) => unit < 128), isTrue);
            expect(jsonDecode(argument)['path'], '/étude.pdf');
            return http.Response('%PDF-1.7', 200);
          }
          if (request.url.path.endsWith('/continue')) {
            expect(jsonDecode(request.body)['cursor'], 'next');
            return http.Response(
              '{"has_more":false,"entries":[{".tag":"file","name":"Étude.pdf","path_lower":"/étude.pdf"}]}',
              200,
            );
          }
          expect(request.url.path, '/2/files/list_folder');
          return http.Response(
            '{"has_more":true,"cursor":"next","entries":[{".tag":"file","name":"skip.txt","path_lower":"/skip.txt"}]}',
            200,
          );
        }),
      );
      addTearDown(session.close);
      final items = await session.folder('');
      final pdf = await session.download(items.single);
      expect(pdf.name, 'Étude.pdf');
    },
  );

  test('Box signed download does not forward the access token', () async {
    final session = CloudProviderSession(
      DirectCloudProvider.box,
      'test-token',
      client: MockClient((request) async {
        if (request.url.host == 'api.box.com') {
          expect(request.headers['authorization'], 'Bearer test-token');
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://dl.boxcloud.com/signed'},
          );
        }
        expect(request.url.host, 'dl.boxcloud.com');
        expect(request.headers['authorization'], isNull);
        return http.Response('%PDF-1.7', 200);
      }),
    );
    addTearDown(session.close);
    final pdf = await session.download((
      id: '42',
      name: 'score.pdf',
      folder: false,
    ));
    expect(await pdf.length(), 8);
  });
}
