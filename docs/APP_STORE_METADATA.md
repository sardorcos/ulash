# Ulash — материалы для App Store Connect и Google Play

Готовые тексты для карточки приложения. Поля скопируйте как есть; при необходимости сократите под лимиты, они указаны в скобках.

## Общие поля

| Поле | Значение |
|---|---|
| Name (30) | **Ulash** (если занято: «Ulash — передача файлов») |
| Bundle ID | `uz.ulash.app` |
| Primary language | Russian |
| Category | Utilities (вторичная — Productivity) |
| Age rating | 4+ (на все вопросы анкеты «None/No») |
| Price | Free, без встроенных покупок |
| Copyright | © 2026 Sardorbek Qosimbekov |
| Privacy Policy URL | https://sardorcos.github.io/neverland-legal/ulash/privacy.html |
| Support URL | https://sardorcos.github.io/neverland-legal/ulash/support.html |

## App Privacy («nutrition label»)

- **Data Collection:** «No, we do not collect data from this app».
- Обоснование: нет серверов, аналитики, рекламы и аккаунтов; файлы идут только между устройствами пользователя в локальной сети. Журнал диагностики остаётся на устройстве и отправляется только самим пользователем.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` в Info.plist: только стандартный TLS для защиты данных пользователя. Подтвердите вывод у юриста; для Франции может понадобиться декларация.

> Правило точности: в текстах упоминаются только реально распространяемые платформы — iPhone, iPad и (после публикации в Google Play) Android. Windows/Mac не упоминать, пока клиенты не опубликованы. Чужие товарные знаки (AirDrop и т. п.) в ключевые слова не включать.

---

## Русский (основной)

**Subtitle (30):** Файлы между вашими устройствами

**Promotional text (170):** Отправляйте фото, видео и документы между iPhone, iPad и Android в исходном качестве — напрямую по Wi-Fi, без облака и регистрации.

**Keywords (100):** передать,файлы,фото,видео,wifi,обмен,отправить,локальная сеть,qr,папка,без интернета

**Description:**

Ulash переносит файлы между вашими устройствами напрямую по локальной сети — быстро, приватно и без ограничений облака.

• Фото и видео в исходном качестве — без сжатия
• iPhone, iPad и Android — в любую сторону
• «Поделиться → Ulash» из Фото, Файлов и других приложений
• Папки целиком, текст и ссылки
• Подключение один раз: QR-код или устройство рядом, сверка 6-значного кода
• Каждую входящую передачу вы подтверждаете сами
• Шифрование соединения и проверка целостности каждого файла
• Докачка после обрыва связи
• Полученное — в «Файлах» и одной кнопкой в «Фото»
• Отправка на компьютер без приложения: ссылка для браузера в той же сети Wi-Fi
• Без аккаунта, рекламы и сбора данных
• Русский, узбекский и английский, светлая и тёмная темы

Как это работает: откройте Ulash на двух устройствах в одной сети Wi-Fi, подключите их по QR-коду и отправляйте файлы. Держите приложение открытым на обоих устройствах во время передачи.

---

## Oʻzbekcha

**Subtitle:** Qurilmalaringiz orasida fayllar

**Promotional text:** Rasm, video va hujjatlarni iPhone, iPad va Android oʻrtasida asl sifatida yuboring — Wi-Fi orqali toʻgʻridan-toʻgʻri, bulutsiz va roʻyxatdan oʻtmasdan.

**Keywords:** fayl,yuborish,rasm,video,wifi,almashish,mahalliy tarmoq,qr,papka

**Description:**

Ulash fayllarni qurilmalaringiz orasida mahalliy tarmoq orqali toʻgʻridan-toʻgʻri uzatadi — tez, maxfiy va bulut cheklovlarisiz.

• Rasm va videolar asl sifatda
• iPhone, iPad va Android — istalgan yoʻnalishda
• «Ulashish → Ulash» Rasmlar, Fayllar va boshqa ilovalardan
• Butun papkalar, matn va havolalar
• Bir marta ulanish: QR-kod yoki yaqindagi qurilma, 6 xonali kodni tekshirish
• Har bir kiruvchi uzatishni oʻzingiz tasdiqlaysiz
• Shifrlangan aloqa va har bir fayl yaxlitligini tekshirish
• Aloqa uzilsa, uzatish toʻxtagan joyidan davom etadi
• Akkaunt, reklama va maʼlumot yigʻishsiz
• Rus, oʻzbek va ingliz tillari

---

## English

**Subtitle:** Files between your devices

**Promotional text:** Send photos, videos and documents between iPhone, iPad and Android in original quality — directly over Wi-Fi, no cloud, no sign-up.

**Keywords:** file transfer,send files,wifi,photos,videos,share,local network,qr,folder,offline

**Description:**

Ulash moves files between your own devices directly over your local network — fast, private and free of cloud limits.

• Photos and videos in original quality — no compression
• iPhone, iPad and Android — in any direction
• Share to Ulash from Photos, Files and other apps
• Whole folders, text and links
• Pair once: QR code or a nearby device with a matching 6-digit code
• You approve every incoming transfer
• Encrypted connections and an integrity check for every file
• Resumes where it stopped if the connection drops
• Received items in the Files app and one tap to save to Photos
• Send to a computer without the app: a browser link on the same Wi-Fi
• No account, no ads, no data collection
• Russian, Uzbek and English, light and dark themes

---

## App Review Information → Notes (вставить в поле «Notes»)

> Ulash transfers files directly between two of the user's own devices on the same Wi-Fi network. There is no account, server or login, so no demo credentials are needed.
>
> To test you need TWO devices on the same Wi-Fi network: two iPhones/iPads, or an iPhone plus an Android phone running Ulash. Without a second device, open Send → Send via link and download the selected files in a browser on any computer on the same Wi-Fi.
> 1. Install Ulash on both devices and open it. Tap through the three intro screens and allow "Local Network" access when iOS asks (required to find the other device).
> 2. On device B open "Devices" and tap "Show QR".
> 3. On device A open "Devices" → "Scan QR" (or choose device B under "Nearby").
> 4. Both devices show the same 6-digit code; confirm on device B.
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
