# Flutter client

Рабочий клиент alpha 0.1.0. Начните с `../../README.md` и
`../../docs/IMPLEMENTATION_STATUS_RU.md`.

`lib/main.dart` создаёт настоящий `TransferAppController` с `AppRuntime.native()`.
`lib/ui/` не генерирует устройства, файлы или прогресс; состояние поступает из
сетевых и файловых сервисов. Тестовые runtime и capture fixtures находятся только
в `test/`.

```bash
flutter pub get
flutter run
flutter test
```

На телефонах держите приложение открытым. Подробности API и хранилища:
`../../packages/transfer_core/lib/src/network/README.md` и
`../../packages/transfer_core/lib/src/storage/README.md`.
