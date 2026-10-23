# FluroCup

Мобильный видеоредактор для Android: Kotlin, Jetpack Compose (Material 3), Media3, Hilt, Room.

## Модули

| Модуль | Назначение |
| --- | --- |
| `app` | Точка входа, сплэш, навигация, тема окна, иконка |
| `core-model` | Модель проекта и таймлайна (чистый Kotlin, kotlinx.serialization) |
| `core-ui` | Дизайн-система: тема, бренд-градиент, логотип, кнопки |
| `core-data` | Хранение проектов: Room (список) + JSON-файл проекта |
| `core-engine` | Видео-ядро: анализ, прокси, превью, экспорт, шейдеры (этапы 2–8) |
| `feature-home` | Главный экран: «Создать новый», сетка проектов, меню проекта |
| `feature-editor` | Редактор (сейчас открывает проект; таймлайн появится на этапе 3) |
| `feature-export` | Экспорт (этап 4) |

## Сборка

```bash
cd FluroCup
./gradlew :app:assembleDebug        # APK: app/build/outputs/apk/debug/
./gradlew :core-model:test          # юнит-тесты модели
```

Нужны JDK 17 и Android SDK (compileSdk 36). Каждый push в `FluroCup/` собирается
в GitHub Actions (`.github/workflows/flurocup.yml`); готовый APK лежит в артефакте
`FluroCup-debug-apk` у запуска.

## Хранение проектов

`files/projects/<id>/project.json` во внутренней памяти — сам проект. Запись атомарная:
сначала во временный файл, затем переименование. Room-таблица `projects` хранит то,
что нужно карточке на главном экране (название, длительность, разрешение и FPS исходника,
дата изменения, путь к превью-кадру).
