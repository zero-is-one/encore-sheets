import 'dart:convert';

import 'package:encoresheets/cloud_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
