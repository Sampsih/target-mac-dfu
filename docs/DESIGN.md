# Дизайн Target Mac DFU 1.3 / Design notes

Запрос «обновить для Astra 6» относится к работе над дизайном, а не к интеграции AI в приложение. Аккаунт OpenAI, API-ключ и подключение к модели для работы DFU не нужны.

## Решения / Decisions

- **Навигация / Navigation:** Liquid Glass `.regular` только в боковой панели на macOS 26 при компиляции Swift 6.2+. Старые системы используют `.regularMaterial`.
- **Содержимое / Content:** обычный материал, семантические цвета, нейтральная обводка. Стекло не дублируется в каждом блоке.
- **Размеры / Metrics:** радиус карточки 18 pt, внутренний радиус 12 pt, отступ 16 pt, расстояние между карточками 14 pt, боковая панель 216 pt. Это решения проекта, не «обязательные настройки Astra».
- **Адаптация / Layout:** основная кнопка переходит под описание, если строке не хватает ширины. Высота сводки устройства определяется содержимым.
- **Доступность / Accessibility:** системные Reduce Transparency и Increase Contrast; выбранный раздел отмечен для VoiceOver. Отключение прозрачности не меняет доступность функций.
- **Безопасность / Safety:** подтверждения Restore сохранены. Редизайн не меняет команды DFU, проверку прошивки или привилегии.

## Источники / Sources

Проверены 10 сентября 2026:

- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials) — стекло в навигации, стандартные материалы в содержимом, умеренное использование эффектов.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) — системная адаптация и доступность.

## Проверка / Verification

`./scripts/test.sh` и `./scripts/build.sh` проверяют код. `./scripts/render-screenshots.sh` обновляет изображения README в демо-режиме без восстановления реального устройства.

Для воспроизводимой сборки 1.3 использован SDK macOS 26.5. Если активный экспериментальный SDK 27 требует отсутствующий плагин `SwiftUIMacros`, укажите установленный стабильный SDK через `TARGET_MAC_DFU_SDK` при сборке и рендере. Например: `TARGET_MAC_DFU_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./scripts/build.sh`. Менять системный Xcode или настройки пользователя не требуется.

Дополнительные параметры рендера:

```sh
TARGET_MAC_DFU_SCREENSHOT_LANGUAGE=de TARGET_MAC_DFU_SCREENSHOT_WIDTH=1080 \
TARGET_MAC_DFU_SCREENSHOT_LIGHT=1 \
TARGET_MAC_DFU_RESOURCES="$PWD/Resources" .build/RenderScreenshots /tmp/target-mac-dfu-preview
```

Рендер проверяет компоновку, но не полностью воспроизводит живое стекло оконного композитора. Перед релизами дополнительно проверяйте прокрутку, клавиатурную навигацию, VoiceOver, обе темы, все пять языков и минимальный размер окна. Проверка реального DFU требует оборудования и не заменяется скриншотами или демо-режимом.
