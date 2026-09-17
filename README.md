# GooseLee / Гусли

Лёгкое, бесплатное и настраиваемое macOS-приложение для записи, распознавания и конспектирования встреч. Главный сценарий — русские и мультиязычные разговоры; диктовка остаётся удобным дополнительным режимом.

GooseLee начинались как русский fork [Muesli](https://github.com/Muesli-HQ/muesli), но теперь живут в самостоятельном репозитории и не синхронизируются с upstream целиком. Название читается как «Гусли» по-русски и как Goose Lee по-английски. Это отдельный продукт со своим набором моделей, интерфейсом, хранением данных и релизным циклом. Полезные upstream-исправления переносятся точечно.

## Что умеют Гусли

- записывать микрофон и системный звук без бота в звонке;
- локально распознавать встречи и диктовку на Apple Silicon;
- сохранять исходную запись, расшифровку, заметки и историю встреч;
- повторно распознавать сохранённую запись;
- чистить расшифровку локальной Qwen-моделью или выбранным облачным провайдером;
- делать summary встречи через настраиваемый LLM;
- при желании подключать календарь и локальный Google Meet speaker bridge.

Основной ASR-каталог намеренно ограничен тремя вариантами:

| Модель | Основное назначение |
| --- | --- |
| **GigaAM v3 E2E CTC** | Русская речь, встречи и диктовка |
| **Parakeet v3** | Мультиязычные встречи и диктовка, 25 языков |
| **Nemotron 3.5 Multilingual** | Потоковая мультиязычная диктовка и live text |

Для английских встреч можно отдельно скачать **Parakeet Realtime EOU**. Он используется только для необязательного live-preview, никогда не загружается автоматически и не заменяет финальную расшифровку встречи.

## Принципы

- **Russian-first, не Russian-only.** Русская речь не должна быть второсортным режимом, но мультиязычные встречи тоже поддерживаются.
- **Local-first.** Запись и ASR выполняются на Mac. Сетевые запросы появляются только там, где они нужны выбранной функции: обновления, загрузка моделей, календарь, облачная чистка или summary.
- **Без телеметрии и попрошаек.** В приложении нет продуктовой аналитики, донатных кнопок и milestone-уведомлений.
- **Меньше магии.** Небольшой поддерживаемый набор моделей и явные настройки важнее каталога из десятков полурабочих вариантов.
- **Данные принадлежат пользователю.** Аудио встреч не отправляется в облако и не синхронизируется через iCloud.

## Требования и установка

- Mac с Apple Silicon;
- macOS 14.2 или новее;
- свободное место для выбранных локальных моделей.

Готовые сборки: [GitHub Releases](https://github.com/ivkiwi/gooselee/releases).

Проект распространяется по лицензии [MIT](LICENSE); исходный Muesli и его авторы сохраняют заслуженный credit и copyright.

## English

GooseLee is a lightweight, free, configurable macOS meeting recorder, local transcription app, and meeting summarizer with a Russian-first focus. The name reads as «Гусли» in Russian and Goose Lee in English. It started from [Muesli](https://github.com/Muesli-HQ/muesli), but now lives in a standalone repository and is maintained as an independent product. Useful upstream fixes are reviewed and ported selectively.

The deliberately small ASR catalog contains GigaAM v3, Parakeet v3, and Nemotron 3.5 Multilingual. Optional Parakeet Realtime EOU support is available only for English live meeting previews. GooseLee has no product telemetry, donation prompts, or paid upsells.
