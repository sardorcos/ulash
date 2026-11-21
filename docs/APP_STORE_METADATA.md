# Ulash — материалы для App Store Connect и Google Play

Готовые тексты для карточки приложения. Поля скопируйте как есть; при необходимости сократите под лимиты, они указаны в скобках.

## Общие поля

| Поле | Значение |
|---|---|
| Name (30) | **Ulash** (если занято: «Ulash — передача файлов» / «Ulash: File Transfer») |
| Bundle ID | `uz.ulash.app` |
| Primary language | Russian |
| Category | Utilities (вторичная — Productivity) |
| Age rating | 4+ (на все вопросы анкеты «None/No») |
| Price | Free, без встроенных покупок |
| Copyright | © 2026 <владелец аккаунта> |
| Privacy Policy URL | опубликуйте `docs/PRIVACY_POLICY.md` (например, GitHub Pages / Notion / свой сайт) и вставьте ссылку |
| Support URL | страница или почта поддержки (обязательно) |

## App Privacy («nutrition label»)

- **Data Collection:** «No, we do not collect data from this app».
- Обоснование: приложение не имеет серверов, аналитики, рекламы и аккаунтов; файлы передаются только между устройствами пользователя в локальной сети. Журнал диагностики остаётся на устройстве и отправляется только самим пользователем через системное меню «Поделиться».

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` уже указан в Info.plist: используется только стандартный TLS для защиты передаваемых данных пользователя (освобождение mass-market / Category 5 Part 2 note 4). Перед публикацией подтвердите вывод у юриста. Для распространения во Франции может потребоваться отдельная декларация.

---

## Русский (основной)

**Subtitle (30):** Файлы между вашими устройствами

**Promotional text (170):** Отправляйте фото, видео и документы с iPhone на компьютер и обратно в исходном качестве — напрямую по Wi-Fi, без облака и регистрации.

**Keywords (100):** передать,файлы,wifi,компьютер,windows,android,фото,видео,обмен,локальная сеть,airdrop,qr

**Description:**

Ulash переносит файлы между вашими устройствами напрямую по локальной сети — быстро, приватно и без ограничений облака.

• Фото и видео в исходном качестве — без сжатия и перекодирования
• iPhone, iPad, Android и Windows — в любую сторону
• Без аккаунта, без загрузки на серверы, без рекламы
• Подключение один раз по QR-коду с проверкой кода устройства
• Каждую входящую передачу вы подтверждаете сами
• Шифрование соединения и проверка целостности каждого файла (SHA-256)
• Докачка: при обрыве связи передача продолжается с места остановки
• Большие файлы и пакеты — до 10 ГБ на файл
• «Поделиться» и «Сохранить копию» для полученных файлов
• Русский, узбекский и английский языки, светлая и тёмная темы

Как это работает: откройте Ulash на двух устройствах в одной сети Wi-Fi, на принимающем покажите QR-код, на отправляющем отсканируйте его — и отправляйте файлы. Держите приложение открытым на обоих устройствах во время передачи.

---

## Oʻzbekcha

**Subtitle:** Qurilmalaringiz orasida fayllar

**Promotional text:** Rasm, video va hujjatlarni iPhone’dan kompyuterga va aksincha asl sifatida yuboring — Wi-Fi orqali to‘g‘ridan-to‘g‘ri, bulutsiz va ro‘yxatdan o‘tmasdan.

**Keywords:** fayl,yuborish,wifi,kompyuter,windows,android,rasm,video,almashish,mahalliy tarmoq,qr

**Description:**

Ulash fayllarni qurilmalaringiz orasida mahalliy tarmoq orqali to‘g‘ridan-to‘g‘ri uzatadi — tez, maxfiy va bulut cheklovlarisiz.

• Rasm va videolar asl sifatda — siqilmaydi
• iPhone, iPad, Android va Windows — istalgan yo‘nalishda
• Akkauntsiz, serverlarga yuklamasdan, reklamasiz
• Bir marta QR-kod orqali ulanish va qurilma kodini tekshirish
• Har bir kiruvchi uzatishni o‘zingiz tasdiqlaysiz
• Shifrlangan ulanish va har bir fayl yaxlitligini tekshirish (SHA-256)
• Aloqa uzilsa, uzatish to‘xtagan joyidan davom etadi
• Katta fayllar — har bir fayl 10 GB gacha
• Rus, o‘zbek va ingliz tillari, yorug‘ va qorong‘i mavzu

---

## English

**Subtitle:** Files between your devices

**Promotional text:** Send photos, videos and documents from iPhone to your computer and back in original quality — directly over Wi-Fi, no cloud, no sign-up.

**Keywords:** file transfer,wifi,send files,pc,windows,android,photos,videos,share,local network,qr

**Description:**

Ulash moves files between your own devices directly over your local network — fast, private and free of cloud limits.

• Photos and videos in original quality — no compression or transcoding
• iPhone, iPad, Android and Windows — in any direction
• No account, no uploads to servers, no ads
• Pair once with a QR code and a matching device code
• You approve every incoming transfer
• Encrypted connections and SHA-256 integrity check for every file
• Resumes where it stopped if the connection drops
• Large files and batches — up to 10 GB per file
• Share or save received files anywhere
• Russian, Uzbek and English, light and dark themes

---

## App Review Information → Notes (вставить в поле «Notes»)

> Ulash transfers files directly between two of the user's own devices on the same Wi-Fi network. There is no account, server or login, so no demo credentials are needed.
>
> To test you need TWO devices on the same Wi-Fi network (for example two iPhones/iPads, or an iPhone plus an Android phone or a Windows PC running Ulash):
> 1. Install Ulash on both devices and open it. Tap through the three intro screens and allow "Local Network" access when iOS asks (required to find the other device).
> 2. On device B open the "Receive" tab and tap "Show invitation" — a QR code appears.
> 3. On device A open "Devices" → "Scan QR" (or "Enter invitation" and paste the copied text) and scan the code.
> 4. Device B shows a pairing request with a code; confirm it matches the code shown on device A and tap "Connect".
> 5. On device A open "Send", tap "Photos & videos" or "Files", choose a file, select device B and tap "Send files".
> 6. Device B shows the incoming files — tap "Accept files". When the transfer finishes, open the file from "History", or use "Share" / "Save a copy…".
>
> A screen recording of this flow is available here: <ВСТАВЬТЕ ССЫЛКУ НА ВИДЕО>
>
> Camera is used only to scan the pairing QR code. Local network access is used only to find and connect to the user's own devices. The app does not collect any data.

**Видео для ревьюера** (рекомендуется): запишите 1–2 минуты экрана двух устройств, проходящих шаги 1–6, загрузите как unlisted на YouTube/Drive и вставьте ссылку.

## Скриншоты

Минимум: iPhone 6.9" (1320×2868) — 3–10 шт.; если оставлена поддержка iPad (сейчас да): iPad 13" (2064×2752). Рекомендуемые экраны: «Отправить» с выбранными файлами, входящий запрос с кнопкой «Принять», QR-приглашение, «История» с завершённой передачей, тёмная тема. Подписи на скриншотах — на языке локализации.

## Google Play (Data safety)

- Data collected: **No**. Data shared: **No**.
- Encryption in transit: **Yes**. Users can request deletion: данные хранятся только на устройстве (удаление приложения удаляет всё).
- Примечание: сканер QR на Android использует Google ML Kit (обработка на устройстве, без отправки изображений).
- Новые личные аккаунты Play: обязателен закрытый тест (≥12 тестировщиков, 14 дней) до production.
