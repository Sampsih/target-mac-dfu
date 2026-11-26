# Установка

## Готовая версия

1. Скачайте архив приложения со страницы [последнего релиза GitHub](https://github.com/Sampsih/target-mac-dfu/releases/latest).
2. Распакуйте архив и перенесите `Target Mac DFU.app` в `/Applications`.
3. Откройте приложение. Если macOS блокирует первый запуск и вы доверяете скачанному архиву, выберите **Системные настройки → Конфиденциальность и безопасность → Всё равно открыть**. [Инструкция Apple по первому запуску](https://support.apple.com/ru-ru/102445).

Приложение распространяется без сертификата Apple Developer. Поэтому macOS может запросить дополнительное подтверждение первого запуска.

## Apple Configurator и Automation Tools

Для чтения модели и ECID и запуска Restore в Target Mac DFU нужен `cfgutil`. Если приложение его не находит, установите Apple Configurator, выберите в его меню **Install Automation Tools…**, затем нажмите **Проверить снова** в Target Mac DFU.

Target Mac DFU запускается на Mac с Apple silicon и macOS 14 или новее. Для установки текущей версии Apple Configurator 2.21 нужна macOS 15.7 или новее. Если совместимого Configurator нет, воспользуйтесь штатным восстановлением через Finder, которое Apple описывает для Host Mac с macOS 14 или новее. [Apple Configurator в Mac App Store](https://apps.apple.com/us/app/apple-configurator/id1037126344) · [Штатное восстановление](https://support.apple.com/en-us/108900).

## macvdmtool

Для кнопки автоматического DFU приложение использует собственную копию `macvdmtool` из Application Support. При первом запуске оно загружает точную закреплённую ревизию официального проекта Asahi Linux, проверяет её и собирает инструмент локально. Случайная копия из `/usr/local/bin` не используется.

Для однократной сборки нужны Xcode Command Line Tools. Если их нет, кнопка DFU откроет стандартное окно установки macOS. Установить их также можно командой:

```bash
xcode-select --install
```

## Удаление

Переместите приложение в Корзину. Пользовательские настройки, журналы и служебные файлы находятся в:

```text
~/Library/Application Support/Target Mac DFU
~/Library/Logs/TargetMacDFU.log
```

Загруженные IPSW остаются в выбранной пользователем папке.
