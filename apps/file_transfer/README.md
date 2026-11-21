# Ulash — Flutter-приложение

Начните с `../../README.md`. `lib/main.dart` создаёт `TransferAppController` с `AppRuntime.native()`; `lib/ui/` не генерирует устройства, файлы или прогресс — состояние приходит из сетевых и файловых сервисов. Тестовые runtime находятся только в `test/`.

```bash
flutter pub get
flutter run
flutter test
```

Строки интерфейса — в `lib/l10n/*.arb` (ru — шаблон). Иконки — `../../scripts/generate_icons.py`.
