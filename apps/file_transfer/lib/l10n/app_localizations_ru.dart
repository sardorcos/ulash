// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get unitB => 'Б';

  @override
  String get unitKiB => 'КиБ';

  @override
  String get unitMiB => 'МиБ';

  @override
  String get unitGiB => 'ГиБ';

  @override
  String get unitTiB => 'ТиБ';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файла',
      many: '$count файлов',
      few: '$count файла',
      one: '$count файл',
    );
    return '$_temp0';
  }

  @override
  String get platformUnknown => 'Устройство';

  @override
  String get phasePreparing => 'Подготавливаем файлы';

  @override
  String get phaseQueued => 'В очереди';

  @override
  String get phaseRetrying => 'Повторяем подключение';

  @override
  String get phaseWaitingForConsent => 'Ждём подтверждения';

  @override
  String get phaseTransferring => 'Передаём файлы';

  @override
  String get phaseVerifying => 'Проверяем файл';

  @override
  String get phaseCompleted => 'Передача завершена';

  @override
  String get phasePaused => 'Передача приостановлена';

  @override
  String get phaseFailed => 'Не удалось завершить';

  @override
  String get phaseCancelled => 'Передача отменена';

  @override
  String get phaseExpired => 'Время ожидания истекло';

  @override
  String get networkStarting => 'Подключение…';

  @override
  String get networkReady => 'Локальная сеть';

  @override
  String get networkUnavailable => 'Нет подключения';

  @override
  String get networkPermissionRequired => 'Нужен доступ к сети';

  @override
  String speedPerSecond(String value) {
    return '$value / с';
  }

  @override
  String get navSend => 'Отправить';

  @override
  String get navReceive => 'Получить';

  @override
  String get navDevices => 'Устройства';

  @override
  String get navHistory => 'История';

  @override
  String get navSettings => 'Настройки';

  @override
  String get actionFailedRetry =>
      'Не удалось выполнить действие. Попробуйте ещё раз.';

  @override
  String get localNetworkNotice =>
      'Нет доступа к локальной сети. Откройте Настройки → Ulash и включите «Локальная сеть», затем нажмите «Повторить».';

  @override
  String get openSettingsShort => 'Настройки';

  @override
  String get retry => 'Повторить';

  @override
  String get incomingWaitingNotice =>
      'Входящие файлы ждут вашего подтверждения';

  @override
  String get view => 'Посмотреть';

  @override
  String get pairingWaitingNotice => 'Новое устройство запрашивает подключение';

  @override
  String get check => 'Проверить';

  @override
  String get sidebarTagline => 'Между вашими\nустройствами';

  @override
  String get sidebarTaglineDetail => 'Файлы передаются\nпо локальной сети.';

  @override
  String get sendEyebrow => 'ЛОКАЛЬНАЯ ПЕРЕДАЧА';

  @override
  String get sendTitle => 'Файлы — на нужном\nустройстве.';

  @override
  String get sendSubtitle =>
      'Выберите, что отправить, и кому. Фото, видео и документы останутся в исходном качестве.';

  @override
  String get recipientStep => '2. Получатель';

  @override
  String get recipientSubtitle => 'Доступные доверенные устройства';

  @override
  String get refreshDevices => 'Обновить устройства';

  @override
  String get connectDeviceTitle => 'Подключите устройство';

  @override
  String get connectDeviceHint =>
      'Откройте приложение на втором устройстве и добавьте его по приглашению.';

  @override
  String get connect => 'Подключить';

  @override
  String get chooseRecipient => 'Выберите получателя';

  @override
  String get sendFiles => 'Отправить файлы';

  @override
  String get recipientWillConfirm =>
      'Получатель подтвердит передачу на своём устройстве.';

  @override
  String get currentTransfers => 'Текущие передачи';

  @override
  String get foldersUnsupported =>
      'Выберите отдельные файлы. Папки пока не поддерживаются.';

  @override
  String get dropFilesHere => 'Отпустите файлы здесь';

  @override
  String get filesStep => '1. Файлы';

  @override
  String get whatToSend => 'Что хотите отправить?';

  @override
  String get clearSelectedFiles => 'Очистить выбранные файлы';

  @override
  String get startWithFiles => 'Начнём с файлов';

  @override
  String get startWithFilesHint =>
      'Фото с телефона, рабочий документ\nили целое видео — выбирайте.';

  @override
  String get photosAndVideos => 'Фото и видео';

  @override
  String get files => 'Файлы';

  @override
  String get chooseFiles => 'Выбрать файлы';

  @override
  String get orDropHere => 'или перетащите их сюда';

  @override
  String get preparingFile => 'Подготавливаем файл…';

  @override
  String get preparationFailed => 'Не удалось подготовить';

  @override
  String get sizePending => 'Размер уточняется';

  @override
  String removeSource(String name) {
    return 'Убрать $name';
  }

  @override
  String get add => 'Добавить';

  @override
  String totalSize(String size) {
    return 'Всего: $size';
  }

  @override
  String get receiveEyebrow => 'ПОЛУЧЕНИЕ';

  @override
  String get receiveTitle => 'Здесь появятся\nваши файлы.';

  @override
  String get receiveSubtitle =>
      'Оставьте приложение открытым. Отправитель увидит устройство после подключения.';

  @override
  String get receivingOn => 'Приём включён';

  @override
  String get receivingOff => 'Приём выключен';

  @override
  String saveLocation(String location) {
    return 'Место сохранения: $location';
  }

  @override
  String get showInvitation => 'Показать приглашение';

  @override
  String get myDevices => 'Мои устройства';

  @override
  String get noIncomingTitle => 'Входящих предложений пока нет';

  @override
  String get noIncomingReady =>
      'Когда отправитель выберет это устройство, вы сможете проверить файлы и принять передачу.';

  @override
  String get noIncomingOff =>
      'Включите приём, когда будете готовы получить файлы.';

  @override
  String get incomingOffers => 'Входящие предложения';

  @override
  String andMoreFiles(String files) {
    return 'И ещё $files';
  }

  @override
  String offerValidUntil(String time) {
    return 'Предложение действует до $time. Без ответа отправителю понадобится создать новое предложение.';
  }

  @override
  String get acceptFiles => 'Принять файлы';

  @override
  String get decline => 'Отклонить';

  @override
  String get devicesEyebrow => 'ВАШИ УСТРОЙСТВА';

  @override
  String get devicesTitle => 'Один раз подключили.\nДальше — просто.';

  @override
  String get devicesSubtitle =>
      'Добавьте телефон или компьютер, чтобы отправлять файлы без повторной настройки.';

  @override
  String get connectDevice => 'Подключить устройство';

  @override
  String get appOpenBothSides =>
      'Приложение должно быть открыто на обеих сторонах.';

  @override
  String get createInvitation => 'Создать приглашение';

  @override
  String get enterInvitation => 'Ввести приглашение';

  @override
  String get scanInvitationTooltip =>
      'Сканировать приглашение с другого устройства';

  @override
  String get cameraUnavailableTooltip =>
      'Камера пока недоступна. Используйте текст приглашения.';

  @override
  String get scanQr => 'Сканировать QR';

  @override
  String deviceCodeHint(String code) {
    return 'Код этого устройства: $code. При подключении он должен совпасть с кодом в запросе на другом устройстве.';
  }

  @override
  String get pairingRequest => 'Запрос подключения';

  @override
  String get pairingConfirmGeneric =>
      'Подтвердите, если вы только что добавили это устройство.';

  @override
  String pairingConfirmCode(String code) {
    return 'Подтвердите, только если код $code совпадает с кодом на подключаемом устройстве.';
  }

  @override
  String get connectedDevices => 'Подключённые устройства';

  @override
  String get availabilityChecked => 'Доступность проверяется приложением';

  @override
  String get onlyThisDeviceTitle => 'Пока только это устройство';

  @override
  String get onlyThisDeviceHint =>
      'Создайте приглашение или введите приглашение со второго устройства. Оно появится здесь после подтверждения.';

  @override
  String disconnectDevice(String name) {
    return 'Отключить $name';
  }

  @override
  String get peerAvailable => 'Доступно';

  @override
  String get peerOffline => 'Не в сети';

  @override
  String get trustedDevice => 'Доверенное устройство';

  @override
  String get historyEyebrow => 'ИСТОРИЯ';

  @override
  String get historyTitle => 'Всё переданное.\nВ одном месте.';

  @override
  String get historySubtitle =>
      'Статус, получатель и сохранённые файлы. Незавершённые передачи тоже остаются здесь.';

  @override
  String get filterAll => 'Все';

  @override
  String get filterSent => 'Отправленные';

  @override
  String get filterReceived => 'Полученные';

  @override
  String get clearHistory => 'Очистить историю';

  @override
  String get historyEmptyTitle => 'История пока пуста';

  @override
  String get historyFilteredEmptyTitle => 'Таких передач пока нет';

  @override
  String get historyEmptyHint =>
      'После первой передачи здесь появится её результат.';

  @override
  String get historyFilteredEmptyHint =>
      'Выберите другой фильтр или начните новую передачу.';

  @override
  String showMore(int count) {
    return 'Показать ещё ($count)';
  }

  @override
  String get clearHistoryQuestion => 'Очистить историю?';

  @override
  String get clearHistoryBody =>
      'Будут удалены записи о завершённых, отменённых и неудачных передачах, а также их неиспользуемые подготовленные копии. Полученные файлы останутся — их можно удалить по отдельности.';

  @override
  String get cancel => 'Отмена';

  @override
  String get clear => 'Очистить';

  @override
  String get deleteReceivedQuestion => 'Удалить полученные файлы?';

  @override
  String get deleteRecordQuestion => 'Удалить запись?';

  @override
  String deleteReceivedBody(String title, String size) {
    return '$title\n\nПередача и её файлы ($size) будут удалены с этого устройства. Копии, которые вы уже сохранили или отправили через «Поделиться», останутся.';
  }

  @override
  String deleteRecordBody(String title) {
    return '$title\n\nЗапись будет удалена из истории вместе с неиспользуемыми подготовленными копиями. Если исходный файл уже удалён, такая копия могла быть единственной.';
  }

  @override
  String get delete => 'Удалить';

  @override
  String get shareFile => 'Поделиться файлом';

  @override
  String get close => 'Закрыть';

  @override
  String toPeer(String name) {
    return 'Кому: $name';
  }

  @override
  String fromPeer(String name) {
    return 'От кого: $name';
  }

  @override
  String savedAt(String location) {
    return 'Сохранено: $location';
  }

  @override
  String filesFolder(String location) {
    return 'Папка для файлов: $location';
  }

  @override
  String previouslySaved(String destination) {
    return 'Ранее сохранено: $destination';
  }

  @override
  String get pause => 'Пауза';

  @override
  String get resume => 'Продолжить';

  @override
  String get cancelTransfer => 'Отменить';

  @override
  String get sendAgain => 'Отправить снова';

  @override
  String get openFiles => 'Открыть файлы';

  @override
  String get openFile => 'Открыть файл';

  @override
  String get saveFileCopyEllipsis => 'Сохранить копию файла…';

  @override
  String get saveCopyEllipsis => 'Сохранить копию…';

  @override
  String get share => 'Поделиться';

  @override
  String get settingsEyebrow => 'НАСТРОЙКИ';

  @override
  String get settingsTitle => 'Удобно именно вам.';

  @override
  String get settingsSubtitle =>
      'Имя устройства, внешний вид и место для полученных файлов.';

  @override
  String get thisDevice => 'Это устройство';

  @override
  String get deviceName => 'Имя устройства';

  @override
  String deviceNameWithCode(String name, String code) {
    return '$name\nКод устройства: $code';
  }

  @override
  String get change => 'Изменить';

  @override
  String get receivedFiles => 'Полученные файлы';

  @override
  String get appearance => 'Внешний вид';

  @override
  String get themeSystem => 'Как в системе';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get language => 'Язык';

  @override
  String get languageSystem => 'Как в системе';

  @override
  String get connection => 'Подключение';

  @override
  String get localNetwork => 'Локальная сеть';

  @override
  String get trustedDevices => 'Доверенные устройства';

  @override
  String get trustedDevicesHint =>
      'Каждое новое устройство подключается с вашим подтверждением.';

  @override
  String get open => 'Открыть';

  @override
  String get privacyAndSupport => 'Конфиденциальность и поддержка';

  @override
  String get privacy => 'Конфиденциальность';

  @override
  String get privacySummary => 'Без аккаунтов, облака, рекламы и аналитики.';

  @override
  String get more => 'Подробнее';

  @override
  String get diagnosticsLog => 'Журнал диагностики';

  @override
  String get diagnosticsHint =>
      'Коды ошибок без имён файлов и адресов. Отправляется только вами.';

  @override
  String get send => 'Отправить';

  @override
  String get resetKeys => 'Сбросить ключи устройства';

  @override
  String get resetKeysHint =>
      'Отключит все устройства. Подключить их можно будет заново по QR-коду.';

  @override
  String get reset => 'Сбросить';

  @override
  String get privacyBody =>
      'Ulash передаёт файлы напрямую между вашими устройствами в локальной сети. Файлы не загружаются на серверы, приложение не требует аккаунта и не содержит рекламы, трекинга и аналитики.\n\nСоединения шифруются (TLS) и проверяются по ключу устройства, подтверждённому при подключении. Каждую входящую передачу вы принимаете сами.\n\nКамера используется только для сканирования QR-кода. Доступ к локальной сети нужен, чтобы найти ваши устройства. Журнал диагностики хранится на устройстве и отправляется только по вашему действию.';

  @override
  String get resetKeysQuestion => 'Сбросить ключи устройства?';

  @override
  String get resetKeysBody =>
      'Будут созданы новые ключи, а все подключённые устройства будут забыты. Чтобы снова обмениваться файлами, подключите их заново по QR-коду. Полученные файлы и история останутся.';

  @override
  String versionLabel(String version) {
    return 'Ulash $version';
  }

  @override
  String get storage => 'Хранилище';

  @override
  String get refreshStorage => 'Обновить сведения о месте';

  @override
  String get storageUnavailable => 'Сведения о хранилище пока недоступны.';

  @override
  String get freeSpace => 'Свободное место';

  @override
  String get freeSpaceUnknown =>
      'Система не сообщила объём. Проверка лимита временных копий работает.';

  @override
  String freeSpaceChecked(String size, String time) {
    return '$size · проверено $time';
  }

  @override
  String get temporaryCopies => 'Временные копии';

  @override
  String temporaryUsage(String used, String reserved) {
    return '$used уже занято; $reserved предусмотрено для начатых передач.';
  }

  @override
  String get quotaUsageSemantics => 'Использование лимита временного хранилища';

  @override
  String get quotaTitle => 'Лимит временного хранилища';

  @override
  String quotaHint(String reserve) {
    return 'Перед записью проверяется запас $reserve свободного места. Готовые полученные файлы не входят в этот лимит и не удаляются при очистке временных копий.';
  }

  @override
  String get unusedCopies => 'Неиспользуемые копии';

  @override
  String unusedCopiesSummary(String files, String size) {
    return '$files · $size';
  }

  @override
  String get clearUnusedCopies => 'Очистить неиспользуемые копии';

  @override
  String get incompleteIncoming => 'Незавершённый приём';

  @override
  String incompleteSummary(int count, String used, String reserved) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count передачи',
      many: '$count передач',
      few: '$count передачи',
      one: '$count передача',
    );
    return '$_temp0 · $used уже занято; $reserved предусмотрено для продолжения.';
  }

  @override
  String get incompleteHint =>
      'Очистка остановит выбранные входящие передачи и удалит их незавершённые части. Для них потребуется новая отправка. Уже полученные готовые файлы останутся на месте.';

  @override
  String get clearIncomplete => 'Очистить незавершённый приём';

  @override
  String get deleteTemporaryQuestion => 'Удалить временные копии?';

  @override
  String deleteTemporaryBody(int count, String size) {
    return 'Будет удалено до $count копий ($size), не используемых выбранными файлами и незавершёнными передачами. Для новой отправки их потребуется выбрать заново. Исходные и готовые полученные файлы останутся на месте. Если исходный файл уже удалён, временная копия может быть единственной; после очистки восстановить её из приложения нельзя.';
  }

  @override
  String fileWithSize(String name, String size) {
    return '$name · $size';
  }

  @override
  String andMoreFilesDot(int count) {
    return 'И ещё $count файлов.';
  }

  @override
  String get keep => 'Оставить';

  @override
  String get deleteCopies => 'Удалить копии';

  @override
  String get stopIncomingQuestion => 'Остановить приём и удалить части файлов?';

  @override
  String stopIncomingBody(int count, String used, String reserved) {
    return 'Будут остановлены перечисленные передачи: $count. Их незавершённые части сейчас занимают $used, ещё $reserved предусмотрено для продолжения. Объём может измениться, если приём ещё идёт. Продолжить эти передачи после очистки нельзя: отправителю потребуется создать новые. Готовые полученные файлы и история сохранятся.';
  }

  @override
  String incompleteItem(
    String title,
    String peer,
    String files,
    String size,
    int completed,
  ) {
    return '$title\n$peer · $files не завершено · $size\nГотовых файлов останется: $completed';
  }

  @override
  String get stopAndClear => 'Остановить и очистить';

  @override
  String get resendQuestion => 'Создать новую отправку?';

  @override
  String resendBody(String title, String peer, String size) {
    return '$title\nПолучатель: $peer\n\nПриложение использует сохранённые подготовленные копии ($size). Выбирать исходные файлы заново не потребуется. Получателю придёт новый запрос, который нужно подтвердить. Результат прежней попытки останется в истории.';
  }

  @override
  String get sendNewRequest => 'Отправить новый запрос';

  @override
  String get saveFileCopyTitle => 'Сохранить копию файла';

  @override
  String get receivedInApp => 'Получен в приложении';

  @override
  String get pairByInvitation => 'Подключиться по приглашению';

  @override
  String get pairByInvitationHint =>
      'На втором устройстве создайте приглашение и скопируйте его сюда целиком.';

  @override
  String get invitationText => 'Текст приглашения';

  @override
  String get pairConnect => 'Подключиться';

  @override
  String get renameHint =>
      'Это имя увидят другие устройства при подключении и передаче.';

  @override
  String get name => 'Имя';

  @override
  String get save => 'Сохранить';

  @override
  String disconnectQuestion(String name) {
    return 'Отключить $name?';
  }

  @override
  String get disconnectBody =>
      'Для следующей передачи это устройство потребуется подключить заново.';

  @override
  String get disconnect => 'Отключить';

  @override
  String get invitationTitle => 'Приглашение на устройство';

  @override
  String get invitationHint =>
      'Отсканируйте QR в приложении на другом устройстве или передайте текст приглашения.';

  @override
  String get invitationQrSemantics =>
      'QR-код временного приглашения на устройство';

  @override
  String get invitationExpired => 'Срок приглашения истёк. Создайте новое.';

  @override
  String invitationRemaining(String time) {
    return 'Действует ещё $time';
  }

  @override
  String get copied => 'Скопировано';

  @override
  String get copyInvitation => 'Скопировать приглашение';

  @override
  String get pairOnlyIfCodeMatches =>
      'Подключайте, только если этот код совпадает с кодом на экране подключаемого устройства.';

  @override
  String get requestNoLongerActive => 'Запрос больше не активен.';

  @override
  String get incomingFiles => 'Входящие файлы';

  @override
  String offerSummary(String peer, String files, String size) {
    return '$peer · $files · $size';
  }

  @override
  String filesAndSize(String files, String size) {
    return '$files · $size';
  }

  @override
  String get offerNoLongerActive => 'Предложение больше не активно.';

  @override
  String get onbTitle1 => 'Файлы между вашими устройствами';

  @override
  String get onbBody1 =>
      'Отправляйте фото, видео и документы с телефона на компьютер и обратно в исходном качестве — напрямую, без облака и без регистрации.';

  @override
  String get onbTitle2 => 'Одна сеть Wi-Fi';

  @override
  String get onbBody2 =>
      'Устройства должны быть в одной сети. Система попросит разрешить доступ к локальной сети — без него приложение не найдёт ваши устройства.';

  @override
  String get onbTitle3 => 'Только с вашего согласия';

  @override
  String get onbBody3 =>
      'Новое устройство подключается по QR-коду с подтверждением, а каждую входящую передачу вы принимаете сами. Данные шифруются.';

  @override
  String get skip => 'Пропустить';

  @override
  String onbStep(int current, int total) {
    return 'Шаг $current из $total';
  }

  @override
  String get start => 'Начать';

  @override
  String get next => 'Далее';

  @override
  String get resetKeysStartupBody =>
      'Будут созданы новые ключи. Все ранее подключённые устройства придётся подключить заново по QR-коду. Полученные файлы останутся на устройстве.';

  @override
  String get repairQuestion => 'Восстановить журнал?';

  @override
  String get repairBody =>
      'Повреждённый журнал будет отложен в сторону, приложение начнёт с чистого. История передач из этого журнала станет недоступна. Если вы недавно откатили версию приложения, лучше сначала обновить его.';

  @override
  String get repair => 'Восстановить';

  @override
  String get startupFailedTitle => 'Приложение не запустилось';

  @override
  String get repairJournal => 'Восстановить журнал';

  @override
  String get sendDiagnostics => 'Отправить журнал диагностики';

  @override
  String get scannerTitle => 'Подключить устройство';

  @override
  String get cameraUnavailable =>
      'Камера недоступна. Разрешите доступ в настройках или вернитесь и вставьте код подключения вручную.';

  @override
  String get openSettings => 'Открыть настройки';

  @override
  String get scannerHint =>
      'Наведите камеру на QR-код в разделе «Получить» на другом устройстве. Оба устройства должны быть в одной сети.';

  @override
  String get busyPreparingStorage => 'Подготовка защищённого хранилища';

  @override
  String get startupKeysFailed =>
      'Не удалось открыть защищённые ключи устройства. Разблокируйте устройство и повторите. Если ключи утрачены (например, после переноса на новый телефон), сбросьте их и подключите устройства заново.';

  @override
  String get startupJournalFailed =>
      'Журнал передач повреждён или создан более новой версией приложения. Обновите приложение или восстановите журнал.';

  @override
  String startupFailed(String reason) {
    return 'Не удалось запустить приложение. $reason';
  }

  @override
  String get allowLocalNetwork =>
      'Разрешите доступ к локальной сети в настройках приложения, затем нажмите «Обновить».';

  @override
  String get resetKeysFailed =>
      'Не удалось сбросить ключи. Перезапустите устройство и повторите.';

  @override
  String get defaultNameIos => 'Мой iPhone';

  @override
  String get defaultNameAndroid => 'Мой Android';

  @override
  String get defaultNameWindows => 'Мой Windows';

  @override
  String get defaultNameLinux => 'Мой Linux';

  @override
  String get defaultNameOther => 'Моё устройство';

  @override
  String get discoveryUnavailable =>
      'Автопоиск недоступен. Подключитесь по QR-коду в общей сети.';

  @override
  String get saveLocationMobile =>
      'В приложении. Чтобы сохранить файл в другое место, используйте «Поделиться» или «Сохранить копию…» в истории.';

  @override
  String get networkDenied =>
      'Доступ к локальной сети запрещён в настройках системы.';

  @override
  String get networkNoAddress =>
      'Подключите устройства к одной сети Wi-Fi или Ethernet.';

  @override
  String get networkKeepOpen =>
      'Локальная сеть · держите приложение открытым на обоих устройствах во время передачи';

  @override
  String get peerKeyVerified => 'Ключ устройства проверен';

  @override
  String get peerOpenApp => 'Откройте приложение на другом устройстве';

  @override
  String get peerScanToConnect => 'Для первого подключения отсканируйте QR-код';

  @override
  String get waitingForRecipient => 'Ожидание ответа получателя';

  @override
  String get busyChoosingMedia => 'Выбор фото и видео';

  @override
  String get busyChoosingFiles => 'Выбор файлов';

  @override
  String get pickerTitle => 'Выберите файлы';

  @override
  String busyPreparing(String name) {
    return 'Подготовка: $name';
  }

  @override
  String get waitCurrentSendOrPause =>
      'Дождитесь окончания текущей отправки или поставьте её на паузу.';

  @override
  String get requestSent =>
      'Запрос на получение отправлен. Подтвердите его на другом устройстве.';

  @override
  String get peerUnavailableOrRevoked =>
      'Устройство недоступно или доверие отозвано.';

  @override
  String get cancelRetriesExhausted =>
      'Автоматические попытки закончились. Отмена ещё не подтверждена; приложение уточнит результат, когда получатель снова будет доступен.';

  @override
  String get connectionLostAutoResume =>
      'Связь прервалась. Подтверждённый прогресс сохранён; передача продолжится автоматически, когда второе устройство снова будет в сети.';

  @override
  String get connectionNotRestored =>
      'Связь не восстановилась. Подтверждённый прогресс сохранён. Откройте приложение на обоих устройствах и нажмите «Продолжить».';

  @override
  String cancelRetrying(int attempt, int max, String seconds) {
    return 'Уточняем отмену: повтор $attempt из $max через $seconds с. Результат получателя пока неизвестен.';
  }

  @override
  String connectionRetrying(int attempt, int max, String seconds) {
    return 'Связь прервалась. Повтор $attempt из $max через $seconds с. Подтверждённый прогресс сохранён.';
  }

  @override
  String get senderPausedTapResume =>
      'Пауза отправителя. Для продолжения нажмите «Продолжить».';

  @override
  String get recipientPaused => 'Получатель поставил передачу на паузу.';

  @override
  String get consentExpiredNewRequest =>
      'Время ожидания согласия истекло. Для передачи нужен новый запрос.';

  @override
  String get receiveNotFinished =>
      'Приём не завершён. Выберите файлы заново для новой отправки.';

  @override
  String partiallySaved(int completed, int total) {
    return 'Сохранено $completed из $total файлов. Завершённые результаты доступны у получателя; остальные можно отправить заново.';
  }

  @override
  String get newRequestFromCopies =>
      'Создан новый запрос из сохранённых копий. Получатель должен подтвердить его заново.';

  @override
  String get senderPaused => 'Пауза отправителя';

  @override
  String get receiveAllowed =>
      'Приём разрешён. На отправителе нажмите «Продолжить», если передача остановлена.';

  @override
  String get waitCurrentSend => 'Дождитесь окончания текущей отправки.';

  @override
  String get confirmingCancel => 'Уточняем результат отмены у получателя.';

  @override
  String get tapResumeToConfirmCancel =>
      'Нажмите «Продолжить», чтобы подтвердить отмену у получателя.';

  @override
  String get recipientUnavailableCancel =>
      'Получатель недоступен. Отмена ещё не подтверждена; «Продолжить» повторно уточнит её результат.';

  @override
  String confirmPairingWithCode(String code) {
    return 'Подтвердите подключение на другом устройстве. Код этого устройства: $code — он должен совпасть с кодом в запросе.';
  }

  @override
  String pairedWith(String name) {
    return 'Подключено: $name. Теперь можно отправлять файлы.';
  }

  @override
  String get pairingApproved =>
      'Подключение подтверждено. Ожидается завершение сопряжения.';

  @override
  String get pairingDeclined => 'Запрос подключения отклонён.';

  @override
  String get trustRevokedCancelUnknown =>
      'Доверие отозвано. Удалённый результат отмены не подтверждён.';

  @override
  String get trustRevokedStopped => 'Доверие отозвано. Передача остановлена.';

  @override
  String get deviceRenamed =>
      'Имя устройства изменено. Подключённые устройства увидят его при следующем подключении.';

  @override
  String get transferDeleted => 'Передача удалена вместе с её файлами.';

  @override
  String get recordDeleted => 'Запись удалена из истории.';

  @override
  String historyCleared(int count) {
    return 'Удалено записей: $count. Полученные файлы сохранены.';
  }

  @override
  String diagnosticsSaved(String path) {
    return 'Журнал диагностики сохранён: $path';
  }

  @override
  String get quotaSaved => 'Лимит временного хранилища сохранён.';

  @override
  String get busyCleaningCopies => 'Очистка неиспользуемых копий';

  @override
  String copiesCleared(int count) {
    return 'Удалено неиспользуемых временных копий: $count. Полученные файлы сохранены.';
  }

  @override
  String get busyCleaningIncoming => 'Очистка незавершённого приёма';

  @override
  String incomingCleared(int stopped, int removed) {
    return 'Обработано незавершённых передач: $stopped. Удалено временных файлов: $removed. Готовые полученные файлы сохранены.';
  }

  @override
  String get exportNotExported => 'Получен в хранилище приложения';

  @override
  String get exportInProgress => 'Сохранение копии…';

  @override
  String exportDone(String destination) {
    return 'Копия сохранена: $destination';
  }

  @override
  String get exportCancelledDetail => 'Последнее сохранение отменено';

  @override
  String get exportFileChanged =>
      'Файл изменён или перемещён. Сохранение копии остановлено.';

  @override
  String get exportFailedDetail =>
      'Не удалось сохранить копию. Полученный файл остаётся в приложении.';

  @override
  String get exportUnknownDetail =>
      'Результат сохранения не подтверждён. Проверьте выбранную папку перед повтором.';

  @override
  String get exportCancelled =>
      'Сохранение копии отменено. Полученный файл остаётся в приложении.';

  @override
  String get cannotOpenFile =>
      'Файл сохранён, но подходящую программу открыть не удалось. Попробуйте «Поделиться» или «Сохранить копию…».';

  @override
  String get backgroundedWillResume =>
      'Приложение было свёрнуто. Передача продолжится, когда вы вернётесь в приложение.';

  @override
  String get interruptedOnClose =>
      'Передача остановлена при закрытии приложения. Нажмите «Продолжить» для проверки состояния у получателя.';

  @override
  String get verifiedAndSaved => 'SHA-256 проверен · сохранение подтверждено';

  @override
  String get consentNotReceived =>
      'Согласие не получено за 120 секунд. Для передачи нужен новый запрос.';

  @override
  String partSavedTapResume(String reason) {
    return '$reason Подтверждённая часть файла сохранена; затем нажмите «Продолжить».';
  }

  @override
  String get recipientPausedShort => 'Пауза получателя';

  @override
  String get consentRequired => 'Требуется согласие получателя';

  @override
  String get someFilesUnfinished =>
      'Есть незавершённые файлы. Проверенные результаты сохранены.';

  @override
  String get receivedFilesMissing =>
      'Полученные файлы удалены или перемещены вне приложения.';

  @override
  String get errPeerUnavailable =>
      'Устройство недоступно. Подключите оба устройства к одной сети и откройте приложение.';

  @override
  String get errQrExpired =>
      'Срок QR-кода истёк. Создайте новый код на другом устройстве.';

  @override
  String get errPairingRejected =>
      'Подключение отклонено на другом устройстве.';

  @override
  String get errSelfPairing => 'Этот QR-код принадлежит текущему устройству.';

  @override
  String get errUnauthorized =>
      'Доверие отозвано или сопряжение не завершено. Подключите устройства заново.';

  @override
  String get errConsentRequired =>
      'Получатель ещё не подтвердил приём. Подтвердите запрос и продолжите отправку.';

  @override
  String get errOfferExpired =>
      'Срок предложения истёк. Выберите файлы и отправьте новый запрос.';

  @override
  String get errTransferPaused =>
      'Передача приостановлена. Продолжение доступно после снятия паузы обеими сторонами.';

  @override
  String get errHashMismatch =>
      'Контрольная сумма не совпала. Файл не отмечен как готовый.';

  @override
  String get errSourceChanged =>
      'Исходный файл изменился во время подготовки. Выберите его повторно.';

  @override
  String get errFileTooLarge => 'Размер файла превышает предел — 10 ГиБ.';

  @override
  String get errDiskFull =>
      'Недостаточно свободного места с учётом начатых передач и резерва. Освободите место в настройках хранилища и повторите.';

  @override
  String get errTempQuotaExceeded =>
      'Достигнут лимит временных копий. Очистите неиспользуемые копии или увеличьте лимит в настройках.';

  @override
  String get errQuotaBelowUsage =>
      'Этот лимит меньше объёма временных копий и места для начатых передач. Сначала завершите передачи или освободите место.';

  @override
  String get errCapacityUnavailable =>
      'Не удалось определить доступное место. Повторите проверку в настройках хранилища.';

  @override
  String get errCommittedFileChanged =>
      'Полученный файл удалён, перемещён или изменён. Сохранение копии остановлено; проверьте файл.';

  @override
  String get errExportFailed =>
      'Не удалось сохранить внешнюю копию. Полученный файл остаётся в приложении; выберите другое место или повторите.';

  @override
  String get errExportSourceUnavailable =>
      'Полученный файл недоступен для сохранения копии. Проверьте, что он не удалён или перемещён.';

  @override
  String get errExportUnsupported =>
      'Системное сохранение не поддерживается на этом устройстве. Файл остаётся в приложении.';

  @override
  String get errExportBusy =>
      'Дождитесь завершения текущего сохранения или закройте открытое системное окно.';

  @override
  String get errDestinationExists =>
      'Файл с таким именем уже существует. Укажите другое имя или папку.';

  @override
  String get errRateLimited =>
      'Получатель временно ограничил число запросов. Повторите через несколько минут.';

  @override
  String get errQuotaExceeded =>
      'Передача больше доступного места на устройстве получателя.';

  @override
  String get errJournal =>
      'Журнал передач недоступен. Обновите приложение или восстановите журнал.';

  @override
  String get errIdentityChanged =>
      'Ключ другого устройства изменился. Удалите его из списка и подключите заново.';

  @override
  String get errTransferTooSlow =>
      'Соединение слишком медленное. Передача приостановлена и будет повторена.';

  @override
  String get errFileMissing =>
      'Полученный файл удалён или перемещён вне приложения.';

  @override
  String get errTransferActive =>
      'Завершите или отмените передачу, прежде чем удалять её.';

  @override
  String get errQueueFull =>
      'Очередь заполнена. Завершите или отмените незавершённые передачи.';

  @override
  String get errBusy => 'Получатель занят другой передачей. Повторите позже.';

  @override
  String get errNotFound =>
      'Данные этой передачи недоступны. Проверьте сохранённые файлы или выберите источник заново.';

  @override
  String get errHandshake =>
      'Не удалось проверить ключ устройства. Перепроверьте устройство и выполните сопряжение заново.';

  @override
  String get errConnectionLost =>
      'Соединение прервано. Откройте приложение на обоих устройствах и продолжите передачу.';

  @override
  String get errFormat =>
      'Некорректный QR-код или неподдерживаемый формат данных.';

  @override
  String get errFileSystem =>
      'Не удалось прочитать или сохранить файл. Проверьте доступ и свободное место.';

  @override
  String get errUnknown =>
      'Что-то пошло не так. Повторите действие. Если ошибка повторяется, отправьте журнал диагностики из настроек.';

  @override
  String errWithCode(String code) {
    return 'Операция остановлена (код $code). Данные не отмечены как успешно переданные.';
  }
}
