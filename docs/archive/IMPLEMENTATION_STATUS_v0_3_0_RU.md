# Статус реализации 0.3.0

**Дата:** 21 ноября 2026. **Объект:** приложение по ТЗ v1.0, третья итерация разработки.

Содержимое этого репозитория — работающая техническая альфа. Формулировка «реализовано» ниже означает наличие выполняемого кода и указанных автоматических проверок; она не означает прохождение физической платформенной матрицы или готовность к магазинам.

## Соответствие основным разделам ТЗ

| Раздел ТЗ | Реализовано в этой итерации | Что остаётся |
|---|---|---|
| 1–5. Продукт, сценарии, экраны | Пять экранов, выбор/подготовка, доверенные устройства, входящие согласия, очередь/история, темы, desktop/mobile layouts, экран хранилища и состояния экспорта | UZ/EN, продуктовая приёмка на телефонах, окончательная марка/иконки |
| 6. Архитектура | Отдельный Dart core, Flutter UI contract, coordinator, AppRuntime и native adapters | Полный role selection Host/Client, native background modules |
| 7. Обнаружение | Bonjour/NSD adapter, QR fallback, bounded candidates, проверка pin после разрешения адреса | Реальные iOS/Android/Windows discovery-тесты, IPv6-only/link-local scope, автоматический мониторинг смены Wi-Fi/интерфейса |
| 8. Доверие | EC P-256 identity, OS SecretStore, SPKI SHA-256, случайные directional credentials, pending/approval/commit, persistence, revoke | Независимый security review, полный clock-skew/fuzz corpus, продвинутое управление pending-парами |
| 9. Источник | Потоковая immutable staging copy, локальная проверка изменения обычного источника, provider stream API, сохранение после удаления оригинала | Нативный version/coordinated snapshot контракт провайдеров, отмена зависшего provider-read, оптимизация без копирования |
| 10–11. Контракт | Версионированные manifest/limits/errors, decimal-string sizes, idempotent offers, peer ownership, TLS before credentials | Полный перечень capability-negotiation/long-poll endpoints и interoperable schema/OpenAPI |
| 12. Передача | Foreground push, HEAD/PATCH offsets, поток, backpressure, докачка, пустые файлы, no redirects | Pull/Range, receipt sequence и agreed reset-receive protocol |
| 13. Сохранение | SQLite WAL/FULL, flush→journal→ACK, disk SHA-256, commit intent/rename/recovery, per-root exclusive lease | Physical filesystem fault tests, native no-follow/no-replace hardening, power-loss campaign |
| 14. Состояния | Consent, expiry 120 с, own pause flags, cancel-vs-commit, durable cancellation intent, пять сетевых повторов с прерыванием, явная новая отправка retained copies | Полная автоматическая очередь, выборочный retry failed file, полная смешанная матрица версий |
| 15. Локальные данные | Входящие/исходящие SQLite, журнал экспорта; общий бюджет, системное измерение места, квоты 5/10/20/50 ГиБ, recovery обязательств, явная очистка исходящих копий и journal-owned входящих частей с защитой commit intent | Сроки 7/30 дней, лимит истории, очистка orphan вне журнала и долговременная проверка |
| 16. Имена и содержание | Безопасные имена, запрет traversal/опасных staging links, неперезапись результата, локальный случайный каталог | Аппаратная проверка системных экспортов, audit гонок с локальным filesystem actor; расширенные политики выбора назначения |
| 17. iOS | Runner iOS 16, camera/LAN/Bonjour/Keychain, document export, volume capacity, PrivacyInfo для disk-space API | Сборка на macOS, реальный iPhone, Share Extension/App Group, Photos экспорт, native background gate |
| 18. Android | Runner min API29/target API37, picker, LAN/camera/secure store, SAF export потоками 64 КиБ, StatFs, отдельный debug ID .alpha02 | Установка/аппаратные разрешения, foreground service, OEM battery behaviour, provider/reboot matrix |
| 19. Windows | Runner, picker/drop, protected store, Save dialog, worker copy без перезаписи, GetDiskFreeSpaceExW | Нативная Windows-сборка, firewall UX, tray, Explorer, installer/signing/update |
| 20–22. Ошибки и QA | Русские сообщения, fail-closed состояния, автоматические storage/network/controller/UI checks, 1 ГиБ loopback probe | Полная QA-01…QA-30 матрица, 9 направлений, 5/10 ГиБ и 1 000 файлов, физические показатели |
| 23–25. Разработка и сдача | Исходники, lockfiles, скрипт проверок, native CI jobs, ADR, отчёты, previews, инструкции сборки | Подписанные release builds, distribution/update pipeline, окончательные privacy/store материалы |
| 26. Следующие версии | Core/UI границы допускают расширение | Интернет/WebRTC/TURN, web-гость, Wi-Fi Aware, облако и синхронизация не реализованы |

## Числа: что измерено, а что является настройкой

Выполнено **110 автоматических тестов: 61 ядра и 49 приложения**, анализаторы без замечаний. По сравнению с 0.2 добавлена 31 проверка. Новые сценарии проверяют expiry и миграцию старого журнала, cleanup/cancel/commit races, конечный бюджет повторов, пять способов остановки ожидания, отсутствие снятия чужой паузы, новую отправку единственной подготовленной копии и настоящий TLS-обрыв с автоматической докачкой. Отдельный screenshot harness запускается с `CAPTURE_UI=true` и не входит в это число.

В предыдущей версии 0.2 выполнена передача файла **1 ГиБ = 1 073 741 824 байта** с общим бюджетом, исходящей подготовленной копией, разрывом после **4 718 592 байт**, закрытием/открытием обоих хранилищ и успешной докачкой. Независимый Python SHA-256 совпал. В конце после validated receipt и очистки исходящей копии: **0 байт временных данных, 0 байт будущего резерва**. Отчёт: `verification/loopback_v02_1g.json`. Этот отдельный гигабайтный сценарий повторно на 0.3 не запускался; актуальная новая интеграционная проверка передаёт 16 777 353 байта через настоящий TCP/TLS с одним автоматическим повтором, сохранением IDs, докачкой подтверждённого префикса и SHA-256. Данные: `verification/network_retry_v03.json`.

**20 ГиБ** — выбранный лимит временных данных по умолчанию; **128 МиБ** — политика запаса при доступном измерении ОС. Эти числа не являются измерением производительности. Настройки квоты: 5/10/20/50 ГиБ. Система может отказать при реальной записи даже после успешной проверки места, поэтому ошибки записи сохраняют durable checkpoint.

Ограничения протокола **10 ГиБ/файл, 1 000 файлов, 50 ГиБ/пакет** проверяются валидаторами, но аппаратная проверка этих максимумов ещё не выполнена. Отдельный Linux CLI использует `availableBytes=null`; его результат подтверждает учёт резервов и файловый протокол, а не Android/iOS/Windows capacity API.

## Граница с Gate A

Gate A из ТЗ **не закрыт**. Для его закрытия нужны устанавливаемые экземпляры на физических iOS, Android и Windows, все шесть межплатформенных направлений, 1 МиБ/1 ГиБ, отключённый WAN, независимые hashes. Совместная работа двух контроллеров в Linux проверяет общую логику и протокол, но не системные особенности этих платформ.

## Приоритет следующего этапа

| Задача | Результат | Критерий приёмки |
|---|---|---|
| DEV-01. Установка Android alpha | Проверка запуска, выбора и разрешений на реальном Android | APK запускается, denied/granted LAN и camera управляемы; контент URI не требует broad-storage permission |
| DEV-02. Windows x64 build | Исполняемый пакет на Windows | Стандартный пользователь, DPAPI persistence, picker/drop, закрытие/повторный запуск, firewall только для приложения |
| DEV-03. iOS build/signing | Установка на iPhone под выбранной командой разработчика | Keychain сохраняет identity; Bonjour permission; Files/provider stream; foreground receive/send и resume |
| DEV-04. Шесть межплатформенных направлений | Матрица DIR-01…06 с фактическими устройствами | В каждом направлении 1 МиБ/1 ГиБ совпадает по независимому SHA-256 при выключенном WAN |
| DEV-05. Контроль хранилища | Preflight, общие резервы, квота, recovery, ручная исходящая и входящая очистка реализованы; остались retention и orphan вне журнала | Автотесты пройдены; нативные замеры, заполнение физического диска и сроки хранения требуют проверки |
| DEV-06. Host-selection и pull | iPhone как исходящий HTTPS client в обоих направлениях | Range/ETag/receipts, ownership, incarnation reset и тесты всех гонок |
| DEV-07. Native lifecycle | Android connected-device foreground service; iOS Share Extension; Windows tray | Отдельные physical tests, корректное разрешение/отказ и прекращение по действию пользователя |
| DEV-08. Полный релизный QA | QA-01…QA-30, fail injection, 5/10 ГиБ, большие пакеты | Зафиксированные модели, версии ОС, сеть, commit и hashes; отсутствие блокирующих дефектов |
| DEV-09. Локализация и экспорт | Системный экспорт и отдельный durable журнал реализованы; UZ/EN и Photos остаются | Native provider hardware matrix, проверка прерывания/отмены, ошибки назначения и cloud provider |
| DEV-10. Release package | Название, identifiers, production signing, permissions/privacy, обновление | Подписанные пакеты тестируются как отдельный Gate D; debug-ключи не используются |

Это техническая последовательность, а не обещание календарного срока. Итоговая оценка следующего выпуска уточняется после аппаратной проверки DEV-01…04.

## Android 0.3: обновление линии 0.2

Сертификат debug 0.3 совпадает с выданной 0.2, applicationId сохранён: `uz.sardor.file_transfer.alpha02`. Версия 0.3.0+3 подготовлена для обновления 0.2 с сохранением данных; фактическая установка обновления на телефон пока не проверялась. Имя — «Передача файлов α0.3». Миграция SQLite проверена отдельно автоматическим тестом.

Сертификат исходной 0.1 отличался: эта линия остаётся отдельной установкой, автоматической миграции из неё нет. Не следует удалять прежнее приложение ради обхода несовпадения подписи. Постоянное production signing остаётся частью release gate.

## Совместимость состояния истечения

Новый wire enum `expired` поддерживается 0.3. Старый клиент 0.2 прекращает обработку такого ответа с ошибкой, не объявляя успешную доставку. Для тестов новой функции обновляются обе стороны. Полная mixed-version матрица и capability negotiation остаются открытыми. Внутри процесса TTL монотонный; после перезапуска UTC fallback не может обнаружить все изменения системных часов. Подробности: `adr/0002_retry_expiry_and_cleanup.md`.
