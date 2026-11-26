# Strings added by the UI redesign (1.1+). Same format as catalog.py.
from catalog import e, S, I  # noqa: F401

# ---------- general ----------
e('moreActions', 'Ещё', 'Yana', 'More')
e('copyAction', 'Скопировать', 'Nusxalash', 'Copy')
e('textCopied', 'Скопировано', 'Nusxalandi', 'Copied')

# ---------- send ----------
e('sendLead', 'Фото, видео и документы — в исходном качестве, напрямую по Wi-Fi.', 'Rasm, video va hujjatlar — asl sifatida, toʻgʻridan-toʻgʻri Wi-Fi orqali.', 'Photos, videos and documents in original quality, straight over Wi-Fi.')
e('folder', 'Папка', 'Jild', 'Folder')
e('textMessage', 'Текст', 'Matn', 'Text')
e('addMore', 'Добавить ещё', 'Yana qoʻshish', 'Add more')
e('sendTo', 'Кому', 'Kimga', 'To')
e('sendToDevice', 'Отправить на «{name}»', '«{name}»ga yuborish', 'Send to {name}', name=S)
e('addFilesFirst', 'Добавьте файлы', 'Fayllarni qoʻshing', 'Add files')
e('noAppLink', 'Нет Ulash на другом устройстве? Отправьте по ссылке', 'Boshqa qurilmada Ulash yoʻqmi? Havola orqali yuboring', 'No Ulash on the other device? Send a link')
e('firstDeviceTitle', 'Подключите первое устройство', 'Birinchi qurilmani ulang', 'Connect your first device')
e('firstDeviceBody', 'Откройте Ulash на втором устройстве в той же сети Wi-Fi и отсканируйте QR-код. Это нужно сделать один раз.', 'Ikkinchi qurilmada xuddi shu Wi-Fi tarmogʻida Ulashni oching va QR-kodni skanerlang. Bu faqat bir marta qilinadi.', 'Open Ulash on the second device on the same Wi-Fi and scan the QR code. You only do this once.')
e('activeTransfers', 'Сейчас передаются', 'Hozir uzatilmoqda', 'In progress')
e('messageTitle', 'Сообщение', 'Xabar', 'Message')
e('messageHint', 'Текст или ссылка', 'Matn yoki havola', 'Text or link')
e('chooseRecipientFirst', 'Сначала выберите получателя.', 'Avval qabul qiluvchini tanlang.', 'Choose a recipient first.')
e('selectedSummary', '{files} · {size}', '{files} · {size}', '{files} · {size}', files=S, size=S)

# ---------- history ----------
e('searchHint', 'Поиск по названию или устройству', 'Nom yoki qurilma boʻyicha qidirish', 'Search by name or device')
e('today', 'Сегодня', 'Bugun', 'Today')
e('yesterday', 'Вчера', 'Kecha', 'Yesterday')
e('nothingFound', 'Ничего не найдено', 'Hech narsa topilmadi', 'Nothing found')
e('saveToPhotos', 'Сохранить в «Фото»', 'Rasmlarga saqlash', 'Save to Photos')
e('revealInFolder', 'Показать в папке', 'Jildda koʻrsatish', 'Show in folder')
e('executableTitle', 'Открыть программу?', 'Dastur ochilsinmi?', 'Open a program?')
e('executableBody', '«{name}» может запустить программу на этом устройстве. Открывайте такие файлы, только если доверяете отправителю.', '«{name}» bu qurilmada dastur ishga tushirishi mumkin. Bunday fayllarni faqat yuboruvchiga ishonsangiz oching.', '“{name}” can run a program on this device. Open such files only if you trust the sender.', name=S)
e('openAnyway', 'Всё равно открыть', 'Baribir ochish', 'Open anyway')
e('folderLabel', 'Папка «{name}»', '«{name}» jildi', 'Folder “{name}”', name=S)

# ---------- devices ----------
e('receiveFiles', 'Принимать файлы', 'Fayllarni qabul qilish', 'Receive files')
e('receiveHintOn', 'Ваши устройства могут отправлять сюда файлы — каждую передачу вы подтверждаете сами.', 'Qurilmalaringiz bu yerga fayl yubora oladi — har bir uzatishni oʻzingiz tasdiqlaysiz.', 'Your devices can send files here — you approve every transfer.')
e('receiveHintOff', 'Приём выключен: это устройство не видно другим.', 'Qabul oʻchiq: bu qurilma boshqalarga koʻrinmaydi.', 'Receiving is off: this device is hidden from others.')
e('deviceCode', 'Код устройства', 'Qurilma kodi', 'Device code')
e('showQr', 'Показать QR', 'QR koʻrsatish', 'Show QR')
e('noCameraEnterCode', 'Нет камеры? Ввести код', 'Kamera yoʻqmi? Kodni kiriting', 'No camera? Enter a code')
e('connectFooter', 'Откройте Ulash на другом устройстве в той же сети Wi-Fi. Подключение нужно один раз.', 'Boshqa qurilmada xuddi shu Wi-Fi tarmogʻida Ulashni oching. Ulanish bir marta kerak.', 'Open Ulash on the other device on the same Wi-Fi. You connect only once.')
e('nearby', 'Рядом', 'Yaqinda', 'Nearby')
e('nearbyFooter', 'Устройства в этой сети, на которых сейчас открыт экран подключения.', 'Shu tarmoqdagi, hozir ulanish ekrani ochiq qurilmalar.', 'Devices on this network that have the connection screen open.')
e('waitingRequests', 'Запросы на подключение', 'Ulanish soʻrovlari', 'Connection requests')

# ---------- QR sheet / pairing code ----------
e('qrHint', 'На другом устройстве откройте Ulash → «Устройства» → «Сканировать QR».', 'Boshqa qurilmada Ulash → «Qurilmalar» → «QR skanerlash»ni oching.', 'On the other device open Ulash → Devices → Scan QR.')
e('qrNearbyVisible', 'Пока открыт этот экран, устройство видно рядом и его можно подключить без QR.', 'Bu ekran ochiq ekan, qurilma yaqindagilarga koʻrinadi va uni QRsiz ulash mumkin.', 'While this screen is open, this device is visible nearby and can be connected without QR.')
e('codesMatchTitle', 'Коды совпадают?', 'Kodlar mosmi?', 'Do the codes match?')
e('sasHostBody', 'Сравните с кодом на экране «{name}». Подключайте, только если коды одинаковые.', '«{name}» ekranidagi kod bilan solishtiring. Faqat kodlar bir xil boʻlsa ulang.', 'Compare with the code on “{name}”. Connect only if the codes are the same.', name=S)
e('sasJoinerTitle', 'Подтвердите на другом устройстве', 'Boshqa qurilmada tasdiqlang', 'Confirm on the other device')
e('sasJoinerBody', 'На «{name}» должен быть показан этот же код. Нажмите там «Подключить».', '«{name}» ekranida xuddi shu kod koʻrinishi kerak. U yerda «Ulanish»ni bosing.', '“{name}” should show the same code. Tap Connect there.', name=S)
e('codesMatch', 'Да, подключить', 'Ha, ulanish', 'Yes, connect')
e('codesDiffer', 'Коды разные', 'Kodlar har xil', 'Codes differ')

# ---------- web share ----------
e('webShareEntry', 'По ссылке', 'Havola orqali', 'Via link')
e('webShareTitle', 'Отправить по ссылке', 'Havola orqali yuborish', 'Send via link')
e('webShareBody', 'Откройте ссылку в браузере на устройстве в этой же сети Wi-Fi — например, на компьютере без Ulash.', 'Havolani shu Wi-Fi tarmogʻidagi qurilma brauzerida oching — masalan, Ulash oʻrnatilmagan kompyuterda.', 'Open the link in a browser on a device on the same Wi-Fi — for example, a computer without Ulash.')
e('webShareInsecure', 'Ссылка работает без шифрования (HTTP). Пользуйтесь ей только в своей сети и остановите её после передачи.', 'Havola shifrlashsiz (HTTP) ishlaydi. Undan faqat oʻz tarmogʻingizda foydalaning va uzatishdan keyin toʻxtating.', 'The link works without encryption (HTTP). Use it only on your own network and stop it when you are done.')
e('webShareAllowUpload', 'Разрешить загрузку файлов на это устройство', 'Bu qurilmaga fayl yuklashga ruxsat berish', 'Allow uploads to this device')
e('webShareValid', 'Ссылка действует до {time}', 'Havola {time} gacha amal qiladi', 'Link valid until {time}', time=S)
e('webShareStats', 'Открыли: {clients} · скачано: {downloads} · загружено: {uploads}', 'Ochildi: {clients} · yuklab olindi: {downloads} · yuklandi: {uploads}', 'Opened: {clients} · downloaded: {downloads} · uploaded: {uploads}', clients=I, downloads=I, uploads=I)
e('webShareCreate', 'Создать ссылку', 'Havola yaratish', 'Create link')
e('webShareStop', 'Остановить', 'Toʻxtatish', 'Stop')
e('copyLink', 'Скопировать ссылку', 'Havolani nusxalash', 'Copy link')
e('webShareSelectFirst', 'Ссылка отдаёт выбранные файлы. Выберите файлы или разрешите загрузку.', 'Havola tanlangan fayllarni beradi. Fayllarni tanlang yoki yuklashga ruxsat bering.', 'The link serves the selected files. Choose files or allow uploads.')
e('webShareQrSemantics', 'QR-код ссылки для браузера', 'Brauzer uchun havola QR-kodi', 'QR code of the browser link')

# ---------- settings ----------
e('receiving', 'Получение', 'Qabul qilish', 'Receiving')
e('autoSaveToPhotos', 'Сохранять фото и видео в «Фото»', 'Rasm va videolarni «Rasmlar»ga saqlash', 'Save photos and videos to Photos')
e('autoSaveHint', 'Полученные снимки и видео сразу появятся в галерее.', 'Qabul qilingan rasm va videolar darhol galereyada paydo boʻladi.', 'Received photos and videos appear in your library right away.')
e('theme', 'Тема', 'Mavzu', 'Theme')
e('support', 'Поддержка', 'Yordam', 'Support')
e('privacyPolicy', 'Политика конфиденциальности', 'Maxfiylik siyosati', 'Privacy policy')
e('howDataHandled', 'Как обрабатываются данные', 'Maʼlumotlar qanday ishlanadi', 'How your data is handled')
e('advanced', 'Дополнительно', 'Qoʻshimcha', 'Advanced')
e('advancedHint', 'Хранилище, диагностика, сброс ключей', 'Xotira, diagnostika, kalitlarni tiklash', 'Storage, diagnostics, key reset')
e('about', 'О приложении', 'Ilova haqida', 'About')
e('dangerZone', 'Безопасность', 'Xavfsizlik', 'Security')

# ---------- onboarding ----------
e('onbAllowTitle', 'Разрешите доступ к сети', 'Tarmoqqa ruxsat bering', 'Allow local network access')
e('onbAllowBody', 'Ulash ищет ваши устройства только в вашей сети Wi-Fi. Без этого разрешения устройства не найдут друг друга.', 'Ulash qurilmalaringizni faqat Wi-Fi tarmogʻingizda qidiradi. Bu ruxsatsiz qurilmalar bir-birini topa olmaydi.', 'Ulash looks for your devices only on your Wi-Fi. Without this permission your devices can’t find each other.')
e('allowAccess', 'Разрешить доступ', 'Ruxsat berish', 'Allow access')

# ---------- web uploads / misc (1.2) ----------
e('webUploadTitle', 'Загрузка из браузера', 'Brauzerdan yuklash', 'Upload from a browser')
e('webUploadBody', '{client} хочет загрузить сюда {files} ({size}).', '{client} bu yerga {files} ({size}) yuklamoqchi.', '{client} wants to upload {files} ({size}) here.', client=S, files=S, size=S)
e('allow', 'Разрешить', 'Ruxsat berish', 'Allow')
e('waitingForApprovalOn', 'Ждём подтверждения на «{name}»', '«{name}»da tasdiqlash kutilmoqda', 'Waiting for approval on {name}', name=S)
e('connectedTo', 'Подключено к «{name}»', '«{name}»ga ulandi', 'Connected to {name}', name=S)
e('shareSheetLink', 'Ссылка', 'Havola', 'Link')
e('nearbyEmpty', 'Рядом пока никого. Откройте на другом устройстве «Устройства» → «Показать QR».', 'Hozircha yaqinda hech kim yoʻq. Boshqa qurilmada «Qurilmalar» → «QR koʻrsatish»ni oching.', 'Nobody nearby yet. On the other device open Devices → Show QR.')
e('noDevicesYet', 'Пока нет подключённых устройств', 'Hozircha ulangan qurilmalar yoʻq', 'No connected devices yet')
e('filterText', 'Текст', 'Matn', 'Text')
e('saveDestination', 'Куда сохранять', 'Qayerga saqlash', 'Save to')
e('largeTextSample', 'Размер текста меняется в настройках устройства.', 'Matn oʻlchami qurilma sozlamalarida oʻzgaradi.', 'Text size follows your device settings.')
