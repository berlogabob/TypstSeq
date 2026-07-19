import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/editor_autocomplete.dart';

void main() {
  group('detectTrigger', () {
    test('@ alone at start of text triggers a mention with an empty query', () {
      final trigger = detectTrigger('@', 1);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.mention);
      expect(trigger.query, '');
      expect(trigger.start, 0);
    });

    test('@Fer triggers a mention with query "Fer"', () {
      final trigger = detectTrigger('@Fer', 4);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.mention);
      expect(trigger.query, 'Fer');
      expect(trigger.start, 0);
    });

    test('a space after the query cancels the trigger', () {
      expect(detectTrigger('@Fer ', 5), isNull);
    });

    test('/ triggers a command palette', () {
      final trigger = detectTrigger('/table', 6);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.command);
      expect(trigger.query, 'table');
      expect(trigger.start, 0);
    });

    test('foo@bar does not trigger (no preceding whitespace)', () {
      expect(detectTrigger('foo@bar', 7), isNull);
    });

    test('a path like x/y does not trigger (no preceding whitespace)', () {
      expect(detectTrigger('x/y', 3), isNull);
    });

    test('@ preceded by whitespace triggers mid-sentence', () {
      final trigger = detectTrigger('Hello @Fer', 10);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.mention);
      expect(trigger.query, 'Fer');
      expect(trigger.start, 6);
    });

    test('@ preceded by a newline triggers', () {
      final trigger = detectTrigger('line one\n@Fer', 13);
      expect(trigger, isNotNull);
      expect(trigger!.query, 'Fer');
      expect(trigger.start, 9);
    });

    test('deleting back past @ cancels the trigger', () {
      // Simulates backspacing "@Fer" down to "" — nothing left to trigger on.
      expect(detectTrigger('', 0), isNull);
    });

    test('deleting the @ itself while query text remains cancels', () {
      // "Fer" with no leading "@" — no trigger character at all.
      expect(detectTrigger('Fer', 3), isNull);
    });

    test('caret not at the end of the word cancels the trigger', () {
      // Caret sits between "Fer" and "nando" in "@Fernando".
      expect(detectTrigger('@Fernando', 4), isNull);
    });

    test('whitespace inside the query cancels the trigger', () {
      expect(detectTrigger('@Fer Nando', 10), isNull);
    });

    test('no trigger character present at all returns null', () {
      expect(detectTrigger('just plain text', 16), isNull);
    });

    test('caret at position 0 with preceding text returns null', () {
      expect(detectTrigger('@Fer', 0), isNull);
    });

    test('command trigger cancels the same way a mention trigger does', () {
      expect(detectTrigger('/foo bar', 8), isNull);
    });
  });

  group('detectTrigger wiki-links', () {
    test('[[ alone triggers a wiki-link with an empty query', () {
      final trigger = detectTrigger('[[', 2);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.wikiLink);
      expect(trigger.query, '');
      expect(trigger.start, 0);
    });

    test('[[ESP32 triggers with query "ESP32"', () {
      final trigger = detectTrigger('[[ESP32', 7);
      expect(trigger!.kind, AutocompleteTriggerKind.wikiLink);
      expect(trigger.query, 'ESP32');
      expect(trigger.start, 0);
    });

    test('the query may contain spaces (Home Assistant)', () {
      final trigger = detectTrigger('see [[Home Assist', 17);
      expect(trigger!.kind, AutocompleteTriggerKind.wikiLink);
      expect(trigger.query, 'Home Assist');
      expect(trigger.start, 4);
    });

    test('the query may contain Unicode (Cyrillic)', () {
      const text = '[[игровые движ';
      final trigger = detectTrigger(text, text.length);
      expect(trigger!.query, 'игровые движ');
    });

    test('a completed [[link]] does not re-trigger from after it', () {
      expect(detectTrigger('[[ESP32]]', 9), isNull);
    });

    test('a newline between [[ and the caret cancels', () {
      expect(detectTrigger('[[ESP32\nmore', 12), isNull);
    });

    test('a ] before the caret cancels', () {
      expect(detectTrigger('[[ESP32] ', 9), isNull);
    });

    test('wiki-link takes precedence over @ inside the brackets', () {
      final trigger = detectTrigger('[[@Fer', 6);
      expect(trigger!.kind, AutocompleteTriggerKind.wikiLink);
      expect(trigger.query, '@Fer');
    });
  });
}
