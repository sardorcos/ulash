// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get unitB => 'B';

  @override
  String get unitKiB => 'KB';

  @override
  String get unitMiB => 'MB';

  @override
  String get unitGiB => 'GB';

  @override
  String get unitTiB => 'TB';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta fayl',
      one: '$count ta fayl',
    );
    return '$_temp0';
  }

  @override
  String get platformUnknown => 'Qurilma';

  @override
  String get phasePreparing => 'Fayllar tayyorlanmoqda';

  @override
  String get phaseQueued => 'Navbatda';

  @override
  String get phaseRetrying => 'Qayta ulanmoqda';

  @override
  String get phaseWaitingForConsent => 'Tasdiq kutilmoqda';

  @override
  String get phaseTransferring => 'Fayllar uzatilmoqda';

  @override
  String get phaseVerifying => 'Fayl tekshirilmoqda';

  @override
  String get phaseCompleted => 'Uzatish yakunlandi';

  @override
  String get phasePaused => 'Uzatish toʻxtatildi';

  @override
  String get phaseFailed => 'Yakunlab boʻlmadi';

  @override
  String get phaseCancelled => 'Uzatish bekor qilindi';

  @override
  String get phaseExpired => 'Kutish vaqti tugadi';

  @override
  String get networkStarting => 'Ulanmoqda…';

  @override
  String get networkReady => 'Mahalliy tarmoq';

  @override
  String get networkUnavailable => 'Ulanish yoʻq';

  @override
  String get networkPermissionRequired => 'Tarmoqqa ruxsat kerak';

  @override
  String speedPerSecond(String value) {
    return '$value / s';
  }

  @override
  String get navSend => 'Yuborish';

  @override
  String get navReceive => 'Qabul qilish';

  @override
  String get navDevices => 'Qurilmalar';

  @override
  String get navHistory => 'Tarix';

  @override
  String get navSettings => 'Sozlamalar';

  @override
  String get actionFailedRetry =>
      'Amalni bajarib boʻlmadi. Yana urinib koʻring.';

  @override
  String get localNetworkNotice =>
      'Mahalliy tarmoqqa ruxsat yoʻq. Sozlamalar → Ulash boʻlimida «Mahalliy tarmoq»ni yoqing, soʻng «Qayta urinish»ni bosing.';

  @override
  String get openSettingsShort => 'Sozlamalar';

  @override
  String get retry => 'Qayta urinish';

  @override
  String get incomingWaitingNotice =>
      'Kiruvchi fayllar tasdigʻingizni kutmoqda';

  @override
  String get view => 'Koʻrish';

  @override
  String get pairingWaitingNotice => 'Yangi qurilma ulanishni soʻramoqda';

  @override
  String get check => 'Tekshirish';

  @override
  String get sidebarTagline => 'Qurilmalaringiz\norasida';

  @override
  String get sidebarTaglineDetail =>
      'Fayllar mahalliy\ntarmoq orqali uzatiladi.';

  @override
  String get sendEyebrow => 'MAHALLIY UZATISH';

  @override
  String get sendTitle => 'Fayllar — kerakli\nqurilmada.';

  @override
  String get sendSubtitle =>
      'Nima va kimga yuborishni tanlang. Rasm, video va hujjatlar asl sifatida qoladi.';

  @override
  String get recipientStep => '2. Qabul qiluvchi';

  @override
  String get recipientSubtitle => 'Mavjud ishonchli qurilmalar';

  @override
  String get refreshDevices => 'Qurilmalarni yangilash';

  @override
  String get connectDeviceTitle => 'Qurilmani ulang';

  @override
  String get connectDeviceHint =>
      'Ikkinchi qurilmada ilovani oching va uni taklifnoma orqali qoʻshing.';

  @override
  String get connect => 'Ulash';

  @override
  String get chooseRecipient => 'Qabul qiluvchini tanlang';

  @override
  String get sendFiles => 'Fayllarni yuborish';

  @override
  String get recipientWillConfirm =>
      'Qabul qiluvchi uzatishni oʻz qurilmasida tasdiqlaydi.';

  @override
  String get currentTransfers => 'Joriy uzatishlar';

  @override
  String get foldersUnsupported =>
      'Alohida fayllarni tanlang. Jildlar hozircha qoʻllab-quvvatlanmaydi.';

  @override
  String get dropFilesHere => 'Fayllarni shu yerga tashlang';

  @override
  String get filesStep => '1. Fayllar';

  @override
  String get whatToSend => 'Nimani yubormoqchisiz?';

  @override
  String get clearSelectedFiles => 'Tanlangan fayllarni tozalash';

  @override
  String get startWithFiles => 'Fayllardan boshlaymiz';

  @override
  String get startWithFilesHint =>
      'Telefondagi rasm, ish hujjati\nyoki butun video — tanlang.';

  @override
  String get photosAndVideos => 'Rasm va video';

  @override
  String get files => 'Fayllar';

  @override
  String get chooseFiles => 'Fayllarni tanlash';

  @override
  String get orDropHere => 'yoki ularni shu yerga sudrab olib keling';

  @override
  String get preparingFile => 'Fayl tayyorlanmoqda…';

  @override
  String get preparationFailed => 'Tayyorlab boʻlmadi';

  @override
  String get sizePending => 'Hajmi aniqlanmoqda';

  @override
  String removeSource(String name) {
    return '$name ni olib tashlash';
  }

  @override
  String get add => 'Qoʻshish';

  @override
  String totalSize(String size) {
    return 'Jami: $size';
  }

  @override
  String get receiveEyebrow => 'QABUL QILISH';

  @override
  String get receiveTitle => 'Fayllaringiz\nshu yerda paydo boʻladi.';

  @override
  String get receiveSubtitle =>
      'Ilovani ochiq qoldiring. Ulangandan soʻng yuboruvchi qurilmani koʻradi.';

  @override
  String get receivingOn => 'Qabul qilish yoqilgan';

  @override
  String get receivingOff => 'Qabul qilish oʻchirilgan';

  @override
  String saveLocation(String location) {
    return 'Saqlash joyi: $location';
  }

  @override
  String get showInvitation => 'Taklifnomani koʻrsatish';

  @override
  String get myDevices => 'Mening qurilmalarim';

  @override
  String get noIncomingTitle => 'Hozircha kiruvchi takliflar yoʻq';

  @override
  String get noIncomingReady =>
      'Yuboruvchi ushbu qurilmani tanlaganda fayllarni koʻrib, uzatishni qabul qilishingiz mumkin.';

  @override
  String get noIncomingOff =>
      'Fayllarni qabul qilishga tayyor boʻlganingizda qabul qilishni yoqing.';

  @override
  String get incomingOffers => 'Kiruvchi takliflar';

  @override
  String andMoreFiles(String files) {
    return 'Yana $files';
  }

  @override
  String offerValidUntil(String time) {
    return 'Taklif $time gacha amal qiladi. Javob boʻlmasa, yuboruvchi yangi taklif yaratishi kerak boʻladi.';
  }

  @override
  String get acceptFiles => 'Fayllarni qabul qilish';

  @override
  String get decline => 'Rad etish';

  @override
  String get devicesEyebrow => 'QURILMALARINGIZ';

  @override
  String get devicesTitle => 'Bir marta ulang.\nKeyin — oson.';

  @override
  String get devicesSubtitle =>
      'Fayllarni qayta sozlamasdan yuborish uchun telefon yoki kompyuter qoʻshing.';

  @override
  String get connectDevice => 'Qurilmani ulash';

  @override
  String get appOpenBothSides =>
      'Ilova ikkala qurilmada ham ochiq boʻlishi kerak.';

  @override
  String get createInvitation => 'Taklifnoma yaratish';

  @override
  String get enterInvitation => 'Taklifnomani kiritish';

  @override
  String get scanInvitationTooltip =>
      'Boshqa qurilmadagi taklifnomani skanerlash';

  @override
  String get cameraUnavailableTooltip =>
      'Kamera mavjud emas. Taklifnoma matnidan foydalaning.';

  @override
  String get scanQr => 'QR skanerlash';

  @override
  String deviceCodeHint(String code) {
    return 'Ushbu qurilma kodi: $code. Ulanishda u boshqa qurilmadagi soʻrovdagi kod bilan mos kelishi kerak.';
  }

  @override
  String get pairingRequest => 'Ulanish soʻrovi';

  @override
  String get pairingConfirmGeneric =>
      'Agar hozirgina ushbu qurilmani qoʻshgan boʻlsangiz, tasdiqlang.';

  @override
  String pairingConfirmCode(String code) {
    return 'Faqat $code kodi ulanayotgan qurilmadagi kod bilan mos kelsa, tasdiqlang.';
  }

  @override
  String get connectedDevices => 'Ulangan qurilmalar';

  @override
  String get availabilityChecked => 'Mavjudlikni ilova tekshiradi';

  @override
  String get onlyThisDeviceTitle => 'Hozircha faqat shu qurilma';

  @override
  String get onlyThisDeviceHint =>
      'Taklifnoma yarating yoki ikkinchi qurilmadagi taklifnomani kiriting. Tasdiqlangandan soʻng u shu yerda paydo boʻladi.';

  @override
  String disconnectDevice(String name) {
    return '$name ni uzish';
  }

  @override
  String get peerAvailable => 'Mavjud';

  @override
  String get peerOffline => 'Tarmoqda emas';

  @override
  String get trustedDevice => 'Ishonchli qurilma';

  @override
  String get historyEyebrow => 'TARIX';

  @override
  String get historyTitle => 'Barcha uzatilganlar.\nBir joyda.';

  @override
  String get historySubtitle =>
      'Holat, qabul qiluvchi va saqlangan fayllar. Tugallanmagan uzatishlar ham shu yerda qoladi.';

  @override
  String get filterAll => 'Hammasi';

  @override
  String get filterSent => 'Yuborilganlar';

  @override
  String get filterReceived => 'Qabul qilinganlar';

  @override
  String get clearHistory => 'Tarixni tozalash';

  @override
  String get historyEmptyTitle => 'Tarix hozircha boʻsh';

  @override
  String get historyFilteredEmptyTitle => 'Bunday uzatishlar hozircha yoʻq';

  @override
  String get historyEmptyHint =>
      'Birinchi uzatishdan soʻng natija shu yerda paydo boʻladi.';

  @override
  String get historyFilteredEmptyHint =>
      'Boshqa filtrni tanlang yoki yangi uzatishni boshlang.';

  @override
  String showMore(int count) {
    return 'Yana koʻrsatish ($count)';
  }

  @override
  String get clearHistoryQuestion => 'Tarix tozalansinmi?';

  @override
  String get clearHistoryBody =>
      'Yakunlangan, bekor qilingan va muvaffaqiyatsiz uzatishlar yozuvlari hamda ularning ishlatilmayotgan tayyorlangan nusxalari oʻchiriladi. Qabul qilingan fayllar qoladi — ularni alohida oʻchirish mumkin.';

  @override
  String get cancel => 'Bekor qilish';

  @override
  String get clear => 'Tozalash';

  @override
  String get deleteReceivedQuestion => 'Qabul qilingan fayllar oʻchirilsinmi?';

  @override
  String get deleteRecordQuestion => 'Yozuv oʻchirilsinmi?';

  @override
  String deleteReceivedBody(String title, String size) {
    return '$title\n\nUzatish va uning fayllari ($size) ushbu qurilmadan oʻchiriladi. Siz allaqachon saqlagan yoki «Ulashish» orqali yuborgan nusxalar qoladi.';
  }

  @override
  String deleteRecordBody(String title) {
    return '$title\n\nYozuv ishlatilmayotgan tayyorlangan nusxalar bilan birga tarixdan oʻchiriladi. Agar asl fayl allaqachon oʻchirilgan boʻlsa, bu nusxa yagona boʻlishi mumkin.';
  }

  @override
  String get delete => 'Oʻchirish';

  @override
  String get shareFile => 'Faylni ulashish';

  @override
  String get close => 'Yopish';

  @override
  String toPeer(String name) {
    return 'Kimga: $name';
  }

  @override
  String fromPeer(String name) {
    return 'Kimdan: $name';
  }

  @override
  String savedAt(String location) {
    return 'Saqlangan: $location';
  }

  @override
  String filesFolder(String location) {
    return 'Fayllar jildi: $location';
  }

  @override
  String previouslySaved(String destination) {
    return 'Avval saqlangan: $destination';
  }

  @override
  String get pause => 'Pauza';

  @override
  String get resume => 'Davom ettirish';

  @override
  String get cancelTransfer => 'Bekor qilish';

  @override
  String get sendAgain => 'Qayta yuborish';

  @override
  String get openFiles => 'Fayllarni ochish';

  @override
  String get openFile => 'Faylni ochish';

  @override
  String get saveFileCopyEllipsis => 'Fayl nusxasini saqlash…';

  @override
  String get saveCopyEllipsis => 'Nusxasini saqlash…';

  @override
  String get share => 'Ulashish';

  @override
  String get settingsEyebrow => 'SOZLAMALAR';

  @override
  String get settingsTitle => 'Aynan siz uchun qulay.';

  @override
  String get settingsSubtitle =>
      'Qurilma nomi, koʻrinish va qabul qilingan fayllar joyi.';

  @override
  String get thisDevice => 'Ushbu qurilma';

  @override
  String get deviceName => 'Qurilma nomi';

  @override
  String deviceNameWithCode(String name, String code) {
    return '$name\nQurilma kodi: $code';
  }

  @override
  String get change => 'Oʻzgartirish';

  @override
  String get receivedFiles => 'Qabul qilingan fayllar';

  @override
  String get appearance => 'Koʻrinish';

  @override
  String get themeSystem => 'Tizimdagidek';

  @override
  String get themeLight => 'Yorugʻ';

  @override
  String get themeDark => 'Qorongʻi';

  @override
  String get language => 'Til';

  @override
  String get languageSystem => 'Tizimdagidek';

  @override
  String get connection => 'Ulanish';

  @override
  String get localNetwork => 'Mahalliy tarmoq';

  @override
  String get trustedDevices => 'Ishonchli qurilmalar';

  @override
  String get trustedDevicesHint =>
      'Har bir yangi qurilma sizning tasdigʻingiz bilan ulanadi.';

  @override
  String get open => 'Ochish';

  @override
  String get privacyAndSupport => 'Maxfiylik va yordam';

  @override
  String get privacy => 'Maxfiylik';

  @override
  String get privacySummary => 'Akkaunt, bulut, reklama va analitikasiz.';

  @override
  String get more => 'Batafsil';

  @override
  String get diagnosticsLog => 'Diagnostika jurnali';

  @override
  String get diagnosticsHint =>
      'Fayl nomlari va manzillarsiz xato kodlari. Faqat siz yuborasiz.';

  @override
  String get send => 'Yuborish';

  @override
  String get resetKeys => 'Qurilma kalitlarini tiklash';

  @override
  String get resetKeysHint =>
      'Barcha qurilmalar uziladi. Ularni QR-kod orqali qayta ulash mumkin.';

  @override
  String get reset => 'Tiklash';

  @override
  String get privacyBody =>
      'Ulash fayllarni mahalliy tarmoqda qurilmalaringiz oʻrtasida bevosita uzatadi. Fayllar serverlarga yuklanmaydi, ilova akkaunt talab qilmaydi, reklama, kuzatuv va analitika yoʻq.\n\nUlanishlar shifrlanadi (TLS) va ulanishda tasdiqlangan qurilma kaliti bilan tekshiriladi. Har bir kiruvchi uzatishni oʻzingiz qabul qilasiz.\n\nKamera faqat QR-kodni skanerlash uchun ishlatiladi. Mahalliy tarmoqqa ruxsat qurilmalaringizni topish uchun kerak. Diagnostika jurnali qurilmada saqlanadi va faqat sizning amalingiz bilan yuboriladi.';

  @override
  String get resetKeysQuestion => 'Qurilma kalitlari tiklansinmi?';

  @override
  String get resetKeysBody =>
      'Yangi kalitlar yaratiladi, barcha ulangan qurilmalar unutiladi. Yana fayl almashish uchun ularni QR-kod orqali qayta ulang. Qabul qilingan fayllar va tarix saqlanib qoladi.';

  @override
  String versionLabel(String version) {
    return 'Ulash $version';
  }

  @override
  String get storage => 'Xotira';

  @override
  String get refreshStorage => 'Joy haqidagi maʼlumotni yangilash';

  @override
  String get storageUnavailable =>
      'Xotira haqida maʼlumot hozircha mavjud emas.';

  @override
  String get freeSpace => 'Boʻsh joy';

  @override
  String get freeSpaceUnknown =>
      'Tizim hajmni xabar qilmadi. Vaqtinchalik nusxalar limiti tekshiruvi ishlaydi.';

  @override
  String freeSpaceChecked(String size, String time) {
    return '$size · $time da tekshirildi';
  }

  @override
  String get temporaryCopies => 'Vaqtinchalik nusxalar';

  @override
  String temporaryUsage(String used, String reserved) {
    return '$used band; $reserved boshlangan uzatishlar uchun ajratilgan.';
  }

  @override
  String get quotaUsageSemantics => 'Vaqtinchalik xotira limitidan foydalanish';

  @override
  String get quotaTitle => 'Vaqtinchalik xotira limiti';

  @override
  String quotaHint(String reserve) {
    return 'Yozishdan oldin $reserve boʻsh joy zaxirasi tekshiriladi. Tayyor qabul qilingan fayllar bu limitga kirmaydi va vaqtinchalik nusxalarni tozalashda oʻchirilmaydi.';
  }

  @override
  String get unusedCopies => 'Ishlatilmayotgan nusxalar';

  @override
  String unusedCopiesSummary(String files, String size) {
    return '$files · $size';
  }

  @override
  String get clearUnusedCopies => 'Ishlatilmayotgan nusxalarni tozalash';

  @override
  String get incompleteIncoming => 'Tugallanmagan qabul';

  @override
  String incompleteSummary(int count, String used, String reserved) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ta uzatish',
      one: '$count ta uzatish',
    );
    return '$_temp0 · $used band; $reserved davom ettirish uchun ajratilgan.';
  }

  @override
  String get incompleteHint =>
      'Tozalash tanlangan kiruvchi uzatishlarni toʻxtatadi va ularning tugallanmagan qismlarini oʻchiradi. Ular uchun yangi yuborish kerak boʻladi. Allaqachon qabul qilingan tayyor fayllar joyida qoladi.';

  @override
  String get clearIncomplete => 'Tugallanmagan qabulni tozalash';

  @override
  String get deleteTemporaryQuestion => 'Vaqtinchalik nusxalar oʻchirilsinmi?';

  @override
  String deleteTemporaryBody(int count, String size) {
    return 'Tanlangan fayllar va tugallanmagan uzatishlar ishlatmayotgan $count tagacha nusxa ($size) oʻchiriladi. Yangi yuborish uchun ularni qayta tanlash kerak boʻladi. Asl va tayyor qabul qilingan fayllar joyida qoladi. Agar asl fayl allaqachon oʻchirilgan boʻlsa, vaqtinchalik nusxa yagona boʻlishi mumkin; tozalangandan soʻng uni ilovadan tiklab boʻlmaydi.';
  }

  @override
  String fileWithSize(String name, String size) {
    return '$name · $size';
  }

  @override
  String andMoreFilesDot(int count) {
    return 'Yana $count ta fayl.';
  }

  @override
  String get keep => 'Qoldirish';

  @override
  String get deleteCopies => 'Nusxalarni oʻchirish';

  @override
  String get stopIncomingQuestion =>
      'Qabul toʻxtatilsin va fayl qismlari oʻchirilsinmi?';

  @override
  String stopIncomingBody(int count, String used, String reserved) {
    return 'Quyidagi uzatishlar toʻxtatiladi: $count. Ularning tugallanmagan qismlari hozir $used joy egallaydi, yana $reserved davom ettirish uchun ajratilgan. Qabul davom etayotgan boʻlsa, hajm oʻzgarishi mumkin. Tozalangandan soʻng bu uzatishlarni davom ettirib boʻlmaydi: yuboruvchi yangilarini yaratishi kerak. Tayyor qabul qilingan fayllar va tarix saqlanadi.';
  }

  @override
  String incompleteItem(
    String title,
    String peer,
    String files,
    String size,
    int completed,
  ) {
    return '$title\n$peer · $files tugallanmagan · $size\nQoladigan tayyor fayllar: $completed';
  }

  @override
  String get stopAndClear => 'Toʻxtatish va tozalash';

  @override
  String get resendQuestion => 'Yangi yuborish yaratilsinmi?';

  @override
  String resendBody(String title, String peer, String size) {
    return '$title\nQabul qiluvchi: $peer\n\nIlova saqlangan tayyorlangan nusxalardan ($size) foydalanadi. Asl fayllarni qayta tanlash shart emas. Qabul qiluvchiga tasdiqlash kerak boʻlgan yangi soʻrov keladi. Avvalgi urinish natijasi tarixda qoladi.';
  }

  @override
  String get sendNewRequest => 'Yangi soʻrov yuborish';

  @override
  String get saveFileCopyTitle => 'Fayl nusxasini saqlash';

  @override
  String get receivedInApp => 'Ilovada qabul qilindi';

  @override
  String get pairByInvitation => 'Taklifnoma orqali ulanish';

  @override
  String get pairByInvitationHint =>
      'Ikkinchi qurilmada taklifnoma yarating va uni bu yerga toʻliq nusxalang.';

  @override
  String get invitationText => 'Taklifnoma matni';

  @override
  String get pairConnect => 'Ulanish';

  @override
  String get renameHint =>
      'Bu nomni boshqa qurilmalar ulanish va uzatishda koʻradi.';

  @override
  String get name => 'Nom';

  @override
  String get save => 'Saqlash';

  @override
  String disconnectQuestion(String name) {
    return '$name uzilsinmi?';
  }

  @override
  String get disconnectBody =>
      'Keyingi uzatish uchun bu qurilmani qayta ulash kerak boʻladi.';

  @override
  String get disconnect => 'Uzish';

  @override
  String get invitationTitle => 'Qurilmaga taklifnoma';

  @override
  String get invitationHint =>
      'QR-kodni boshqa qurilmadagi ilovada skanerlang yoki taklifnoma matnini yuboring.';

  @override
  String get invitationQrSemantics =>
      'Qurilmaga vaqtinchalik taklifnoma QR-kodi';

  @override
  String get invitationExpired =>
      'Taklifnoma muddati tugadi. Yangisini yarating.';

  @override
  String invitationRemaining(String time) {
    return 'Yana $time amal qiladi';
  }

  @override
  String get copied => 'Nusxalandi';

  @override
  String get copyInvitation => 'Taklifnomani nusxalash';

  @override
  String get pairOnlyIfCodeMatches =>
      'Faqat bu kod ulanayotgan qurilma ekranidagi kod bilan mos kelsa, ulang.';

  @override
  String get requestNoLongerActive => 'Soʻrov endi faol emas.';

  @override
  String get incomingFiles => 'Kiruvchi fayllar';

  @override
  String offerSummary(String peer, String files, String size) {
    return '$peer · $files · $size';
  }

  @override
  String filesAndSize(String files, String size) {
    return '$files · $size';
  }

  @override
  String get offerNoLongerActive => 'Taklif endi faol emas.';

  @override
  String get onbTitle1 => 'Qurilmalaringiz orasida fayllar';

  @override
  String get onbBody1 =>
      'Rasm, video va hujjatlarni telefondan kompyuterga va aksincha asl sifatida yuboring — bevosita, bulutsiz va roʻyxatdan oʻtmasdan.';

  @override
  String get onbTitle2 => 'Bitta Wi-Fi tarmogʻi';

  @override
  String get onbBody2 =>
      'Qurilmalar bitta tarmoqda boʻlishi kerak. Tizim mahalliy tarmoqqa ruxsat soʻraydi — usiz ilova qurilmalaringizni topa olmaydi.';

  @override
  String get onbTitle3 => 'Faqat sizning roziligingiz bilan';

  @override
  String get onbBody3 =>
      'Yangi qurilma QR-kod va tasdiq orqali ulanadi, har bir kiruvchi uzatishni esa oʻzingiz qabul qilasiz. Maʼlumotlar shifrlanadi.';

  @override
  String get skip => 'Oʻtkazib yuborish';

  @override
  String onbStep(int current, int total) {
    return '$total dan $current-qadam';
  }

  @override
  String get start => 'Boshlash';

  @override
  String get next => 'Keyingi';

  @override
  String get resetKeysStartupBody =>
      'Yangi kalitlar yaratiladi. Avval ulangan barcha qurilmalarni QR-kod orqali qayta ulash kerak boʻladi. Qabul qilingan fayllar qurilmada qoladi.';

  @override
  String get repairQuestion => 'Jurnal tiklansinmi?';

  @override
  String get repairBody =>
      'Shikastlangan jurnal chetga olinadi va ilova toza holatdan boshlanadi. Bu jurnaldagi uzatishlar tarixi mavjud boʻlmay qoladi. Agar yaqinda ilova versiyasini orqaga qaytargan boʻlsangiz, avval uni yangilagan maʼqul.';

  @override
  String get repair => 'Tiklash';

  @override
  String get startupFailedTitle => 'Ilova ishga tushmadi';

  @override
  String get repairJournal => 'Jurnalni tiklash';

  @override
  String get sendDiagnostics => 'Diagnostika jurnalini yuborish';

  @override
  String get scannerTitle => 'Qurilmani ulash';

  @override
  String get cameraUnavailable =>
      'Kamera mavjud emas. Sozlamalarda ruxsat bering yoki ortga qaytib, ulanish kodini qoʻlda kiriting.';

  @override
  String get openSettings => 'Sozlamalarni ochish';

  @override
  String get scannerHint =>
      'Kamerani boshqa qurilmadagi «Qabul qilish» boʻlimidagi QR-kodga qarating. Ikkala qurilma bitta tarmoqda boʻlishi kerak.';

  @override
  String get busyPreparingStorage => 'Himoyalangan xotira tayyorlanmoqda';

  @override
  String get startupKeysFailed =>
      'Qurilmaning himoyalangan kalitlarini ochib boʻlmadi. Qurilmani qulfdan chiqarib, qayta urinib koʻring. Agar kalitlar yoʻqolgan boʻlsa (masalan, yangi telefonga koʻchirilgandan soʻng), ularni tiklang va qurilmalarni qayta ulang.';

  @override
  String get startupJournalFailed =>
      'Uzatishlar jurnali shikastlangan yoki ilovaning yangiroq versiyasida yaratilgan. Ilovani yangilang yoki jurnalni tiklang.';

  @override
  String startupFailed(String reason) {
    return 'Ilovani ishga tushirib boʻlmadi. $reason';
  }

  @override
  String get allowLocalNetwork =>
      'Ilova sozlamalarida mahalliy tarmoqqa ruxsat bering, soʻng «Yangilash»ni bosing.';

  @override
  String get resetKeysFailed =>
      'Kalitlarni tiklab boʻlmadi. Qurilmani qayta ishga tushirib, yana urinib koʻring.';

  @override
  String get defaultNameIos => 'Mening iPhone’im';

  @override
  String get defaultNameAndroid => 'Mening Android’im';

  @override
  String get defaultNameWindows => 'Mening Windows kompyuterim';

  @override
  String get defaultNameLinux => 'Mening Linux kompyuterim';

  @override
  String get defaultNameOther => 'Mening qurilmam';

  @override
  String get discoveryUnavailable =>
      'Avtomatik qidiruv mavjud emas. Umumiy tarmoqda QR-kod orqali ulaning.';

  @override
  String get saveLocationMobile =>
      'Ilova ichida. Faylni boshqa joyga saqlash uchun tarixdagi «Ulashish» yoki «Nusxasini saqlash…» tugmasidan foydalaning.';

  @override
  String get networkDenied =>
      'Tizim sozlamalarida mahalliy tarmoqqa ruxsat berilmagan.';

  @override
  String get networkNoAddress =>
      'Qurilmalarni bitta Wi-Fi yoki Ethernet tarmogʻiga ulang.';

  @override
  String get networkKeepOpen =>
      'Mahalliy tarmoq · uzatish vaqtida ilovani ikkala qurilmada ochiq tuting';

  @override
  String get peerKeyVerified => 'Qurilma kaliti tekshirildi';

  @override
  String get peerOpenApp => 'Boshqa qurilmada ilovani oching';

  @override
  String get peerScanToConnect => 'Birinchi ulanish uchun QR-kodni skanerlang';

  @override
  String get waitingForRecipient => 'Qabul qiluvchining javobi kutilmoqda';

  @override
  String get busyChoosingMedia => 'Rasm va video tanlanmoqda';

  @override
  String get busyChoosingFiles => 'Fayllar tanlanmoqda';

  @override
  String get pickerTitle => 'Fayllarni tanlang';

  @override
  String busyPreparing(String name) {
    return 'Tayyorlanmoqda: $name';
  }

  @override
  String get waitCurrentSendOrPause =>
      'Joriy yuborish tugashini kuting yoki uni pauza qiling.';

  @override
  String get requestSent =>
      'Qabul qilish soʻrovi yuborildi. Uni boshqa qurilmada tasdiqlang.';

  @override
  String get peerUnavailableOrRevoked =>
      'Qurilma mavjud emas yoki ishonch bekor qilingan.';

  @override
  String get cancelRetriesExhausted =>
      'Avtomatik urinishlar tugadi. Bekor qilish hali tasdiqlanmagan; qabul qiluvchi yana mavjud boʻlganda ilova natijani aniqlaydi.';

  @override
  String get connectionLostAutoResume =>
      'Aloqa uzildi. Tasdiqlangan jarayon saqlandi; ikkinchi qurilma yana tarmoqqa chiqqanda uzatish avtomatik davom etadi.';

  @override
  String get connectionNotRestored =>
      'Aloqa tiklanmadi. Tasdiqlangan jarayon saqlandi. Ilovani ikkala qurilmada oching va «Davom ettirish»ni bosing.';

  @override
  String cancelRetrying(int attempt, int max, String seconds) {
    return 'Bekor qilish aniqlanmoqda: $seconds s dan soʻng $max tadan $attempt-urinish. Qabul qiluvchidagi natija hozircha nomaʼlum.';
  }

  @override
  String connectionRetrying(int attempt, int max, String seconds) {
    return 'Aloqa uzildi. $seconds s dan soʻng $max tadan $attempt-urinish. Tasdiqlangan jarayon saqlandi.';
  }

  @override
  String get senderPausedTapResume =>
      'Yuboruvchi pauzasi. Davom ettirish uchun «Davom ettirish»ni bosing.';

  @override
  String get recipientPaused => 'Qabul qiluvchi uzatishni pauza qildi.';

  @override
  String get consentExpiredNewRequest =>
      'Rozilik kutish vaqti tugadi. Uzatish uchun yangi soʻrov kerak.';

  @override
  String get receiveNotFinished =>
      'Qabul yakunlanmadi. Yangi yuborish uchun fayllarni qayta tanlang.';

  @override
  String partiallySaved(int completed, int total) {
    return '$total ta fayldan $completed tasi saqlandi. Yakunlangan natijalar qabul qiluvchida mavjud; qolganlarini qayta yuborish mumkin.';
  }

  @override
  String get newRequestFromCopies =>
      'Saqlangan nusxalardan yangi soʻrov yaratildi. Qabul qiluvchi uni qayta tasdiqlashi kerak.';

  @override
  String get senderPaused => 'Yuboruvchi pauzasi';

  @override
  String get receiveAllowed =>
      'Qabul qilishga ruxsat berildi. Uzatish toʻxtagan boʻlsa, yuboruvchida «Davom ettirish»ni bosing.';

  @override
  String get waitCurrentSend => 'Joriy yuborish tugashini kuting.';

  @override
  String get confirmingCancel =>
      'Bekor qilish natijasi qabul qiluvchida aniqlanmoqda.';

  @override
  String get tapResumeToConfirmCancel =>
      'Qabul qiluvchida bekor qilishni tasdiqlash uchun «Davom ettirish»ni bosing.';

  @override
  String get recipientUnavailableCancel =>
      'Qabul qiluvchi mavjud emas. Bekor qilish hali tasdiqlanmagan; «Davom ettirish» natijani qayta aniqlaydi.';

  @override
  String confirmPairingWithCode(String code) {
    return 'Ulanishni boshqa qurilmada tasdiqlang. Ushbu qurilma kodi: $code — u soʻrovdagi kod bilan mos kelishi kerak.';
  }

  @override
  String pairedWith(String name) {
    return 'Ulandi: $name. Endi fayllarni yuborish mumkin.';
  }

  @override
  String get pairingApproved =>
      'Ulanish tasdiqlandi. Juftlash yakunlanishi kutilmoqda.';

  @override
  String get pairingDeclined => 'Ulanish soʻrovi rad etildi.';

  @override
  String get trustRevokedCancelUnknown =>
      'Ishonch bekor qilindi. Masofadagi bekor qilish natijasi tasdiqlanmagan.';

  @override
  String get trustRevokedStopped =>
      'Ishonch bekor qilindi. Uzatish toʻxtatildi.';

  @override
  String get deviceRenamed =>
      'Qurilma nomi oʻzgartirildi. Ulangan qurilmalar uni keyingi ulanishda koʻradi.';

  @override
  String get transferDeleted => 'Uzatish fayllari bilan birga oʻchirildi.';

  @override
  String get recordDeleted => 'Yozuv tarixdan oʻchirildi.';

  @override
  String historyCleared(int count) {
    return 'Oʻchirilgan yozuvlar: $count. Qabul qilingan fayllar saqlandi.';
  }

  @override
  String diagnosticsSaved(String path) {
    return 'Diagnostika jurnali saqlandi: $path';
  }

  @override
  String get quotaSaved => 'Vaqtinchalik xotira limiti saqlandi.';

  @override
  String get busyCleaningCopies => 'Ishlatilmayotgan nusxalar tozalanmoqda';

  @override
  String copiesCleared(int count) {
    return 'Oʻchirilgan ishlatilmayotgan vaqtinchalik nusxalar: $count. Qabul qilingan fayllar saqlandi.';
  }

  @override
  String get busyCleaningIncoming => 'Tugallanmagan qabul tozalanmoqda';

  @override
  String incomingCleared(int stopped, int removed) {
    return 'Qayta ishlangan tugallanmagan uzatishlar: $stopped. Oʻchirilgan vaqtinchalik fayllar: $removed. Tayyor qabul qilingan fayllar saqlandi.';
  }

  @override
  String get exportNotExported => 'Ilova xotirasida qabul qilindi';

  @override
  String get exportInProgress => 'Nusxa saqlanmoqda…';

  @override
  String exportDone(String destination) {
    return 'Nusxa saqlandi: $destination';
  }

  @override
  String get exportCancelledDetail => 'Oxirgi saqlash bekor qilindi';

  @override
  String get exportFileChanged =>
      'Fayl oʻzgartirilgan yoki koʻchirilgan. Nusxa saqlash toʻxtatildi.';

  @override
  String get exportFailedDetail =>
      'Nusxani saqlab boʻlmadi. Qabul qilingan fayl ilovada qoladi.';

  @override
  String get exportUnknownDetail =>
      'Saqlash natijasi tasdiqlanmagan. Qayta urinishdan oldin tanlangan jildni tekshiring.';

  @override
  String get exportCancelled =>
      'Nusxa saqlash bekor qilindi. Qabul qilingan fayl ilovada qoladi.';

  @override
  String get cannotOpenFile =>
      'Fayl saqlangan, lekin mos dasturni ochib boʻlmadi. «Ulashish» yoki «Nusxasini saqlash…»ni sinab koʻring.';

  @override
  String get backgroundedWillResume =>
      'Ilova yigʻib qoʻyildi. Ilovaga qaytganingizda uzatish davom etadi.';

  @override
  String get interruptedOnClose =>
      'Ilova yopilganda uzatish toʻxtatildi. Qabul qiluvchidagi holatni tekshirish uchun «Davom ettirish»ni bosing.';

  @override
  String get verifiedAndSaved => 'SHA-256 tekshirildi · saqlash tasdiqlandi';

  @override
  String get consentNotReceived =>
      '120 soniya ichida rozilik olinmadi. Uzatish uchun yangi soʻrov kerak.';

  @override
  String partSavedTapResume(String reason) {
    return '$reason Faylning tasdiqlangan qismi saqlandi; soʻng «Davom ettirish»ni bosing.';
  }

  @override
  String get recipientPausedShort => 'Qabul qiluvchi pauzasi';

  @override
  String get consentRequired => 'Qabul qiluvchining roziligi kerak';

  @override
  String get someFilesUnfinished =>
      'Tugallanmagan fayllar bor. Tekshirilgan natijalar saqlandi.';

  @override
  String get receivedFilesMissing =>
      'Qabul qilingan fayllar ilovadan tashqarida oʻchirilgan yoki koʻchirilgan.';

  @override
  String get errPeerUnavailable =>
      'Qurilma mavjud emas. Ikkala qurilmani bitta tarmoqqa ulang va ilovani oching.';

  @override
  String get errQrExpired =>
      'QR-kod muddati tugadi. Boshqa qurilmada yangi kod yarating.';

  @override
  String get errPairingRejected => 'Ulanish boshqa qurilmada rad etildi.';

  @override
  String get errSelfPairing => 'Bu QR-kod joriy qurilmaga tegishli.';

  @override
  String get errUnauthorized =>
      'Ishonch bekor qilingan yoki juftlash yakunlanmagan. Qurilmalarni qayta ulang.';

  @override
  String get errConsentRequired =>
      'Qabul qiluvchi hali qabul qilishni tasdiqlamadi. Soʻrovni tasdiqlang va yuborishni davom ettiring.';

  @override
  String get errOfferExpired =>
      'Taklif muddati tugadi. Fayllarni tanlab, yangi soʻrov yuboring.';

  @override
  String get errTransferPaused =>
      'Uzatish toʻxtatilgan. Ikkala tomon pauzani olib tashlagandan soʻng davom ettirish mumkin.';

  @override
  String get errHashMismatch =>
      'Nazorat summasi mos kelmadi. Fayl tayyor deb belgilanmadi.';

  @override
  String get errSourceChanged =>
      'Asl fayl tayyorlash vaqtida oʻzgardi. Uni qayta tanlang.';

  @override
  String get errFileTooLarge => 'Fayl hajmi 10 GB chegarasidan oshadi.';

  @override
  String get errDiskFull =>
      'Boshlangan uzatishlar va zaxirani hisobga olganda boʻsh joy yetarli emas. Xotira sozlamalarida joy boʻshating va qayta urinib koʻring.';

  @override
  String get errTempQuotaExceeded =>
      'Vaqtinchalik nusxalar limitiga yetildi. Ishlatilmayotgan nusxalarni tozalang yoki sozlamalarda limitni oshiring.';

  @override
  String get errQuotaBelowUsage =>
      'Bu limit vaqtinchalik nusxalar va boshlangan uzatishlar uchun joydan kichik. Avval uzatishlarni yakunlang yoki joy boʻshating.';

  @override
  String get errCapacityUnavailable =>
      'Mavjud joyni aniqlab boʻlmadi. Xotira sozlamalarida qayta tekshiring.';

  @override
  String get errCommittedFileChanged =>
      'Qabul qilingan fayl oʻchirilgan, koʻchirilgan yoki oʻzgartirilgan. Nusxa saqlash toʻxtatildi; faylni tekshiring.';

  @override
  String get errExportFailed =>
      'Tashqi nusxani saqlab boʻlmadi. Qabul qilingan fayl ilovada qoladi; boshqa joyni tanlang yoki qayta urinib koʻring.';

  @override
  String get errExportSourceUnavailable =>
      'Qabul qilingan fayl nusxa saqlash uchun mavjud emas. Uning oʻchirilmagan yoki koʻchirilmaganini tekshiring.';

  @override
  String get errExportUnsupported =>
      'Bu qurilmada tizim orqali saqlash qoʻllab-quvvatlanmaydi. Fayl ilovada qoladi.';

  @override
  String get errExportBusy =>
      'Joriy saqlash tugashini kuting yoki ochiq tizim oynasini yoping.';

  @override
  String get errDestinationExists =>
      'Bunday nomli fayl allaqachon mavjud. Boshqa nom yoki jildni tanlang.';

  @override
  String get errRateLimited =>
      'Qabul qiluvchi soʻrovlar sonini vaqtincha cheklagan. Bir necha daqiqadan soʻng qayta urinib koʻring.';

  @override
  String get errQuotaExceeded =>
      'Uzatish qabul qiluvchi qurilmasidagi mavjud joydan katta.';

  @override
  String get errJournal =>
      'Uzatishlar jurnali mavjud emas. Ilovani yangilang yoki jurnalni tiklang.';

  @override
  String get errIdentityChanged =>
      'Boshqa qurilmaning kaliti oʻzgardi. Uni roʻyxatdan oʻchiring va qayta ulang.';

  @override
  String get errTransferTooSlow =>
      'Ulanish juda sekin. Uzatish toʻxtatildi va qayta urinib koʻriladi.';

  @override
  String get errFileMissing =>
      'Qabul qilingan fayl ilovadan tashqarida oʻchirilgan yoki koʻchirilgan.';

  @override
  String get errTransferActive =>
      'Uzatishni oʻchirishdan oldin uni yakunlang yoki bekor qiling.';

  @override
  String get errQueueFull =>
      'Navbat toʻlgan. Tugallanmagan uzatishlarni yakunlang yoki bekor qiling.';

  @override
  String get errBusy =>
      'Qabul qiluvchi boshqa uzatish bilan band. Keyinroq qayta urinib koʻring.';

  @override
  String get errNotFound =>
      'Bu uzatish maʼlumotlari mavjud emas. Saqlangan fayllarni tekshiring yoki manbani qayta tanlang.';

  @override
  String get errHandshake =>
      'Qurilma kalitini tekshirib boʻlmadi. Qurilmani qayta tekshiring va qayta juftlang.';

  @override
  String get errConnectionLost =>
      'Ulanish uzildi. Ilovani ikkala qurilmada oching va uzatishni davom ettiring.';

  @override
  String get errFormat =>
      'Notoʻgʻri QR-kod yoki qoʻllab-quvvatlanmaydigan maʼlumot formati.';

  @override
  String get errFileSystem =>
      'Faylni oʻqib yoki saqlab boʻlmadi. Ruxsat va boʻsh joyni tekshiring.';

  @override
  String get errUnknown =>
      'Nimadir notoʻgʻri ketdi. Amalni takrorlang. Xato qaytarilsa, sozlamalardan diagnostika jurnalini yuboring.';

  @override
  String errWithCode(String code) {
    return 'Amal toʻxtatildi (kod $code). Maʼlumotlar muvaffaqiyatli uzatilgan deb belgilanmadi.';
  }
}
