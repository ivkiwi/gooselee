# Localization

- English is the source language: UI strings stay English in code and serve as keys.
- SwiftUI literals (`Text("…")`, `Button("…")`, `Toggle`, `Picker`, `.help`, alert titles) localize automatically. Do not use `Text(verbatim:)` for UI text.
- Everything else the user sees (String variables, enum/model labels, `NSMenuItem`, `NSAlert`, notifications, user-facing errors) goes through `String(localized: "English text")`.
- Interpolation becomes format specifiers in the key: `Int` → `%lld`, `String` → `%@`, `Double` → `%lf`. The translation must keep the same specifiers; use positional `%1$@`, `%2$lld` when the order changes.
- Russian lives in `ru/<Area>.strings`, one fragment per feature or area: `"English key" = "Русский перевод";`, UTF-8, escape `\"` and `\n`. Edit only your own fragment; shared words go to `Common.strings`.
- Keep translations as short as possible and use standard macOS Russian terms («Отменить», «Готово», «Настройки»). LLM prompts are not UI and are not localized.
- `scripts/build_native_app.sh` merges `ru/*.strings` (sorted) into `ru.lproj/Localizable.strings`; `LocalizationStringsTests` checks parsing, duplicate keys, empty values and format specifiers.
