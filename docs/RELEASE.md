# Выпуск Ulash: TestFlight и Google Play

Инструкция для владельца аккаунтов. Сборка и загрузка выполняются в Codemagic по файлу `codemagic.yaml` в корне репозитория. Ключи и сертификаты никогда не хранятся в репозитории.

## Что уже настроено в проекте

| Параметр | Значение |
|---|---|
| Название под иконкой | Ulash |
| iOS Bundle ID | `uz.ulash.app` (тесты: `uz.ulash.app.RunnerTests`) |
| Android applicationId | `uz.ulash.app`; debug-сборка ставится рядом как `uz.ulash.app.debug` |
| Минимальные ОС | iOS 16, Android 10 (API 29), target API 37 |
| Устройства iOS | iPhone и iPad (адаптивная раскладка) |
| Языки | русский (основной), узбекский (латиница), английский |
| Шифрование | `ITSAppUsesNonExemptEncryption = false` (см. раздел 6) |
| Privacy manifest | Tracking = нет, собираемых данных нет; API: DiskSpace (E174.1, 85F4.1), FileTimestamp (C617.1, 3B52.1) |
| Резервные копии | iOS: служебные каталоги исключаются из iCloud через `excludeFromBackup`; Android: облачный бэкап и перенос между устройствами отключены (`data_extraction_rules.xml`) |
| Иконки | генерируются скриптом `python3 scripts/generate_icons.py` из `apps/file_transfer/assets/branding/` |

Bundle ID и applicationId после первой публикации сменить нельзя.

---

## 1. Apple Developer: регистрация идентификатора

1. Откройте https://developer.apple.com/account → **Certificates, Identifiers & Profiles** → **Identifiers** → **+**.
2. Выберите **App IDs** → **App**.
3. Description: `Ulash`. Bundle ID: **Explicit**, `uz.ulash.app`.
4. Дополнительные capabilities не нужны. Приложение использует только свой keychain по умолчанию, камеру и локальную сеть, а для них отдельные capabilities не требуются.
5. **Register**.

## 2. App Store Connect: карточка приложения

1. https://appstoreconnect.apple.com → **Apps** → **+** → **New App**.
2. Platforms: **iOS**.
3. Name: `Ulash`. Если имя занято, используйте вариант с подзаголовком, например «Ulash — передача файлов». Имя под иконкой на телефоне останется «Ulash».
4. Primary Language: **Russian**.
5. Bundle ID: `uz.ulash.app`.
6. SKU: любой внутренний код, например `ulash-ios`.
7. User Access: **Full Access**.
8. После создания откройте **App Information** и скопируйте **Apple ID** — это число вида `6740000000`. Оно нужно в шаге 4.

## 3. Ключ App Store Connect API

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**.
2. Name: `Codemagic`, Access: **App Manager**.
3. Скачайте файл `AuthKey_XXXX.p8`. Скачать его можно **только один раз**.
4. Запишите **Key ID** и **Issuer ID** (указан над таблицей ключей).

## 4. Codemagic

1. Зарегистрируйтесь на https://codemagic.io и подключите репозиторий с этим проектом (GitHub, GitLab или Bitbucket). При добавлении приложения выберите конфигурацию **codemagic.yaml**.
2. **Teams → Integrations → Developer Portal → Connect / Manage keys → Add key**:
   - Name: **`Ulash App Store Connect`** — точно так же, как в `codemagic.yaml`;
   - Issuer ID, Key ID и файл `.p8` из шага 3.
3. **Ключ для сертификата дистрибуции.** Один постоянный ключ не даёт Codemagic создавать новый сертификат при каждой сборке. Apple допускает лишь несколько сертификатов дистрибуции.
   - Сгенерируйте ключ на своём компьютере:

     ```bash
     ssh-keygen -t rsa -b 2048 -m PEM -f ulash_cert_key -q -N ""
     ```

   - В Codemagic: приложение → **Environment variables** → добавьте переменную `CERTIFICATE_PRIVATE_KEY`:
     - значение — **всё содержимое** файла `ulash_cert_key`, включая строки BEGIN/END;
     - группа — **`ios_signing_key`**;
     - отметьте **Secure**.
   - Храните файл `ulash_cert_key` в надёжном месте. Не добавляйте его в репозиторий.
4. В `codemagic.yaml` замените `APP_STORE_APPLE_ID: "0000000000"` числом из шага 2.8 и закоммитьте. Пока стоит заглушка, сборка остановится на шаге «Check placeholders».
5. В разделе `publishing.email` замените `release@example.com` на свой адрес.

## 5. Первая сборка в TestFlight

1. Codemagic → приложение → **Start new build** → ветка с релизом → workflow **iOS → TestFlight**.
2. Сборка выполняется так:
   - тесты ядра и приложения;
   - получение или создание сертификата и provisioning profile;
   - `flutter build ipa` с версией из `pubspec.yaml`;
   - загрузка в App Store Connect.
3. Номер сборки вычисляется автоматически: последний номер в App Store Connect + 1.
4. Через 5–30 минут после загрузки Apple обработает сборку. Она появится в **TestFlight**.
5. **Внутреннее тестирование** (до 100 участников вашей команды App Store Connect, без проверки Apple):
   - TestFlight → **Internal Testing** → **+** → создайте группу;
   - добавьте тестировщиков и выберите сборку;
   - тестировщики устанавливают приложение через TestFlight на iPhone.
6. **Внешнее тестирование** (по ссылке, до 10 000 человек) требует проверки Beta App Review:
   - заполните **Test Information**: описание, контактный e-mail, инструкцию «что тестировать»;
   - в `codemagic.yaml` установите `submit_to_testflight: true` и укажите `beta_groups`.

### Подсказка для проверяющих Apple

Приложению нужен второй сопряжённый девайс. В поле **Review Notes** (TestFlight → Test Information, позже — App Review Information) приложите:

- пошаговую инструкцию: «Получить» → «Показать приглашение» → на втором устройстве «Устройства» → сканировать QR → подтвердить → отправить файл;
- ссылку на короткое видео передачи между двумя устройствами.

## 6. Экспортный контроль шифрования

В `Info.plist` указано `ITSAppUsesNonExemptEncryption = false`, поэтому App Store Connect не задаёт вопрос об экспорте при каждой загрузке.

- **Обоснование:** приложение использует только стандартные открытые протоколы — TLS 1.2+ и ECDSA P-256 через встроенную в Dart библиотеку BoringSSL — для защиты передаваемых пользователем файлов. Шифрование не является основной функцией продукта. Приложение массового рынка, собственной криптографии нет. Такие приложения обычно подпадают под освобождение (mass market, EAR категория 5D992).
- **Ответственность:** окончательное решение остаётся за владельцем аккаунта. При сомнениях проконсультируйтесь с юристом.
- **Если вывод не подтвердится:** удалите ключ из `Info.plist` и ответьте на вопросы App Store Connect вручную.
- **Франция:** для распространения во Франции может потребоваться отдельная декларация.

## 7. App Privacy и политика конфиденциальности

- **App Privacy** (App Store Connect → App Privacy): **Data Not Collected**.
  - Приложение не использует аналитику, рекламу, аккаунты или облако. Файлы передаются только напрямую между устройствами пользователя.
  - Отчёты о сбоях Apple, на которые пользователь соглашается в системных настройках, не считаются сбором данных разработчиком.
- **Privacy Policy URL** обязателен. Опубликуйте страницу политики, например на GitHub Pages или своём сайте, и укажите ссылку в App Information.
- Если позже будет добавлен сторонний сервис отчётов о сбоях, обновите App Privacy и `PrivacyInfo.xcprivacy` **до** выпуска.

## 8. Google Play (workflow `android-internal`)

1. Создайте upload keystore (один раз; храните копию в безопасном месте):

   ```bash
   keytool -genkeypair -v -keystore ulash-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Codemagic → **Code signing identities → Android keystores** → загрузите `ulash-upload.jks`. Reference name: **`ulash_upload_keystore`**. Укажите пароли и alias.
3. **Play Console**:
   - создайте приложение `Ulash` с пакетом `uz.ulash.app`;
   - включите **Play App Signing**;
   - **первый AAB загрузите вручную** (артефакт сборки Codemagic) во внутреннее тестирование.
4. Для автоматической публикации:
   - создайте сервисный аккаунт Google Cloud с доступом к Play Console (роль Release manager);
   - добавьте его JSON в Codemagic как секретную переменную `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` в группу **`google_play`**.
5. Заполните форму **Data safety**: данные не собираются и не передаются. Сканер QR использует ML Kit на устройстве; изображения с камеры не покидают устройство.
6. Новые **личные** аккаунты разработчика обязаны провести закрытое тестирование: минимум 12 тестировщиков в течение 14 дней до выхода в production.

### Локальная release-сборка Android без Codemagic

Создайте `apps/file_transfer/android/key.properties`. Файл уже в `.gitignore`, не коммитьте его.

```properties
storeFile=/абсолютный/путь/ulash-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Без ключа release-сборка остаётся неподписанной. Debug-ключ для release не используется никогда.

## 9. Иконки

- Исходник: `apps/file_transfer/assets/branding/ulash_icon.svg` (две стрелки обмена на фирменном бирюзовом градиенте).
- Пересоздать все размеры iOS, Android (обычные, adaptive, monochrome, launch) и Windows:

  ```bash
  python3 scripts/generate_icons.py
  ```

  Нужны Python 3 с Pillow и Node.js с Playwright (headless Chromium).

## 10. Что проверить перед каждой загрузкой

- [ ] `python3 scripts/verify.py` — анализаторы и тесты проходят.
- [ ] Версия в `apps/file_transfer/pubspec.yaml` увеличена (`X.Y.Z+N`; номер сборки Codemagic выставит сам).
- [ ] В интерфейсе нет слов alpha/beta/test и неработающих кнопок.
- [ ] Установка поверх предыдущей сборки TestFlight сохраняет историю и полученные файлы.
- [ ] На iPhone: разрешение «Локальная сеть» запрашивается, отказ показывает экран с кнопкой «Настройки».
