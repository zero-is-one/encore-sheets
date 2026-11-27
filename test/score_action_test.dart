import 'package:encoresheets/rehearsal_wave.dart';
import 'package:encoresheets/score_action.dart';
import 'package:encoresheets/score_action_destination.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ScoreAction action(ScoreActionKind kind, String parameter) => ScoreAction(
  title: 'Reference',
  page: 1,
  x: .2,
  y: .3,
  color: 0xff254a73,
  kind: kind,
  parameter: parameter,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new score actions preserve existing tempo and pitch defaults', () {
    final tempo = action(ScoreActionKind.tempo, '96').toJson();
    expect(ScoreAction.fromJson(tempo)?.kind, ScoreActionKind.tempo);
    final pitch = action(ScoreActionKind.pitch, '69').toJson();
    expect(ScoreAction.fromJson(pitch)?.timbre, ReferenceTimbre.pure);
    final reed = ScoreAction.fromJson({...pitch, 'timbre': 'reed'})!;
    expect(reed.reposition(2, .3, .5).toJson()['timbre'], 'reed');
    for (final kind in [
      ScoreActionKind.toggleMetronome,
      ScoreActionKind.nextSetlist,
      ScoreActionKind.previousSetlist,
    ]) {
      final data = action(kind, kind.usesTempo ? '120' : '').toJson();
      expect(ScoreAction.fromJson(data)?.kind, kind);
    }
    expect(
      ScoreAction.validParameter(ScoreActionKind.toggleMetronome, '0'),
      isFalse,
    );
  });

  test('optional page action labels survive persistence and editing', () {
    final original = action(ScoreActionKind.website, 'https://example.com');
    expect(ScoreAction.fromJson(original.toJson())?.showLabel, isFalse);
    final labeled = ScoreAction.fromJson({
      ...original.toJson(),
      'showLabel': true,
    })!;
    expect(labeled.reposition(2, .4, .5).showLabel, isTrue);
    expect(labeled.retarget('updated').showLabel, isTrue);
    expect(
      labeled.withParameter('https://example.org').toJson()['showLabel'],
      isTrue,
    );
  });

  test(
    'website and app destinations round-trip and enforce supported schemes',
    () {
      for (final (kind, value) in [
        (ScoreActionKind.website, 'https://example.com/rehearsal?q=part%201'),
        (ScoreActionKind.externalApp, 'https://example.com/app/track'),
        (ScoreActionKind.externalApp, 'spotify:track:example'),
      ]) {
        final restored = ScoreAction.fromJson(action(kind, value).toJson());
        expect(restored?.kind, kind);
        expect(restored?.parameter, value);
      }
      for (final value in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://track',
        'https://user@example.com/track',
        'https:///missing-host',
      ]) {
        expect(
          ScoreAction.fromJson(action(ScoreActionKind.website, value).toJson()),
          isNull,
        );
        expect(
          ScoreAction.fromJson(
            action(ScoreActionKind.externalApp, value).toJson(),
          ),
          isNull,
        );
      }
    },
  );

  testWidgets(
    'file destinations pass only the managed file reference to the platform',
    (tester) async {
      const channel = MethodChannel('encoresheets/score-action-file');
      const id = '0123456789abcdef0123456789abcdef';
      final messages = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        messages.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final file = action(ScoreActionKind.externalFile, '$id/Étude.pdf');
      expect(ScoreAction.fromJson(file.toJson())?.parameter, file.parameter);
      expect(await openScoreActionDestination(file), isTrue);
      expect(messages.single.method, 'open');
      expect(messages.single.arguments, {'id': id, 'name': 'Étude.pdf'});

      for (final value in [
        '/private/score.pdf',
        '$id/../score.pdf',
        '$id/bad\\name.pdf',
        '$id/script.html',
      ]) {
        final invalid = action(ScoreActionKind.externalFile, value);
        expect(ScoreAction.fromJson(invalid.toJson()), isNull);
        expect(await openScoreActionDestination(invalid), isFalse);
      }
      expect(messages, hasLength(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
