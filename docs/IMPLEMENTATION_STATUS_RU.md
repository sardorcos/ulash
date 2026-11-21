# Статус реализации 0.2.0

**Дата:** 21 ноября 2026. **Объект:** приложение по ТЗ v1.0, вторая итерация разработки.

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
| 14. Состояния | Consent, own pause flags, cancel-vs-commit, persistent cancellation intent, per-file and partial results | Полная автоматическая очередь, ограниченные повторные попытки по политике, отдельный retry failed file |
| 15. Локальные данные | Входящие/исходящие SQLite, журнал экспорта; общий бюджет, системное измерение места, квоты 5/10/20/50 ГиБ, recovery обязательств, явная очистка неиспользуемых исходящих копий | Сроки 7/30 дней, лимит истории, ручная очистка входящих partial/orphan и долговременная проверка |
| 16. Имена и содержание | Безопасные имена, запрет traversal/опасных staging links, неперезапись результата, локальный случайный каталог | Аппаратная проверка системных экспортов, audit гонок с локальным filesystem actor; расширенные политики выбора назначения |
| 17. iOS | Runner iOS 16, camera/LAN/Bonjour/Keychain, document export, volume capacity, PrivacyInfo для disk-space API | Сборка на macOS, реальный iPhone, Share Extension/App Group, Photos экспорт, native background gate |
| 18. Android | Runner min API29/target API37, picker, LAN/camera/secure store, SAF export потоками 64 КиБ, StatFs, отдельный debug ID .alpha02 | Установка/аппаратные разрешения, foreground service, OEM battery behaviour, provider/reboot matrix |
| 19. Windows | Runner, picker/drop, protected store, Save dialog, worker copy без перезаписи, GetDiskFreeSpaceExW | Нативная Windows-сборка, firewall UX, tray, Explorer, installer/signing/update |
| 20–22. Ошибки и QA | Русские сообщения, fail-closed состояния, автоматические storage/network/controller/UI checks, 1 ГиБ loopback probe | Полная QA-01…QA-30 матрица, 9 направлений, 5/10 ГиБ и 1 000 файлов, физические показатели |
| 23–25. Разработка и сдача | Исходники, lockfiles, скрипт проверок, native CI jobs, ADR, отчёты, previews, инструкции сборки | Подписанные release builds, distribution/update pipeline, окончательные privacy/store материалы |
| 26. Следующие версии | Core/UI границы допускают расширение | Интернет/WebRTC/TURN, web-гость, Wi-Fi Aware, облако и синхронизация не реализованы |

## Числа: что измерено, а что является настройкой

Выполнено **79 автоматических тестов: 46 ядра и 33 приложения**, анализаторы без замечаний. Отдельный screenshot harness пропускается в стандартном прогоне и запускается с `CAPTURE_UI=true`. Новые тесты проверяют дефицит места, конкуренцию входящих/исходящих резервов, recovery, очистку только допустимых копий, системные ответы экспорта, жизненный цикл picker и состояния интерфейса.

Повторная передача файла **1 ГиБ = 1 073 741 824 байта** с общим бюджетом, исходящей подготовленной копией, разрывом после **4 718 592 байт**, закрытием/открытием обоих хранилищ и докачкой завершена. Независимый Python SHA-256 совпал. В конце после validated receipt и очистки исходящей копии: **0 байт временных данных, 0 байт будущего резерва**. Отчёт: `verification/loopback_v02_1g.json`.

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
| DEV-05. Контроль хранилища | Preflight, общие резервы, квота, recovery и ручная исходящая очистка реализованы; остались retention и входящая очистка | Автотесты пройдены; нативные замеры, заполнение физического диска и сроки хранения требуют проверки |
| DEV-06. Host-selection и pull | iPhone как исходящий HTTPS client в обоих направлениях | Range/ETag/receipts, ownership, incarnation reset и тесты всех гонок |
| DEV-07. Native lifecycle | Android connected-device foreground service; iOS Share Extension; Windows tray | Отдельные physical tests, корректное разрешение/отказ и прекращение по действию пользователя |
| DEV-08. Полный релизный QA | QA-01…QA-30, fail injection, 5/10 ГиБ, большие пакеты | Зафиксированные модели, версии ОС, сеть, commit и hashes; отсутствие блокирующих дефектов |
| DEV-09. Локализация и экспорт | Системный экспорт и отдельный durable журнал реализованы; UZ/EN и Photos остаются | Native provider hardware matrix, проверка прерывания/отмены, ошибки назначения и cloud provider |
| DEV-10. Release package | Название, identifiers, production signing, permissions/privacy, обновление | Подписанные пакеты тестируются как отдельный Gate D; debug-ключи не используются |

Это техническая последовательность, а не обещание календарного срока. Итоговая оценка следующего выпуска уточняется после аппаратной проверки DEV-01…04.

## Android 0.2: отдельная установка

Сертификаты debug 0.1 и текущей среды различаются. Debug-only ID `uz.sardor.file_transfer.alpha02` позволяет сохранить старую установку и её данные. Новое имя — «Передача файлов α0.2». Это не автоматическое обновление 0.1 и не миграция; пары и локальное хранилище создаются отдельно. Постоянное подписывание обновлений остаётся частью release gate.
