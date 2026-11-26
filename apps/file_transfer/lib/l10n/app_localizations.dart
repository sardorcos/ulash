import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_uz.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ru'),
    Locale('uz'),
    Locale('en'),
  ];

  /// No description provided for @unitB.
  ///
  /// In ru, this message translates to:
  /// **'Б'**
  String get unitB;

  /// No description provided for @unitKiB.
  ///
  /// In ru, this message translates to:
  /// **'КБ'**
  String get unitKiB;

  /// No description provided for @unitMiB.
  ///
  /// In ru, this message translates to:
  /// **'МБ'**
  String get unitMiB;

  /// No description provided for @unitGiB.
  ///
  /// In ru, this message translates to:
  /// **'ГБ'**
  String get unitGiB;

  /// No description provided for @unitTiB.
  ///
  /// In ru, this message translates to:
  /// **'ТБ'**
  String get unitTiB;

  /// No description provided for @filesCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} файл} few{{count} файла} many{{count} файлов} other{{count} файла}}'**
  String filesCount(int count);

  /// No description provided for @platformUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Устройство'**
  String get platformUnknown;

  /// No description provided for @phasePreparing.
  ///
  /// In ru, this message translates to:
  /// **'Подготавливаем файлы'**
  String get phasePreparing;

  /// No description provided for @phaseQueued.
  ///
  /// In ru, this message translates to:
  /// **'В очереди'**
  String get phaseQueued;

  /// No description provided for @phaseRetrying.
  ///
  /// In ru, this message translates to:
  /// **'Повторяем подключение'**
  String get phaseRetrying;

  /// No description provided for @phaseWaitingForConsent.
  ///
  /// In ru, this message translates to:
  /// **'Ждём подтверждения'**
  String get phaseWaitingForConsent;

  /// No description provided for @phaseTransferring.
  ///
  /// In ru, this message translates to:
  /// **'Передаём файлы'**
  String get phaseTransferring;

  /// No description provided for @phaseVerifying.
  ///
  /// In ru, this message translates to:
  /// **'Проверяем файл'**
  String get phaseVerifying;

  /// No description provided for @phaseCompleted.
  ///
  /// In ru, this message translates to:
  /// **'Передача завершена'**
  String get phaseCompleted;

  /// No description provided for @phasePaused.
  ///
  /// In ru, this message translates to:
  /// **'Передача приостановлена'**
  String get phasePaused;

  /// No description provided for @phaseFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось завершить'**
  String get phaseFailed;

  /// No description provided for @phaseCancelled.
  ///
  /// In ru, this message translates to:
  /// **'Передача отменена'**
  String get phaseCancelled;

  /// No description provided for @phaseExpired.
  ///
  /// In ru, this message translates to:
  /// **'Время ожидания истекло'**
  String get phaseExpired;

  /// No description provided for @networkStarting.
  ///
  /// In ru, this message translates to:
  /// **'Подключение…'**
  String get networkStarting;

  /// No description provided for @networkReady.
  ///
  /// In ru, this message translates to:
  /// **'Локальная сеть'**
  String get networkReady;

  /// No description provided for @networkUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Нет подключения'**
  String get networkUnavailable;

  /// No description provided for @networkPermissionRequired.
  ///
  /// In ru, this message translates to:
  /// **'Нужен доступ к сети'**
  String get networkPermissionRequired;

  /// No description provided for @speedPerSecond.
  ///
  /// In ru, this message translates to:
  /// **'{value} / с'**
  String speedPerSecond(String value);

  /// No description provided for @navSend.
  ///
  /// In ru, this message translates to:
  /// **'Отправить'**
  String get navSend;

  /// No description provided for @navReceive.
  ///
  /// In ru, this message translates to:
  /// **'Получить'**
  String get navReceive;

  /// No description provided for @navDevices.
  ///
  /// In ru, this message translates to:
  /// **'Устройства'**
  String get navDevices;

  /// No description provided for @navHistory.
  ///
  /// In ru, this message translates to:
  /// **'История'**
  String get navHistory;

  /// No description provided for @navSettings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get navSettings;

  /// No description provided for @actionFailedRetry.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить действие. Попробуйте ещё раз.'**
  String get actionFailedRetry;

  /// No description provided for @localNetworkNotice.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа к локальной сети. Откройте Настройки → Ulash и включите «Локальная сеть», затем нажмите «Повторить».'**
  String get localNetworkNotice;

  /// No description provided for @openSettingsShort.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get openSettingsShort;

  /// No description provided for @retry.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get retry;

  /// No description provided for @incomingWaitingNotice.
  ///
  /// In ru, this message translates to:
  /// **'Входящие файлы ждут вашего подтверждения'**
  String get incomingWaitingNotice;

  /// No description provided for @view.
  ///
  /// In ru, this message translates to:
  /// **'Посмотреть'**
  String get view;

  /// No description provided for @pairingWaitingNotice.
  ///
  /// In ru, this message translates to:
  /// **'Новое устройство запрашивает подключение'**
  String get pairingWaitingNotice;

  /// No description provided for @check.
  ///
  /// In ru, this message translates to:
  /// **'Проверить'**
  String get check;

  /// No description provided for @sidebarTagline.
  ///
  /// In ru, this message translates to:
  /// **'Между вашими\nустройствами'**
  String get sidebarTagline;

  /// No description provided for @sidebarTaglineDetail.
  ///
  /// In ru, this message translates to:
  /// **'Файлы передаются\nпо локальной сети.'**
  String get sidebarTaglineDetail;

  /// No description provided for @sendEyebrow.
  ///
  /// In ru, this message translates to:
  /// **'ЛОКАЛЬНАЯ ПЕРЕДАЧА'**
  String get sendEyebrow;

  /// No description provided for @sendTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отправить'**
  String get sendTitle;

  /// No description provided for @sendSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Выберите, что отправить, и кому. Фото, видео и документы останутся в исходном качестве.'**
  String get sendSubtitle;

  /// No description provided for @recipientStep.
  ///
  /// In ru, this message translates to:
  /// **'2. Получатель'**
  String get recipientStep;

  /// No description provided for @recipientSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Доступные доверенные устройства'**
  String get recipientSubtitle;

  /// No description provided for @refreshDevices.
  ///
  /// In ru, this message translates to:
  /// **'Обновить устройства'**
  String get refreshDevices;

  /// No description provided for @connectDeviceTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключите устройство'**
  String get connectDeviceTitle;

  /// No description provided for @connectDeviceHint.
  ///
  /// In ru, this message translates to:
  /// **'Откройте приложение на втором устройстве и добавьте его по приглашению.'**
  String get connectDeviceHint;

  /// No description provided for @connect.
  ///
  /// In ru, this message translates to:
  /// **'Подключить'**
  String get connect;

  /// No description provided for @chooseRecipient.
  ///
  /// In ru, this message translates to:
  /// **'Выберите получателя'**
  String get chooseRecipient;

  /// No description provided for @sendFiles.
  ///
  /// In ru, this message translates to:
  /// **'Отправить файлы'**
  String get sendFiles;

  /// No description provided for @recipientWillConfirm.
  ///
  /// In ru, this message translates to:
  /// **'Получатель подтвердит передачу на своём устройстве.'**
  String get recipientWillConfirm;

  /// No description provided for @currentTransfers.
  ///
  /// In ru, this message translates to:
  /// **'Текущие передачи'**
  String get currentTransfers;

  /// No description provided for @foldersUnsupported.
  ///
  /// In ru, this message translates to:
  /// **'Выберите отдельные файлы. Папки пока не поддерживаются.'**
  String get foldersUnsupported;

  /// No description provided for @dropFilesHere.
  ///
  /// In ru, this message translates to:
  /// **'Отпустите файлы здесь'**
  String get dropFilesHere;

  /// No description provided for @filesStep.
  ///
  /// In ru, this message translates to:
  /// **'1. Файлы'**
  String get filesStep;

  /// No description provided for @whatToSend.
  ///
  /// In ru, this message translates to:
  /// **'Что хотите отправить?'**
  String get whatToSend;

  /// No description provided for @clearSelectedFiles.
  ///
  /// In ru, this message translates to:
  /// **'Очистить выбранные файлы'**
  String get clearSelectedFiles;

  /// No description provided for @startWithFiles.
  ///
  /// In ru, this message translates to:
  /// **'Начнём с файлов'**
  String get startWithFiles;

  /// No description provided for @startWithFilesHint.
  ///
  /// In ru, this message translates to:
  /// **'Фото с телефона, рабочий документ\nили целое видео — выбирайте.'**
  String get startWithFilesHint;

  /// No description provided for @photosAndVideos.
  ///
  /// In ru, this message translates to:
  /// **'Фото и видео'**
  String get photosAndVideos;

  /// No description provided for @files.
  ///
  /// In ru, this message translates to:
  /// **'Файлы'**
  String get files;

  /// No description provided for @chooseFiles.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать файлы'**
  String get chooseFiles;

  /// No description provided for @orDropHere.
  ///
  /// In ru, this message translates to:
  /// **'или перетащите их сюда'**
  String get orDropHere;

  /// No description provided for @preparingFile.
  ///
  /// In ru, this message translates to:
  /// **'Подготавливаем файл…'**
  String get preparingFile;

  /// No description provided for @preparationFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось подготовить'**
  String get preparationFailed;

  /// No description provided for @sizePending.
  ///
  /// In ru, this message translates to:
  /// **'Размер уточняется'**
  String get sizePending;

  /// No description provided for @removeSource.
  ///
  /// In ru, this message translates to:
  /// **'Убрать {name}'**
  String removeSource(String name);

  /// No description provided for @add.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get add;

  /// No description provided for @totalSize.
  ///
  /// In ru, this message translates to:
  /// **'Всего: {size}'**
  String totalSize(String size);

  /// No description provided for @receiveEyebrow.
  ///
  /// In ru, this message translates to:
  /// **'ПОЛУЧЕНИЕ'**
  String get receiveEyebrow;

  /// No description provided for @receiveTitle.
  ///
  /// In ru, this message translates to:
  /// **'Здесь появятся\nваши файлы.'**
  String get receiveTitle;

  /// No description provided for @receiveSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Оставьте приложение открытым. Отправитель увидит устройство после подключения.'**
  String get receiveSubtitle;

  /// No description provided for @receivingOn.
  ///
  /// In ru, this message translates to:
  /// **'Приём включён'**
  String get receivingOn;

  /// No description provided for @receivingOff.
  ///
  /// In ru, this message translates to:
  /// **'Приём выключен'**
  String get receivingOff;

  /// No description provided for @saveLocation.
  ///
  /// In ru, this message translates to:
  /// **'Место сохранения: {location}'**
  String saveLocation(String location);

  /// No description provided for @showInvitation.
  ///
  /// In ru, this message translates to:
  /// **'Показать QR'**
  String get showInvitation;

  /// No description provided for @myDevices.
  ///
  /// In ru, this message translates to:
  /// **'Мои устройства'**
  String get myDevices;

  /// No description provided for @noIncomingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Входящих предложений пока нет'**
  String get noIncomingTitle;

  /// No description provided for @noIncomingReady.
  ///
  /// In ru, this message translates to:
  /// **'Когда отправитель выберет это устройство, вы сможете проверить файлы и принять передачу.'**
  String get noIncomingReady;

  /// No description provided for @noIncomingOff.
  ///
  /// In ru, this message translates to:
  /// **'Включите приём, когда будете готовы получить файлы.'**
  String get noIncomingOff;

  /// No description provided for @incomingOffers.
  ///
  /// In ru, this message translates to:
  /// **'Ждут вашего ответа'**
  String get incomingOffers;

  /// No description provided for @andMoreFiles.
  ///
  /// In ru, this message translates to:
  /// **'И ещё {files}'**
  String andMoreFiles(String files);

  /// No description provided for @offerValidUntil.
  ///
  /// In ru, this message translates to:
  /// **'Предложение действует до {time}. Без ответа отправителю понадобится создать новое предложение.'**
  String offerValidUntil(String time);

  /// No description provided for @acceptFiles.
  ///
  /// In ru, this message translates to:
  /// **'Принять файлы'**
  String get acceptFiles;

  /// No description provided for @decline.
  ///
  /// In ru, this message translates to:
  /// **'Отклонить'**
  String get decline;

  /// No description provided for @devicesEyebrow.
  ///
  /// In ru, this message translates to:
  /// **'ВАШИ УСТРОЙСТВА'**
  String get devicesEyebrow;

  /// No description provided for @devicesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Один раз подключили.\nДальше — просто.'**
  String get devicesTitle;

  /// No description provided for @devicesSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте телефон или компьютер, чтобы отправлять файлы без повторной настройки.'**
  String get devicesSubtitle;

  /// No description provided for @connectDevice.
  ///
  /// In ru, this message translates to:
  /// **'Подключить устройство'**
  String get connectDevice;

  /// No description provided for @appOpenBothSides.
  ///
  /// In ru, this message translates to:
  /// **'Приложение должно быть открыто на обеих сторонах.'**
  String get appOpenBothSides;

  /// No description provided for @createInvitation.
  ///
  /// In ru, this message translates to:
  /// **'Показать QR'**
  String get createInvitation;

  /// No description provided for @enterInvitation.
  ///
  /// In ru, this message translates to:
  /// **'Ввести код'**
  String get enterInvitation;

  /// No description provided for @scanInvitationTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Сканировать приглашение с другого устройства'**
  String get scanInvitationTooltip;

  /// No description provided for @cameraUnavailableTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Камера пока недоступна. Используйте текст приглашения.'**
  String get cameraUnavailableTooltip;

  /// No description provided for @scanQr.
  ///
  /// In ru, this message translates to:
  /// **'Сканировать QR'**
  String get scanQr;

  /// No description provided for @deviceCodeHint.
  ///
  /// In ru, this message translates to:
  /// **'Код этого устройства: {code}. При подключении он должен совпасть с кодом в запросе на другом устройстве.'**
  String deviceCodeHint(String code);

  /// No description provided for @pairingRequest.
  ///
  /// In ru, this message translates to:
  /// **'Запрос подключения'**
  String get pairingRequest;

  /// No description provided for @pairingConfirmGeneric.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердите, если вы только что добавили это устройство.'**
  String get pairingConfirmGeneric;

  /// No description provided for @pairingConfirmCode.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердите, только если код {code} совпадает с кодом на подключаемом устройстве.'**
  String pairingConfirmCode(String code);

  /// No description provided for @connectedDevices.
  ///
  /// In ru, this message translates to:
  /// **'Подключённые устройства'**
  String get connectedDevices;

  /// No description provided for @availabilityChecked.
  ///
  /// In ru, this message translates to:
  /// **'Доступность проверяется приложением'**
  String get availabilityChecked;

  /// No description provided for @onlyThisDeviceTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пока только это устройство'**
  String get onlyThisDeviceTitle;

  /// No description provided for @onlyThisDeviceHint.
  ///
  /// In ru, this message translates to:
  /// **'Создайте приглашение или введите приглашение со второго устройства. Оно появится здесь после подтверждения.'**
  String get onlyThisDeviceHint;

  /// No description provided for @disconnectDevice.
  ///
  /// In ru, this message translates to:
  /// **'Отключить {name}'**
  String disconnectDevice(String name);

  /// No description provided for @peerAvailable.
  ///
  /// In ru, this message translates to:
  /// **'Доступно'**
  String get peerAvailable;

  /// No description provided for @peerOffline.
  ///
  /// In ru, this message translates to:
  /// **'Не в сети'**
  String get peerOffline;

  /// No description provided for @trustedDevice.
  ///
  /// In ru, this message translates to:
  /// **'Доверенное устройство'**
  String get trustedDevice;

  /// No description provided for @historyEyebrow.
  ///
  /// In ru, this message translates to:
  /// **'ИСТОРИЯ'**
  String get historyEyebrow;

  /// No description provided for @historyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Всё переданное.\nВ одном месте.'**
  String get historyTitle;

  /// No description provided for @historySubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Статус, получатель и сохранённые файлы. Незавершённые передачи тоже остаются здесь.'**
  String get historySubtitle;

  /// No description provided for @filterAll.
  ///
  /// In ru, this message translates to:
  /// **'Все'**
  String get filterAll;

  /// No description provided for @filterSent.
  ///
  /// In ru, this message translates to:
  /// **'Отправленные'**
  String get filterSent;

  /// No description provided for @filterReceived.
  ///
  /// In ru, this message translates to:
  /// **'Полученные'**
  String get filterReceived;

  /// No description provided for @clearHistory.
  ///
  /// In ru, this message translates to:
  /// **'Очистить историю'**
  String get clearHistory;

  /// No description provided for @historyEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'История пока пуста'**
  String get historyEmptyTitle;

  /// No description provided for @historyFilteredEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Таких передач пока нет'**
  String get historyFilteredEmptyTitle;

  /// No description provided for @historyEmptyHint.
  ///
  /// In ru, this message translates to:
  /// **'После первой передачи здесь появится её результат.'**
  String get historyEmptyHint;

  /// No description provided for @historyFilteredEmptyHint.
  ///
  /// In ru, this message translates to:
  /// **'Выберите другой фильтр или начните новую передачу.'**
  String get historyFilteredEmptyHint;

  /// No description provided for @showMore.
  ///
  /// In ru, this message translates to:
  /// **'Показать ещё ({count})'**
  String showMore(int count);

  /// No description provided for @clearHistoryQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Очистить историю?'**
  String get clearHistoryQuestion;

  /// No description provided for @clearHistoryBody.
  ///
  /// In ru, this message translates to:
  /// **'Будут удалены записи о завершённых, отменённых и неудачных передачах, а также их неиспользуемые подготовленные копии. Полученные файлы останутся — их можно удалить по отдельности.'**
  String get clearHistoryBody;

  /// No description provided for @cancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// No description provided for @clear.
  ///
  /// In ru, this message translates to:
  /// **'Очистить'**
  String get clear;

  /// No description provided for @deleteReceivedQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Удалить полученные файлы?'**
  String get deleteReceivedQuestion;

  /// No description provided for @deleteRecordQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Удалить запись?'**
  String get deleteRecordQuestion;

  /// No description provided for @deleteReceivedBody.
  ///
  /// In ru, this message translates to:
  /// **'{title}\n\nПередача и её файлы ({size}) будут удалены с этого устройства. Копии, которые вы уже сохранили или отправили через «Поделиться», останутся.'**
  String deleteReceivedBody(String title, String size);

  /// No description provided for @deleteRecordBody.
  ///
  /// In ru, this message translates to:
  /// **'{title}\n\nЗапись будет удалена из истории вместе с неиспользуемыми подготовленными копиями. Если исходный файл уже удалён, такая копия могла быть единственной.'**
  String deleteRecordBody(String title);

  /// No description provided for @delete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get delete;

  /// No description provided for @shareFile.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться файлом'**
  String get shareFile;

  /// No description provided for @close.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get close;

  /// No description provided for @toPeer.
  ///
  /// In ru, this message translates to:
  /// **'Кому: {name}'**
  String toPeer(String name);

  /// No description provided for @fromPeer.
  ///
  /// In ru, this message translates to:
  /// **'От кого: {name}'**
  String fromPeer(String name);

  /// No description provided for @savedAt.
  ///
  /// In ru, this message translates to:
  /// **'Сохранено: {location}'**
  String savedAt(String location);

  /// No description provided for @filesFolder.
  ///
  /// In ru, this message translates to:
  /// **'Папка для файлов: {location}'**
  String filesFolder(String location);

  /// No description provided for @previouslySaved.
  ///
  /// In ru, this message translates to:
  /// **'Ранее сохранено: {destination}'**
  String previouslySaved(String destination);

  /// No description provided for @pause.
  ///
  /// In ru, this message translates to:
  /// **'Пауза'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get resume;

  /// No description provided for @cancelTransfer.
  ///
  /// In ru, this message translates to:
  /// **'Отменить'**
  String get cancelTransfer;

  /// No description provided for @sendAgain.
  ///
  /// In ru, this message translates to:
  /// **'Отправить снова'**
  String get sendAgain;

  /// No description provided for @openFiles.
  ///
  /// In ru, this message translates to:
  /// **'Открыть файлы'**
  String get openFiles;

  /// No description provided for @openFile.
  ///
  /// In ru, this message translates to:
  /// **'Открыть файл'**
  String get openFile;

  /// No description provided for @saveFileCopyEllipsis.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить копию файла…'**
  String get saveFileCopyEllipsis;

  /// No description provided for @saveCopyEllipsis.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить копию…'**
  String get saveCopyEllipsis;

  /// No description provided for @share.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться'**
  String get share;

  /// No description provided for @settingsEyebrow.
  ///
  /// In ru, this message translates to:
  /// **'НАСТРОЙКИ'**
  String get settingsEyebrow;

  /// No description provided for @settingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удобно именно вам.'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Имя устройства, внешний вид и место для полученных файлов.'**
  String get settingsSubtitle;

  /// No description provided for @thisDevice.
  ///
  /// In ru, this message translates to:
  /// **'Это устройство'**
  String get thisDevice;

  /// No description provided for @deviceName.
  ///
  /// In ru, this message translates to:
  /// **'Имя устройства'**
  String get deviceName;

  /// No description provided for @deviceNameWithCode.
  ///
  /// In ru, this message translates to:
  /// **'{name}\nКод устройства: {code}'**
  String deviceNameWithCode(String name, String code);

  /// No description provided for @change.
  ///
  /// In ru, this message translates to:
  /// **'Изменить'**
  String get change;

  /// No description provided for @receivedFiles.
  ///
  /// In ru, this message translates to:
  /// **'Полученные файлы'**
  String get receivedFiles;

  /// No description provided for @appearance.
  ///
  /// In ru, this message translates to:
  /// **'Внешний вид'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get languageSystem;

  /// No description provided for @connection.
  ///
  /// In ru, this message translates to:
  /// **'Подключение'**
  String get connection;

  /// No description provided for @localNetwork.
  ///
  /// In ru, this message translates to:
  /// **'Локальная сеть'**
  String get localNetwork;

  /// No description provided for @trustedDevices.
  ///
  /// In ru, this message translates to:
  /// **'Доверенные устройства'**
  String get trustedDevices;

  /// No description provided for @trustedDevicesHint.
  ///
  /// In ru, this message translates to:
  /// **'Каждое новое устройство подключается только с вашим подтверждением.'**
  String get trustedDevicesHint;

  /// No description provided for @open.
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get open;

  /// No description provided for @privacyAndSupport.
  ///
  /// In ru, this message translates to:
  /// **'Конфиденциальность и поддержка'**
  String get privacyAndSupport;

  /// No description provided for @privacy.
  ///
  /// In ru, this message translates to:
  /// **'Конфиденциальность'**
  String get privacy;

  /// No description provided for @privacySummary.
  ///
  /// In ru, this message translates to:
  /// **'Без аккаунтов, облака, рекламы и аналитики.'**
  String get privacySummary;

  /// No description provided for @more.
  ///
  /// In ru, this message translates to:
  /// **'Подробнее'**
  String get more;

  /// No description provided for @diagnosticsLog.
  ///
  /// In ru, this message translates to:
  /// **'Отчёт для поддержки'**
  String get diagnosticsLog;

  /// No description provided for @diagnosticsHint.
  ///
  /// In ru, this message translates to:
  /// **'Коды ошибок без имён файлов и адресов. Отправляете только вы.'**
  String get diagnosticsHint;

  /// No description provided for @send.
  ///
  /// In ru, this message translates to:
  /// **'Отправить'**
  String get send;

  /// No description provided for @resetKeys.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить ключи устройства'**
  String get resetKeys;

  /// No description provided for @resetKeysHint.
  ///
  /// In ru, this message translates to:
  /// **'Отключит все устройства. Подключить их можно будет заново по QR-коду.'**
  String get resetKeysHint;

  /// No description provided for @reset.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить'**
  String get reset;

  /// No description provided for @privacyBody.
  ///
  /// In ru, this message translates to:
  /// **'Ulash передаёт файлы напрямую между вашими устройствами в локальной сети. Файлы не загружаются на серверы, приложение не требует аккаунта и не содержит рекламы, трекинга и аналитики.\n\nСоединения шифруются (TLS) и проверяются по ключу устройства, подтверждённому при подключении. Каждую входящую передачу вы принимаете сами.\n\nКамера используется только для сканирования QR-кода. Доступ к локальной сети нужен, чтобы найти ваши устройства. Журнал диагностики хранится на устройстве и отправляется только по вашему действию.'**
  String get privacyBody;

  /// No description provided for @resetKeysQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить ключи устройства?'**
  String get resetKeysQuestion;

  /// No description provided for @resetKeysBody.
  ///
  /// In ru, this message translates to:
  /// **'Будут созданы новые ключи, а все подключённые устройства будут забыты. Чтобы снова обмениваться файлами, подключите их заново по QR-коду. Полученные файлы и история останутся.'**
  String get resetKeysBody;

  /// No description provided for @versionLabel.
  ///
  /// In ru, this message translates to:
  /// **'Ulash {version}'**
  String versionLabel(String version);

  /// No description provided for @storage.
  ///
  /// In ru, this message translates to:
  /// **'Хранилище'**
  String get storage;

  /// No description provided for @refreshStorage.
  ///
  /// In ru, this message translates to:
  /// **'Обновить сведения о месте'**
  String get refreshStorage;

  /// No description provided for @storageUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Сведения о хранилище пока недоступны.'**
  String get storageUnavailable;

  /// No description provided for @freeSpace.
  ///
  /// In ru, this message translates to:
  /// **'Свободное место'**
  String get freeSpace;

  /// No description provided for @freeSpaceUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Система не сообщила объём. Проверка лимита временных копий работает.'**
  String get freeSpaceUnknown;

  /// No description provided for @freeSpaceChecked.
  ///
  /// In ru, this message translates to:
  /// **'{size} · проверено {time}'**
  String freeSpaceChecked(String size, String time);

  /// No description provided for @temporaryCopies.
  ///
  /// In ru, this message translates to:
  /// **'Подготовленные копии'**
  String get temporaryCopies;

  /// No description provided for @temporaryUsage.
  ///
  /// In ru, this message translates to:
  /// **'{used} уже занято; {reserved} предусмотрено для начатых передач.'**
  String temporaryUsage(String used, String reserved);

  /// No description provided for @quotaUsageSemantics.
  ///
  /// In ru, this message translates to:
  /// **'Использование лимита временного хранилища'**
  String get quotaUsageSemantics;

  /// No description provided for @quotaTitle.
  ///
  /// In ru, this message translates to:
  /// **'Лимит временного хранилища'**
  String get quotaTitle;

  /// No description provided for @quotaHint.
  ///
  /// In ru, this message translates to:
  /// **'Перед записью проверяется запас {reserve} свободного места. Готовые полученные файлы не входят в этот лимит и не удаляются при очистке временных копий.'**
  String quotaHint(String reserve);

  /// No description provided for @unusedCopies.
  ///
  /// In ru, this message translates to:
  /// **'Неиспользуемые копии'**
  String get unusedCopies;

  /// No description provided for @unusedCopiesSummary.
  ///
  /// In ru, this message translates to:
  /// **'{files} · {size}'**
  String unusedCopiesSummary(String files, String size);

  /// No description provided for @clearUnusedCopies.
  ///
  /// In ru, this message translates to:
  /// **'Очистить неиспользуемые копии'**
  String get clearUnusedCopies;

  /// No description provided for @incompleteIncoming.
  ///
  /// In ru, this message translates to:
  /// **'Незавершённый приём'**
  String get incompleteIncoming;

  /// No description provided for @incompleteSummary.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} передача} few{{count} передачи} many{{count} передач} other{{count} передачи}} · {used} уже занято; {reserved} предусмотрено для продолжения.'**
  String incompleteSummary(int count, String used, String reserved);

  /// No description provided for @incompleteHint.
  ///
  /// In ru, this message translates to:
  /// **'Очистка остановит выбранные входящие передачи и удалит их незавершённые части. Для них потребуется новая отправка. Уже полученные готовые файлы останутся на месте.'**
  String get incompleteHint;

  /// No description provided for @clearIncomplete.
  ///
  /// In ru, this message translates to:
  /// **'Очистить незавершённый приём'**
  String get clearIncomplete;

  /// No description provided for @deleteTemporaryQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Удалить временные копии?'**
  String get deleteTemporaryQuestion;

  /// No description provided for @deleteTemporaryBody.
  ///
  /// In ru, this message translates to:
  /// **'Будет удалено до {count} копий ({size}), не используемых выбранными файлами и незавершёнными передачами. Для новой отправки их потребуется выбрать заново. Исходные и готовые полученные файлы останутся на месте. Если исходный файл уже удалён, временная копия может быть единственной; после очистки восстановить её из приложения нельзя.'**
  String deleteTemporaryBody(int count, String size);

  /// No description provided for @fileWithSize.
  ///
  /// In ru, this message translates to:
  /// **'{name} · {size}'**
  String fileWithSize(String name, String size);

  /// No description provided for @andMoreFilesDot.
  ///
  /// In ru, this message translates to:
  /// **'И ещё {count} файлов.'**
  String andMoreFilesDot(int count);

  /// No description provided for @keep.
  ///
  /// In ru, this message translates to:
  /// **'Оставить'**
  String get keep;

  /// No description provided for @deleteCopies.
  ///
  /// In ru, this message translates to:
  /// **'Удалить копии'**
  String get deleteCopies;

  /// No description provided for @stopIncomingQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Остановить приём и удалить части файлов?'**
  String get stopIncomingQuestion;

  /// No description provided for @stopIncomingBody.
  ///
  /// In ru, this message translates to:
  /// **'Будут остановлены перечисленные передачи: {count}. Их незавершённые части сейчас занимают {used}, ещё {reserved} предусмотрено для продолжения. Объём может измениться, если приём ещё идёт. Продолжить эти передачи после очистки нельзя: отправителю потребуется создать новые. Готовые полученные файлы и история сохранятся.'**
  String stopIncomingBody(int count, String used, String reserved);

  /// No description provided for @incompleteItem.
  ///
  /// In ru, this message translates to:
  /// **'{title}\n{peer} · {files} не завершено · {size}\nГотовых файлов останется: {completed}'**
  String incompleteItem(
    String title,
    String peer,
    String files,
    String size,
    int completed,
  );

  /// No description provided for @stopAndClear.
  ///
  /// In ru, this message translates to:
  /// **'Остановить и очистить'**
  String get stopAndClear;

  /// No description provided for @resendQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Создать новую отправку?'**
  String get resendQuestion;

  /// No description provided for @resendBody.
  ///
  /// In ru, this message translates to:
  /// **'{title}\nПолучатель: {peer}\n\nПриложение использует сохранённые подготовленные копии ({size}). Выбирать исходные файлы заново не потребуется. Получателю придёт новый запрос, который нужно подтвердить. Результат прежней попытки останется в истории.'**
  String resendBody(String title, String peer, String size);

  /// No description provided for @sendNewRequest.
  ///
  /// In ru, this message translates to:
  /// **'Отправить новый запрос'**
  String get sendNewRequest;

  /// No description provided for @saveFileCopyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить копию файла'**
  String get saveFileCopyTitle;

  /// No description provided for @receivedInApp.
  ///
  /// In ru, this message translates to:
  /// **'Получен в приложении'**
  String get receivedInApp;

  /// No description provided for @pairByInvitation.
  ///
  /// In ru, this message translates to:
  /// **'Подключение по коду'**
  String get pairByInvitation;

  /// No description provided for @pairByInvitationHint.
  ///
  /// In ru, this message translates to:
  /// **'На другом устройстве нажмите «Показать QR» → «Скопировать код» и вставьте код сюда целиком.'**
  String get pairByInvitationHint;

  /// No description provided for @invitationText.
  ///
  /// In ru, this message translates to:
  /// **'Код подключения'**
  String get invitationText;

  /// No description provided for @pairConnect.
  ///
  /// In ru, this message translates to:
  /// **'Подключиться'**
  String get pairConnect;

  /// No description provided for @renameHint.
  ///
  /// In ru, this message translates to:
  /// **'Это имя увидят другие устройства при подключении и передаче.'**
  String get renameHint;

  /// No description provided for @name.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get name;

  /// No description provided for @save.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get save;

  /// No description provided for @disconnectQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Отключить {name}?'**
  String disconnectQuestion(String name);

  /// No description provided for @disconnectBody.
  ///
  /// In ru, this message translates to:
  /// **'Для следующей передачи это устройство потребуется подключить заново.'**
  String get disconnectBody;

  /// No description provided for @disconnect.
  ///
  /// In ru, this message translates to:
  /// **'Отключить'**
  String get disconnect;

  /// No description provided for @invitationTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключение устройства'**
  String get invitationTitle;

  /// No description provided for @invitationHint.
  ///
  /// In ru, this message translates to:
  /// **'Отсканируйте этот QR-код в Ulash на другом устройстве.'**
  String get invitationHint;

  /// No description provided for @invitationQrSemantics.
  ///
  /// In ru, this message translates to:
  /// **'QR-код для подключения устройства'**
  String get invitationQrSemantics;

  /// No description provided for @invitationExpired.
  ///
  /// In ru, this message translates to:
  /// **'Срок действия QR-кода истёк. Создайте новый.'**
  String get invitationExpired;

  /// No description provided for @invitationRemaining.
  ///
  /// In ru, this message translates to:
  /// **'Действует ещё {time}'**
  String invitationRemaining(String time);

  /// No description provided for @copied.
  ///
  /// In ru, this message translates to:
  /// **'Скопировано'**
  String get copied;

  /// No description provided for @copyInvitation.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать код'**
  String get copyInvitation;

  /// No description provided for @pairOnlyIfCodeMatches.
  ///
  /// In ru, this message translates to:
  /// **'Подключайте, только если этот код совпадает с кодом на экране подключаемого устройства.'**
  String get pairOnlyIfCodeMatches;

  /// No description provided for @requestNoLongerActive.
  ///
  /// In ru, this message translates to:
  /// **'Запрос больше не активен.'**
  String get requestNoLongerActive;

  /// No description provided for @incomingFiles.
  ///
  /// In ru, this message translates to:
  /// **'Входящие файлы'**
  String get incomingFiles;

  /// No description provided for @offerSummary.
  ///
  /// In ru, this message translates to:
  /// **'{peer} · {files} · {size}'**
  String offerSummary(String peer, String files, String size);

  /// No description provided for @filesAndSize.
  ///
  /// In ru, this message translates to:
  /// **'{files} · {size}'**
  String filesAndSize(String files, String size);

  /// No description provided for @offerNoLongerActive.
  ///
  /// In ru, this message translates to:
  /// **'Предложение больше не активно.'**
  String get offerNoLongerActive;

  /// No description provided for @onbTitle1.
  ///
  /// In ru, this message translates to:
  /// **'Файлы между вашими устройствами'**
  String get onbTitle1;

  /// No description provided for @onbBody1.
  ///
  /// In ru, this message translates to:
  /// **'Фото, видео и документы — между телефоном и компьютером в исходном качестве. Без облака и регистрации, а каждую передачу вы подтверждаете сами.'**
  String get onbBody1;

  /// No description provided for @onbTitle2.
  ///
  /// In ru, this message translates to:
  /// **'Одна сеть Wi-Fi'**
  String get onbTitle2;

  /// No description provided for @onbBody2.
  ///
  /// In ru, this message translates to:
  /// **'Устройства должны быть в одной сети. Система попросит разрешить доступ к локальной сети — без него приложение не найдёт ваши устройства.'**
  String get onbBody2;

  /// No description provided for @onbTitle3.
  ///
  /// In ru, this message translates to:
  /// **'Только с вашего согласия'**
  String get onbTitle3;

  /// No description provided for @onbBody3.
  ///
  /// In ru, this message translates to:
  /// **'Новое устройство подключается по QR-коду с подтверждением, а каждую входящую передачу вы принимаете сами. Данные шифруются.'**
  String get onbBody3;

  /// No description provided for @skip.
  ///
  /// In ru, this message translates to:
  /// **'Пропустить'**
  String get skip;

  /// No description provided for @onbStep.
  ///
  /// In ru, this message translates to:
  /// **'Шаг {current} из {total}'**
  String onbStep(int current, int total);

  /// No description provided for @start.
  ///
  /// In ru, this message translates to:
  /// **'Начать'**
  String get start;

  /// No description provided for @next.
  ///
  /// In ru, this message translates to:
  /// **'Далее'**
  String get next;

  /// No description provided for @resetKeysStartupBody.
  ///
  /// In ru, this message translates to:
  /// **'Будут созданы новые ключи. Все ранее подключённые устройства придётся подключить заново по QR-коду. Полученные файлы останутся на устройстве.'**
  String get resetKeysStartupBody;

  /// No description provided for @repairQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить журнал?'**
  String get repairQuestion;

  /// No description provided for @repairBody.
  ///
  /// In ru, this message translates to:
  /// **'Повреждённый журнал будет отложен в сторону, приложение начнёт с чистого. История передач из этого журнала станет недоступна. Если вы недавно откатили версию приложения, лучше сначала обновить его.'**
  String get repairBody;

  /// No description provided for @repair.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить'**
  String get repair;

  /// No description provided for @startupFailedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Приложение не запустилось'**
  String get startupFailedTitle;

  /// No description provided for @repairJournal.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить журнал'**
  String get repairJournal;

  /// No description provided for @sendDiagnostics.
  ///
  /// In ru, this message translates to:
  /// **'Отправить журнал диагностики'**
  String get sendDiagnostics;

  /// No description provided for @scannerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключить устройство'**
  String get scannerTitle;

  /// No description provided for @cameraUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Камера недоступна. Разрешите доступ в настройках или вернитесь и введите код подключения вручную.'**
  String get cameraUnavailable;

  /// No description provided for @openSettings.
  ///
  /// In ru, this message translates to:
  /// **'Открыть настройки'**
  String get openSettings;

  /// No description provided for @scannerHint.
  ///
  /// In ru, this message translates to:
  /// **'Наведите камеру на QR-код: на другом устройстве откройте Ulash → «Устройства» → «Показать QR». Оба устройства должны быть в одной сети.'**
  String get scannerHint;

  /// No description provided for @busyPreparingStorage.
  ///
  /// In ru, this message translates to:
  /// **'Подготовка защищённого хранилища'**
  String get busyPreparingStorage;

  /// No description provided for @startupKeysFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть защищённые ключи устройства. Разблокируйте устройство и повторите. Если ключи утрачены (например, после переноса на новый телефон), сбросьте их и подключите устройства заново.'**
  String get startupKeysFailed;

  /// No description provided for @startupJournalFailed.
  ///
  /// In ru, this message translates to:
  /// **'Журнал передач повреждён или создан более новой версией приложения. Обновите приложение или восстановите журнал.'**
  String get startupJournalFailed;

  /// No description provided for @startupFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось запустить приложение. {reason}'**
  String startupFailed(String reason);

  /// No description provided for @allowLocalNetwork.
  ///
  /// In ru, this message translates to:
  /// **'Разрешите доступ к локальной сети в настройках приложения, затем нажмите «Обновить».'**
  String get allowLocalNetwork;

  /// No description provided for @resetKeysFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сбросить ключи. Перезапустите устройство и повторите.'**
  String get resetKeysFailed;

  /// No description provided for @defaultNameIos.
  ///
  /// In ru, this message translates to:
  /// **'Мой iPhone'**
  String get defaultNameIos;

  /// No description provided for @defaultNameAndroid.
  ///
  /// In ru, this message translates to:
  /// **'Мой Android'**
  String get defaultNameAndroid;

  /// No description provided for @defaultNameWindows.
  ///
  /// In ru, this message translates to:
  /// **'Мой Windows'**
  String get defaultNameWindows;

  /// No description provided for @defaultNameLinux.
  ///
  /// In ru, this message translates to:
  /// **'Мой Linux'**
  String get defaultNameLinux;

  /// No description provided for @defaultNameOther.
  ///
  /// In ru, this message translates to:
  /// **'Моё устройство'**
  String get defaultNameOther;

  /// No description provided for @discoveryUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Автопоиск недоступен. Подключитесь по QR-коду в общей сети.'**
  String get discoveryUnavailable;

  /// No description provided for @saveLocationMobile.
  ///
  /// In ru, this message translates to:
  /// **'В приложении. Чтобы сохранить файл в другое место, используйте «Поделиться» или «Сохранить копию…» в истории.'**
  String get saveLocationMobile;

  /// No description provided for @networkDenied.
  ///
  /// In ru, this message translates to:
  /// **'Доступ к локальной сети запрещён в настройках системы.'**
  String get networkDenied;

  /// No description provided for @networkNoAddress.
  ///
  /// In ru, this message translates to:
  /// **'Подключите устройства к одной сети Wi-Fi или Ethernet.'**
  String get networkNoAddress;

  /// No description provided for @networkKeepOpen.
  ///
  /// In ru, this message translates to:
  /// **'Локальная сеть · держите приложение открытым на обоих устройствах во время передачи'**
  String get networkKeepOpen;

  /// No description provided for @peerKeyVerified.
  ///
  /// In ru, this message translates to:
  /// **'Ключ устройства проверен'**
  String get peerKeyVerified;

  /// No description provided for @peerOpenApp.
  ///
  /// In ru, this message translates to:
  /// **'Откройте приложение на другом устройстве'**
  String get peerOpenApp;

  /// No description provided for @peerScanToConnect.
  ///
  /// In ru, this message translates to:
  /// **'Для первого подключения отсканируйте QR-код'**
  String get peerScanToConnect;

  /// No description provided for @waitingForRecipient.
  ///
  /// In ru, this message translates to:
  /// **'Ожидание ответа получателя'**
  String get waitingForRecipient;

  /// No description provided for @busyChoosingMedia.
  ///
  /// In ru, this message translates to:
  /// **'Выбор фото и видео'**
  String get busyChoosingMedia;

  /// No description provided for @busyChoosingFiles.
  ///
  /// In ru, this message translates to:
  /// **'Выбор файлов'**
  String get busyChoosingFiles;

  /// No description provided for @pickerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выберите файлы'**
  String get pickerTitle;

  /// No description provided for @busyPreparing.
  ///
  /// In ru, this message translates to:
  /// **'Подготовка: {name}'**
  String busyPreparing(String name);

  /// No description provided for @waitCurrentSendOrPause.
  ///
  /// In ru, this message translates to:
  /// **'Дождитесь окончания текущей отправки или поставьте её на паузу.'**
  String get waitCurrentSendOrPause;

  /// No description provided for @requestSent.
  ///
  /// In ru, this message translates to:
  /// **'Запрос на получение отправлен. Подтвердите его на другом устройстве.'**
  String get requestSent;

  /// No description provided for @peerUnavailableOrRevoked.
  ///
  /// In ru, this message translates to:
  /// **'Устройство недоступно или доверие отозвано.'**
  String get peerUnavailableOrRevoked;

  /// No description provided for @cancelRetriesExhausted.
  ///
  /// In ru, this message translates to:
  /// **'Автоматические попытки закончились. Отмена ещё не подтверждена; приложение уточнит результат, когда получатель снова будет доступен.'**
  String get cancelRetriesExhausted;

  /// No description provided for @connectionLostAutoResume.
  ///
  /// In ru, this message translates to:
  /// **'Связь прервалась. Подтверждённый прогресс сохранён; передача продолжится автоматически, когда второе устройство снова будет в сети.'**
  String get connectionLostAutoResume;

  /// No description provided for @connectionNotRestored.
  ///
  /// In ru, this message translates to:
  /// **'Связь не восстановилась. Подтверждённый прогресс сохранён. Откройте приложение на обоих устройствах и нажмите «Продолжить».'**
  String get connectionNotRestored;

  /// No description provided for @cancelRetrying.
  ///
  /// In ru, this message translates to:
  /// **'Уточняем отмену: повтор {attempt} из {max} через {seconds} с. Результат получателя пока неизвестен.'**
  String cancelRetrying(int attempt, int max, String seconds);

  /// No description provided for @connectionRetrying.
  ///
  /// In ru, this message translates to:
  /// **'Связь прервалась. Повтор {attempt} из {max} через {seconds} с. Подтверждённый прогресс сохранён.'**
  String connectionRetrying(int attempt, int max, String seconds);

  /// No description provided for @senderPausedTapResume.
  ///
  /// In ru, this message translates to:
  /// **'Пауза отправителя. Для продолжения нажмите «Продолжить».'**
  String get senderPausedTapResume;

  /// No description provided for @recipientPaused.
  ///
  /// In ru, this message translates to:
  /// **'Получатель поставил передачу на паузу.'**
  String get recipientPaused;

  /// No description provided for @consentExpiredNewRequest.
  ///
  /// In ru, this message translates to:
  /// **'Время ожидания согласия истекло. Для передачи нужен новый запрос.'**
  String get consentExpiredNewRequest;

  /// No description provided for @receiveNotFinished.
  ///
  /// In ru, this message translates to:
  /// **'Приём не завершён. Выберите файлы заново для новой отправки.'**
  String get receiveNotFinished;

  /// No description provided for @partiallySaved.
  ///
  /// In ru, this message translates to:
  /// **'Сохранено {completed} из {total} файлов. Завершённые результаты доступны у получателя; остальные можно отправить заново.'**
  String partiallySaved(int completed, int total);

  /// No description provided for @newRequestFromCopies.
  ///
  /// In ru, this message translates to:
  /// **'Создан новый запрос из сохранённых копий. Получатель должен подтвердить его заново.'**
  String get newRequestFromCopies;

  /// No description provided for @senderPaused.
  ///
  /// In ru, this message translates to:
  /// **'Пауза отправителя'**
  String get senderPaused;

  /// No description provided for @receiveAllowed.
  ///
  /// In ru, this message translates to:
  /// **'Приём разрешён. На отправителе нажмите «Продолжить», если передача остановлена.'**
  String get receiveAllowed;

  /// No description provided for @waitCurrentSend.
  ///
  /// In ru, this message translates to:
  /// **'Дождитесь окончания текущей отправки.'**
  String get waitCurrentSend;

  /// No description provided for @confirmingCancel.
  ///
  /// In ru, this message translates to:
  /// **'Уточняем результат отмены у получателя.'**
  String get confirmingCancel;

  /// No description provided for @tapResumeToConfirmCancel.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите «Продолжить», чтобы подтвердить отмену у получателя.'**
  String get tapResumeToConfirmCancel;

  /// No description provided for @recipientUnavailableCancel.
  ///
  /// In ru, this message translates to:
  /// **'Получатель недоступен. Отмена ещё не подтверждена; «Продолжить» повторно уточнит её результат.'**
  String get recipientUnavailableCancel;

  /// No description provided for @confirmPairingWithCode.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердите подключение на другом устройстве. Код этого устройства: {code} — он должен совпасть с кодом в запросе.'**
  String confirmPairingWithCode(String code);

  /// No description provided for @pairedWith.
  ///
  /// In ru, this message translates to:
  /// **'Подключено: {name}. Теперь можно отправлять файлы.'**
  String pairedWith(String name);

  /// No description provided for @pairingApproved.
  ///
  /// In ru, this message translates to:
  /// **'Подключение подтверждено. Ожидается завершение сопряжения.'**
  String get pairingApproved;

  /// No description provided for @pairingDeclined.
  ///
  /// In ru, this message translates to:
  /// **'Запрос подключения отклонён.'**
  String get pairingDeclined;

  /// No description provided for @trustRevokedCancelUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Доверие отозвано. Удалённый результат отмены не подтверждён.'**
  String get trustRevokedCancelUnknown;

  /// No description provided for @trustRevokedStopped.
  ///
  /// In ru, this message translates to:
  /// **'Доверие отозвано. Передача остановлена.'**
  String get trustRevokedStopped;

  /// No description provided for @deviceRenamed.
  ///
  /// In ru, this message translates to:
  /// **'Имя устройства изменено. Подключённые устройства увидят его при следующем подключении.'**
  String get deviceRenamed;

  /// No description provided for @transferDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Передача удалена вместе с её файлами.'**
  String get transferDeleted;

  /// No description provided for @recordDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Запись удалена из истории.'**
  String get recordDeleted;

  /// No description provided for @historyCleared.
  ///
  /// In ru, this message translates to:
  /// **'Удалено записей: {count}. Полученные файлы сохранены.'**
  String historyCleared(int count);

  /// No description provided for @diagnosticsSaved.
  ///
  /// In ru, this message translates to:
  /// **'Журнал диагностики сохранён: {path}'**
  String diagnosticsSaved(String path);

  /// No description provided for @quotaSaved.
  ///
  /// In ru, this message translates to:
  /// **'Лимит временного хранилища сохранён.'**
  String get quotaSaved;

  /// No description provided for @busyCleaningCopies.
  ///
  /// In ru, this message translates to:
  /// **'Очистка неиспользуемых копий'**
  String get busyCleaningCopies;

  /// No description provided for @copiesCleared.
  ///
  /// In ru, this message translates to:
  /// **'Удалено неиспользуемых временных копий: {count}. Полученные файлы сохранены.'**
  String copiesCleared(int count);

  /// No description provided for @busyCleaningIncoming.
  ///
  /// In ru, this message translates to:
  /// **'Очистка незавершённого приёма'**
  String get busyCleaningIncoming;

  /// No description provided for @incomingCleared.
  ///
  /// In ru, this message translates to:
  /// **'Обработано незавершённых передач: {stopped}. Удалено временных файлов: {removed}. Готовые полученные файлы сохранены.'**
  String incomingCleared(int stopped, int removed);

  /// No description provided for @exportNotExported.
  ///
  /// In ru, this message translates to:
  /// **'Получен в хранилище приложения'**
  String get exportNotExported;

  /// No description provided for @exportInProgress.
  ///
  /// In ru, this message translates to:
  /// **'Сохранение копии…'**
  String get exportInProgress;

  /// No description provided for @exportDone.
  ///
  /// In ru, this message translates to:
  /// **'Копия сохранена: {destination}'**
  String exportDone(String destination);

  /// No description provided for @exportCancelledDetail.
  ///
  /// In ru, this message translates to:
  /// **'Последнее сохранение отменено'**
  String get exportCancelledDetail;

  /// No description provided for @exportFileChanged.
  ///
  /// In ru, this message translates to:
  /// **'Файл изменён или перемещён. Сохранение копии остановлено.'**
  String get exportFileChanged;

  /// No description provided for @exportFailedDetail.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить копию. Полученный файл остаётся в приложении.'**
  String get exportFailedDetail;

  /// No description provided for @exportUnknownDetail.
  ///
  /// In ru, this message translates to:
  /// **'Результат сохранения не подтверждён. Проверьте выбранную папку перед повтором.'**
  String get exportUnknownDetail;

  /// No description provided for @exportCancelled.
  ///
  /// In ru, this message translates to:
  /// **'Сохранение копии отменено. Полученный файл остаётся в приложении.'**
  String get exportCancelled;

  /// No description provided for @cannotOpenFile.
  ///
  /// In ru, this message translates to:
  /// **'Файл сохранён, но подходящую программу открыть не удалось. Попробуйте «Поделиться» или «Сохранить копию…».'**
  String get cannotOpenFile;

  /// No description provided for @backgroundedWillResume.
  ///
  /// In ru, this message translates to:
  /// **'Приложение было свёрнуто. Передача продолжится, когда вы вернётесь в приложение.'**
  String get backgroundedWillResume;

  /// No description provided for @interruptedOnClose.
  ///
  /// In ru, this message translates to:
  /// **'Передача остановлена при закрытии приложения. Нажмите «Продолжить» для проверки состояния у получателя.'**
  String get interruptedOnClose;

  /// No description provided for @verifiedAndSaved.
  ///
  /// In ru, this message translates to:
  /// **'Проверено и сохранено'**
  String get verifiedAndSaved;

  /// No description provided for @consentNotReceived.
  ///
  /// In ru, this message translates to:
  /// **'Согласие не получено за 120 секунд. Для передачи нужен новый запрос.'**
  String get consentNotReceived;

  /// No description provided for @partSavedTapResume.
  ///
  /// In ru, this message translates to:
  /// **'{reason} Подтверждённая часть файла сохранена; затем нажмите «Продолжить».'**
  String partSavedTapResume(String reason);

  /// No description provided for @recipientPausedShort.
  ///
  /// In ru, this message translates to:
  /// **'Пауза получателя'**
  String get recipientPausedShort;

  /// No description provided for @consentRequired.
  ///
  /// In ru, this message translates to:
  /// **'Требуется согласие получателя'**
  String get consentRequired;

  /// No description provided for @someFilesUnfinished.
  ///
  /// In ru, this message translates to:
  /// **'Есть незавершённые файлы. Проверенные результаты сохранены.'**
  String get someFilesUnfinished;

  /// No description provided for @receivedFilesMissing.
  ///
  /// In ru, this message translates to:
  /// **'Полученные файлы удалены или перемещены вне приложения.'**
  String get receivedFilesMissing;

  /// No description provided for @errPeerUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Устройство недоступно. Подключите оба устройства к одной сети и откройте приложение.'**
  String get errPeerUnavailable;

  /// No description provided for @errQrExpired.
  ///
  /// In ru, this message translates to:
  /// **'Срок QR-кода истёк. Создайте новый код на другом устройстве.'**
  String get errQrExpired;

  /// No description provided for @errPairingRejected.
  ///
  /// In ru, this message translates to:
  /// **'Подключение отклонено на другом устройстве.'**
  String get errPairingRejected;

  /// No description provided for @errSelfPairing.
  ///
  /// In ru, this message translates to:
  /// **'Этот QR-код принадлежит текущему устройству.'**
  String get errSelfPairing;

  /// No description provided for @errUnauthorized.
  ///
  /// In ru, this message translates to:
  /// **'Доверие отозвано или сопряжение не завершено. Подключите устройства заново.'**
  String get errUnauthorized;

  /// No description provided for @errConsentRequired.
  ///
  /// In ru, this message translates to:
  /// **'Получатель ещё не подтвердил приём. Подтвердите запрос и продолжите отправку.'**
  String get errConsentRequired;

  /// No description provided for @errOfferExpired.
  ///
  /// In ru, this message translates to:
  /// **'Срок предложения истёк. Выберите файлы и отправьте новый запрос.'**
  String get errOfferExpired;

  /// No description provided for @errTransferPaused.
  ///
  /// In ru, this message translates to:
  /// **'Передача приостановлена. Продолжение доступно после снятия паузы обеими сторонами.'**
  String get errTransferPaused;

  /// No description provided for @errHashMismatch.
  ///
  /// In ru, this message translates to:
  /// **'Контрольная сумма не совпала. Файл не отмечен как готовый.'**
  String get errHashMismatch;

  /// No description provided for @errSourceChanged.
  ///
  /// In ru, this message translates to:
  /// **'Исходный файл изменился во время подготовки. Выберите его повторно.'**
  String get errSourceChanged;

  /// No description provided for @errFileTooLarge.
  ///
  /// In ru, this message translates to:
  /// **'Размер файла превышает предел — 10 ГиБ.'**
  String get errFileTooLarge;

  /// No description provided for @errDiskFull.
  ///
  /// In ru, this message translates to:
  /// **'Недостаточно свободного места с учётом начатых передач и резерва. Освободите место в настройках хранилища и повторите.'**
  String get errDiskFull;

  /// No description provided for @errTempQuotaExceeded.
  ///
  /// In ru, this message translates to:
  /// **'Достигнут лимит временных копий. Очистите неиспользуемые копии или увеличьте лимит в настройках.'**
  String get errTempQuotaExceeded;

  /// No description provided for @errQuotaBelowUsage.
  ///
  /// In ru, this message translates to:
  /// **'Этот лимит меньше объёма временных копий и места для начатых передач. Сначала завершите передачи или освободите место.'**
  String get errQuotaBelowUsage;

  /// No description provided for @errCapacityUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось определить доступное место. Повторите проверку в настройках хранилища.'**
  String get errCapacityUnavailable;

  /// No description provided for @errCommittedFileChanged.
  ///
  /// In ru, this message translates to:
  /// **'Полученный файл удалён, перемещён или изменён. Сохранение копии остановлено; проверьте файл.'**
  String get errCommittedFileChanged;

  /// No description provided for @errExportFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить внешнюю копию. Полученный файл остаётся в приложении; выберите другое место или повторите.'**
  String get errExportFailed;

  /// No description provided for @errExportSourceUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Полученный файл недоступен для сохранения копии. Проверьте, что он не удалён или перемещён.'**
  String get errExportSourceUnavailable;

  /// No description provided for @errExportUnsupported.
  ///
  /// In ru, this message translates to:
  /// **'Системное сохранение не поддерживается на этом устройстве. Файл остаётся в приложении.'**
  String get errExportUnsupported;

  /// No description provided for @errExportBusy.
  ///
  /// In ru, this message translates to:
  /// **'Дождитесь завершения текущего сохранения или закройте открытое системное окно.'**
  String get errExportBusy;

  /// No description provided for @errDestinationExists.
  ///
  /// In ru, this message translates to:
  /// **'Файл с таким именем уже существует. Укажите другое имя или папку.'**
  String get errDestinationExists;

  /// No description provided for @errRateLimited.
  ///
  /// In ru, this message translates to:
  /// **'Получатель временно ограничил число запросов. Повторите через несколько минут.'**
  String get errRateLimited;

  /// No description provided for @errQuotaExceeded.
  ///
  /// In ru, this message translates to:
  /// **'Передача больше доступного места на устройстве получателя.'**
  String get errQuotaExceeded;

  /// No description provided for @errJournal.
  ///
  /// In ru, this message translates to:
  /// **'Журнал передач недоступен. Обновите приложение или восстановите журнал.'**
  String get errJournal;

  /// No description provided for @errIdentityChanged.
  ///
  /// In ru, this message translates to:
  /// **'Ключ другого устройства изменился. Удалите его из списка и подключите заново.'**
  String get errIdentityChanged;

  /// No description provided for @errTransferTooSlow.
  ///
  /// In ru, this message translates to:
  /// **'Соединение слишком медленное. Передача приостановлена и будет повторена.'**
  String get errTransferTooSlow;

  /// No description provided for @errFileMissing.
  ///
  /// In ru, this message translates to:
  /// **'Полученный файл удалён или перемещён вне приложения.'**
  String get errFileMissing;

  /// No description provided for @errTransferActive.
  ///
  /// In ru, this message translates to:
  /// **'Завершите или отмените передачу, прежде чем удалять её.'**
  String get errTransferActive;

  /// No description provided for @errQueueFull.
  ///
  /// In ru, this message translates to:
  /// **'Очередь заполнена. Завершите или отмените незавершённые передачи.'**
  String get errQueueFull;

  /// No description provided for @errBusy.
  ///
  /// In ru, this message translates to:
  /// **'Получатель занят другой передачей. Повторите позже.'**
  String get errBusy;

  /// No description provided for @errNotFound.
  ///
  /// In ru, this message translates to:
  /// **'Данные этой передачи недоступны. Проверьте сохранённые файлы или выберите источник заново.'**
  String get errNotFound;

  /// No description provided for @errHandshake.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось проверить ключ устройства. Перепроверьте устройство и выполните сопряжение заново.'**
  String get errHandshake;

  /// No description provided for @errConnectionLost.
  ///
  /// In ru, this message translates to:
  /// **'Соединение прервано. Откройте приложение на обоих устройствах и продолжите передачу.'**
  String get errConnectionLost;

  /// No description provided for @errFormat.
  ///
  /// In ru, this message translates to:
  /// **'Некорректный QR-код или неподдерживаемый формат данных.'**
  String get errFormat;

  /// No description provided for @errFileSystem.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось прочитать или сохранить файл. Проверьте доступ и свободное место.'**
  String get errFileSystem;

  /// No description provided for @errUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Что-то пошло не так. Повторите действие. Если ошибка повторяется, отправьте журнал диагностики из настроек.'**
  String get errUnknown;

  /// No description provided for @errWithCode.
  ///
  /// In ru, this message translates to:
  /// **'Операция остановлена (код {code}). Данные не отмечены как успешно переданные.'**
  String errWithCode(String code);

  /// No description provided for @statusDeviceKeysReset.
  ///
  /// In ru, this message translates to:
  /// **'Ключи устройства сброшены. Подключите свои устройства заново по QR-коду.'**
  String get statusDeviceKeysReset;

  /// No description provided for @statusReceivedDone.
  ///
  /// In ru, this message translates to:
  /// **'Файлы получены: {title}'**
  String statusReceivedDone(String title);

  /// No description provided for @statusSentDone.
  ///
  /// In ru, this message translates to:
  /// **'Доставлено: {title}'**
  String statusSentDone(String title);

  /// No description provided for @etaLeft.
  ///
  /// In ru, this message translates to:
  /// **'осталось {value}'**
  String etaLeft(String value);

  /// No description provided for @messageSent.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение отправлено. Получатель подтвердит его на своём устройстве.'**
  String get messageSent;

  /// No description provided for @errMessageTooLong.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение слишком длинное (до 64 КБ). Отправьте его файлом.'**
  String get errMessageTooLong;

  /// No description provided for @journalWarningText.
  ///
  /// In ru, this message translates to:
  /// **'Часть записей истории не удалось прочитать. Подготовленные копии сохранены и не будут предложены к очистке.'**
  String get journalWarningText;

  /// No description provided for @preparationCancelled.
  ///
  /// In ru, this message translates to:
  /// **'Подготовка остановлена. Уже подготовленные файлы остались в списке.'**
  String get preparationCancelled;

  /// No description provided for @errUrlUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть ссылку. Проверьте, что установлен браузер.'**
  String get errUrlUnavailable;

  /// No description provided for @browserPeer.
  ///
  /// In ru, this message translates to:
  /// **'Браузер'**
  String get browserPeer;

  /// No description provided for @webUploadDetail.
  ///
  /// In ru, this message translates to:
  /// **'Загружено из браузера по ссылке Ulash'**
  String get webUploadDetail;

  /// No description provided for @webPageTitle.
  ///
  /// In ru, this message translates to:
  /// **'Файлы с устройства'**
  String get webPageTitle;

  /// No description provided for @webPageDownload.
  ///
  /// In ru, this message translates to:
  /// **'Скачать'**
  String get webPageDownload;

  /// No description provided for @webPageNoFiles.
  ///
  /// In ru, this message translates to:
  /// **'Файлы для скачивания не выбраны.'**
  String get webPageNoFiles;

  /// No description provided for @webPageUpload.
  ///
  /// In ru, this message translates to:
  /// **'Отправить на устройство'**
  String get webPageUpload;

  /// No description provided for @webPageChoose.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать файлы'**
  String get webPageChoose;

  /// No description provided for @webPageWaiting.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердите приём на устройстве…'**
  String get webPageWaiting;

  /// No description provided for @webPageUploading.
  ///
  /// In ru, this message translates to:
  /// **'Отправка'**
  String get webPageUploading;

  /// No description provided for @webPageDone.
  ///
  /// In ru, this message translates to:
  /// **'Готово: файлы на устройстве.'**
  String get webPageDone;

  /// No description provided for @webPageRejected.
  ///
  /// In ru, this message translates to:
  /// **'Приём отклонён на устройстве.'**
  String get webPageRejected;

  /// No description provided for @webPageFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отправить. Попробуйте ещё раз.'**
  String get webPageFailed;

  /// No description provided for @webPageExpires.
  ///
  /// In ru, this message translates to:
  /// **'Ссылка действует до'**
  String get webPageExpires;

  /// No description provided for @unknownDevice.
  ///
  /// In ru, this message translates to:
  /// **'Устройство'**
  String get unknownDevice;

  /// No description provided for @pairingCancelled.
  ///
  /// In ru, this message translates to:
  /// **'Подключение отменено'**
  String get pairingCancelled;

  /// No description provided for @peerBusyRetrying.
  ///
  /// In ru, this message translates to:
  /// **'Получатель занят. Повтор через {seconds} с.'**
  String peerBusyRetrying(int seconds);

  /// No description provided for @errFoldersUnsupported.
  ///
  /// In ru, this message translates to:
  /// **'На другом устройстве старая версия Ulash — она не принимает папки. Обновите приложение там или выберите отдельные файлы.'**
  String get errFoldersUnsupported;

  /// No description provided for @errFolderTooLarge.
  ///
  /// In ru, this message translates to:
  /// **'В папке больше 1000 файлов. Выберите папку поменьше.'**
  String get errFolderTooLarge;

  /// No description provided for @errFolderPath.
  ///
  /// In ru, this message translates to:
  /// **'Папка слишком глубокая или содержит недопустимые имена. Выберите вложенную папку или отдельные файлы.'**
  String get errFolderPath;

  /// No description provided for @errFolderEmpty.
  ///
  /// In ru, this message translates to:
  /// **'В выбранной папке нет файлов.'**
  String get errFolderEmpty;

  /// No description provided for @errNearbyUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Устройство больше не ждёт подключения. Попросите снова открыть на нём экран подключения.'**
  String get errNearbyUnavailable;

  /// No description provided for @errPhotosDenied.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа к «Фото». Разрешите добавление в настройках.'**
  String get errPhotosDenied;

  /// No description provided for @errPhotosFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить в «Фото». Файл остался в Ulash.'**
  String get errPhotosFailed;

  /// No description provided for @savedToPhotos.
  ///
  /// In ru, this message translates to:
  /// **'Сохранено в «Фото»'**
  String get savedToPhotos;

  /// No description provided for @errOpenBlocked.
  ///
  /// In ru, this message translates to:
  /// **'Это программа или скрипт — Ulash не запускает такие файлы. Откройте папку и запустите файл сами, если доверяете отправителю.'**
  String get errOpenBlocked;

  /// No description provided for @saveLocationFiles.
  ///
  /// In ru, this message translates to:
  /// **'Приложение «Файлы» → На iPhone → Ulash'**
  String get saveLocationFiles;

  /// No description provided for @intakeAdded.
  ///
  /// In ru, this message translates to:
  /// **'Добавлено из другого приложения: {count}'**
  String intakeAdded(int count);

  /// No description provided for @errTooManyFiles.
  ///
  /// In ru, this message translates to:
  /// **'За один раз можно отправить до 1000 файлов. Уберите часть из списка.'**
  String get errTooManyFiles;

  /// No description provided for @pairingConnectingTo.
  ///
  /// In ru, this message translates to:
  /// **'Связываемся с «{name}». Код появится через секунду.'**
  String pairingConnectingTo(String name);

  /// No description provided for @legacyCodesNote.
  ///
  /// In ru, this message translates to:
  /// **'На другом устройстве старая версия Ulash, поэтому сравниваются коды устройств (вида ABCD-1234). Лучше обновите Ulash там.'**
  String get legacyCodesNote;

  /// No description provided for @errUpgradeRequired.
  ///
  /// In ru, this message translates to:
  /// **'Обновите Ulash на другом устройстве: эта версия не может подключиться к нему без QR-кода.'**
  String get errUpgradeRequired;

  /// No description provided for @errCommitmentMismatch.
  ///
  /// In ru, this message translates to:
  /// **'Подключение не удалось: проверка кода не прошла, возможно, соединение перехвачено. Попробуйте ещё раз с новым кодом.'**
  String get errCommitmentMismatch;

  /// No description provided for @moreActions.
  ///
  /// In ru, this message translates to:
  /// **'Ещё'**
  String get moreActions;

  /// No description provided for @copyAction.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать'**
  String get copyAction;

  /// No description provided for @textCopied.
  ///
  /// In ru, this message translates to:
  /// **'Скопировано'**
  String get textCopied;

  /// No description provided for @sendLead.
  ///
  /// In ru, this message translates to:
  /// **'Фото, видео и документы — в исходном качестве, напрямую по Wi-Fi.'**
  String get sendLead;

  /// No description provided for @folder.
  ///
  /// In ru, this message translates to:
  /// **'Папка'**
  String get folder;

  /// No description provided for @textMessage.
  ///
  /// In ru, this message translates to:
  /// **'Текст'**
  String get textMessage;

  /// No description provided for @addMore.
  ///
  /// In ru, this message translates to:
  /// **'Добавить ещё'**
  String get addMore;

  /// No description provided for @sendTo.
  ///
  /// In ru, this message translates to:
  /// **'Кому'**
  String get sendTo;

  /// No description provided for @sendToDevice.
  ///
  /// In ru, this message translates to:
  /// **'Отправить на «{name}»'**
  String sendToDevice(String name);

  /// No description provided for @addFilesFirst.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте файлы'**
  String get addFilesFirst;

  /// No description provided for @noAppLink.
  ///
  /// In ru, this message translates to:
  /// **'Нет Ulash на другом устройстве? Отправьте по ссылке'**
  String get noAppLink;

  /// No description provided for @firstDeviceTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключите первое устройство'**
  String get firstDeviceTitle;

  /// No description provided for @firstDeviceBody.
  ///
  /// In ru, this message translates to:
  /// **'Откройте Ulash на втором устройстве в той же сети Wi-Fi и отсканируйте QR-код. Это нужно сделать один раз.'**
  String get firstDeviceBody;

  /// No description provided for @activeTransfers.
  ///
  /// In ru, this message translates to:
  /// **'Сейчас передаются'**
  String get activeTransfers;

  /// No description provided for @messageTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение'**
  String get messageTitle;

  /// No description provided for @messageHint.
  ///
  /// In ru, this message translates to:
  /// **'Текст или ссылка'**
  String get messageHint;

  /// No description provided for @chooseRecipientFirst.
  ///
  /// In ru, this message translates to:
  /// **'Сначала выберите получателя.'**
  String get chooseRecipientFirst;

  /// No description provided for @selectedSummary.
  ///
  /// In ru, this message translates to:
  /// **'{files} · {size}'**
  String selectedSummary(String files, String size);

  /// No description provided for @searchHint.
  ///
  /// In ru, this message translates to:
  /// **'Поиск по названию или устройству'**
  String get searchHint;

  /// No description provided for @today.
  ///
  /// In ru, this message translates to:
  /// **'Сегодня'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In ru, this message translates to:
  /// **'Вчера'**
  String get yesterday;

  /// No description provided for @nothingFound.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get nothingFound;

  /// No description provided for @saveToPhotos.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить в «Фото»'**
  String get saveToPhotos;

  /// No description provided for @revealInFolder.
  ///
  /// In ru, this message translates to:
  /// **'Показать в папке'**
  String get revealInFolder;

  /// No description provided for @executableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Открыть программу?'**
  String get executableTitle;

  /// No description provided for @executableBody.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» может запустить программу на этом устройстве. Открывайте такие файлы, только если доверяете отправителю.'**
  String executableBody(String name);

  /// No description provided for @openAnyway.
  ///
  /// In ru, this message translates to:
  /// **'Всё равно открыть'**
  String get openAnyway;

  /// No description provided for @folderLabel.
  ///
  /// In ru, this message translates to:
  /// **'Папка «{name}»'**
  String folderLabel(String name);

  /// No description provided for @receiveFiles.
  ///
  /// In ru, this message translates to:
  /// **'Принимать файлы'**
  String get receiveFiles;

  /// No description provided for @receiveHintOn.
  ///
  /// In ru, this message translates to:
  /// **'Ваши устройства могут отправлять сюда файлы — каждую передачу вы подтверждаете сами.'**
  String get receiveHintOn;

  /// No description provided for @receiveHintOff.
  ///
  /// In ru, this message translates to:
  /// **'Приём выключен: это устройство не видно другим.'**
  String get receiveHintOff;

  /// No description provided for @deviceCode.
  ///
  /// In ru, this message translates to:
  /// **'Код устройства'**
  String get deviceCode;

  /// No description provided for @showQr.
  ///
  /// In ru, this message translates to:
  /// **'Показать QR'**
  String get showQr;

  /// No description provided for @noCameraEnterCode.
  ///
  /// In ru, this message translates to:
  /// **'Нет камеры? Ввести код'**
  String get noCameraEnterCode;

  /// No description provided for @connectFooter.
  ///
  /// In ru, this message translates to:
  /// **'Откройте Ulash на другом устройстве в той же сети Wi-Fi. Подключение нужно один раз.'**
  String get connectFooter;

  /// No description provided for @nearby.
  ///
  /// In ru, this message translates to:
  /// **'Рядом'**
  String get nearby;

  /// No description provided for @nearbyFooter.
  ///
  /// In ru, this message translates to:
  /// **'Устройства в этой сети, на которых сейчас открыт экран подключения.'**
  String get nearbyFooter;

  /// No description provided for @waitingRequests.
  ///
  /// In ru, this message translates to:
  /// **'Запросы на подключение'**
  String get waitingRequests;

  /// No description provided for @qrHint.
  ///
  /// In ru, this message translates to:
  /// **'На другом устройстве откройте Ulash → «Устройства» → «Сканировать QR».'**
  String get qrHint;

  /// No description provided for @qrNearbyVisible.
  ///
  /// In ru, this message translates to:
  /// **'Пока открыт этот экран, устройство видно рядом и его можно подключить без QR.'**
  String get qrNearbyVisible;

  /// No description provided for @codesMatchTitle.
  ///
  /// In ru, this message translates to:
  /// **'Коды совпадают?'**
  String get codesMatchTitle;

  /// No description provided for @sasHostBody.
  ///
  /// In ru, this message translates to:
  /// **'Сравните с кодом на экране «{name}». Подключайте, только если коды одинаковые.'**
  String sasHostBody(String name);

  /// No description provided for @sasJoinerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердите на другом устройстве'**
  String get sasJoinerTitle;

  /// No description provided for @sasJoinerBody.
  ///
  /// In ru, this message translates to:
  /// **'На «{name}» должен быть показан этот же код. Нажмите там «Подключить».'**
  String sasJoinerBody(String name);

  /// No description provided for @codesMatch.
  ///
  /// In ru, this message translates to:
  /// **'Да, подключить'**
  String get codesMatch;

  /// No description provided for @codesDiffer.
  ///
  /// In ru, this message translates to:
  /// **'Коды разные'**
  String get codesDiffer;

  /// No description provided for @webShareEntry.
  ///
  /// In ru, this message translates to:
  /// **'По ссылке'**
  String get webShareEntry;

  /// No description provided for @webShareTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отправить по ссылке'**
  String get webShareTitle;

  /// No description provided for @webShareBody.
  ///
  /// In ru, this message translates to:
  /// **'Откройте ссылку в браузере на устройстве в этой же сети Wi-Fi — например, на компьютере без Ulash.'**
  String get webShareBody;

  /// No description provided for @webShareInsecure.
  ///
  /// In ru, this message translates to:
  /// **'Ссылка работает без шифрования (HTTP). Пользуйтесь ей только в своей сети и остановите её после передачи.'**
  String get webShareInsecure;

  /// No description provided for @webShareAllowUpload.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить загрузку файлов на это устройство'**
  String get webShareAllowUpload;

  /// No description provided for @webShareValid.
  ///
  /// In ru, this message translates to:
  /// **'Ссылка действует до {time}'**
  String webShareValid(String time);

  /// No description provided for @webShareStats.
  ///
  /// In ru, this message translates to:
  /// **'Открыли: {clients} · скачано: {downloads} · загружено: {uploads}'**
  String webShareStats(int clients, int downloads, int uploads);

  /// No description provided for @webShareCreate.
  ///
  /// In ru, this message translates to:
  /// **'Создать ссылку'**
  String get webShareCreate;

  /// No description provided for @webShareStop.
  ///
  /// In ru, this message translates to:
  /// **'Остановить'**
  String get webShareStop;

  /// No description provided for @copyLink.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать ссылку'**
  String get copyLink;

  /// No description provided for @webShareSelectFirst.
  ///
  /// In ru, this message translates to:
  /// **'Ссылка отдаёт выбранные файлы. Выберите файлы или разрешите загрузку.'**
  String get webShareSelectFirst;

  /// No description provided for @webShareQrSemantics.
  ///
  /// In ru, this message translates to:
  /// **'QR-код ссылки для браузера'**
  String get webShareQrSemantics;

  /// No description provided for @receiving.
  ///
  /// In ru, this message translates to:
  /// **'Получение'**
  String get receiving;

  /// No description provided for @autoSaveToPhotos.
  ///
  /// In ru, this message translates to:
  /// **'Сохранять фото и видео в «Фото»'**
  String get autoSaveToPhotos;

  /// No description provided for @autoSaveHint.
  ///
  /// In ru, this message translates to:
  /// **'Полученные снимки и видео сразу появятся в галерее.'**
  String get autoSaveHint;

  /// No description provided for @theme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get theme;

  /// No description provided for @support.
  ///
  /// In ru, this message translates to:
  /// **'Поддержка'**
  String get support;

  /// No description provided for @privacyPolicy.
  ///
  /// In ru, this message translates to:
  /// **'Политика конфиденциальности'**
  String get privacyPolicy;

  /// No description provided for @howDataHandled.
  ///
  /// In ru, this message translates to:
  /// **'Как обрабатываются данные'**
  String get howDataHandled;

  /// No description provided for @advanced.
  ///
  /// In ru, this message translates to:
  /// **'Дополнительно'**
  String get advanced;

  /// No description provided for @advancedHint.
  ///
  /// In ru, this message translates to:
  /// **'Хранилище, диагностика, сброс ключей'**
  String get advancedHint;

  /// No description provided for @about.
  ///
  /// In ru, this message translates to:
  /// **'О приложении'**
  String get about;

  /// No description provided for @dangerZone.
  ///
  /// In ru, this message translates to:
  /// **'Безопасность'**
  String get dangerZone;

  /// No description provided for @onbAllowTitle.
  ///
  /// In ru, this message translates to:
  /// **'Разрешите доступ к сети'**
  String get onbAllowTitle;

  /// No description provided for @onbAllowBody.
  ///
  /// In ru, this message translates to:
  /// **'Ulash ищет ваши устройства только в вашей сети Wi-Fi. Без этого разрешения устройства не найдут друг друга.'**
  String get onbAllowBody;

  /// No description provided for @allowAccess.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить доступ'**
  String get allowAccess;

  /// No description provided for @webUploadTitle.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка из браузера'**
  String get webUploadTitle;

  /// No description provided for @webUploadBody.
  ///
  /// In ru, this message translates to:
  /// **'{client} хочет загрузить сюда {files} ({size}).'**
  String webUploadBody(String client, String files, String size);

  /// No description provided for @allow.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить'**
  String get allow;

  /// No description provided for @waitingForApprovalOn.
  ///
  /// In ru, this message translates to:
  /// **'Ждём подтверждения на «{name}»'**
  String waitingForApprovalOn(String name);

  /// No description provided for @connectedTo.
  ///
  /// In ru, this message translates to:
  /// **'Подключено к «{name}»'**
  String connectedTo(String name);

  /// No description provided for @shareSheetLink.
  ///
  /// In ru, this message translates to:
  /// **'Ссылка'**
  String get shareSheetLink;

  /// No description provided for @nearbyEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Рядом пока никого. Откройте на другом устройстве «Устройства» → «Показать QR».'**
  String get nearbyEmpty;

  /// No description provided for @noDevicesYet.
  ///
  /// In ru, this message translates to:
  /// **'Пока нет подключённых устройств'**
  String get noDevicesYet;

  /// No description provided for @filterText.
  ///
  /// In ru, this message translates to:
  /// **'Текст'**
  String get filterText;

  /// No description provided for @saveDestination.
  ///
  /// In ru, this message translates to:
  /// **'Куда сохранять'**
  String get saveDestination;

  /// No description provided for @largeTextSample.
  ///
  /// In ru, this message translates to:
  /// **'Размер текста меняется в настройках устройства.'**
  String get largeTextSample;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru', 'uz'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'uz':
      return AppLocalizationsUz();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
