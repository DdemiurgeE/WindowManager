# Архитектура WindowManager

Документ описывает устройство текущего приложения WindowManager, его основные сервисы, модели данных и поток выполнения пользовательских сценариев.

## Назначение

WindowManager автоматизирует восстановление рабочих раскладок окон на macOS. Основная задача — быстро вернуть окна приложений на нужные дисплеи и в нужные позиции после переподключения мониторов, смены рабочего места или ручной перестановки окон.

Приложение построено как SwiftUI + AppKit macOS app:

- SwiftUI отвечает за главное окно, список раскладок и экран разрешений.
- AppKit используется для Menu Bar, работы с окнами приложения и системными экранами.
- Accessibility API (`ApplicationServices`) используется для чтения и изменения позиций окон сторонних приложений.
- `UserDefaults` используется как локальное хранилище сохранённых раскладок.

## Высокоуровневая схема

```text
WindowManagerApp
├── ContentView
│   ├── Display Configuration
│   ├── Quick Actions
│   └── LayoutListView
├── Settings → PermissionsView
├── StatusBarService
├── ScreenMonitorService
├── WindowService
├── LayoutStorageService
└── PermissionsService
```

Потоки данных:

```text
Save Current Layout
    ↓
WindowService.captureCurrentLayout()
    ↓
[WindowInfo]
    ↓
Layout(name, windows, screenConfiguration)
    ↓
LayoutStorageService.saveLayout()
    ↓
UserDefaults["SavedLayouts"]
```

```text
Restore Layout
    ↓
LayoutListView / StatusBarService
    ↓
WindowService.restoreLayout(layout)
    ↓
AXUIElementSetAttributeValue(kAXPositionAttribute / kAXSizeAttribute)
```

```text
Screen configuration changed
    ↓
ScreenMonitorService
    ↓
Find matching Layout.screenConfiguration
    ↓
Restore most recently used matching layout
    ↓
User notification
```

## Точка входа

Файл: `WindowManager/WindowManagerApp.swift`

`WindowManagerApp` создаёт три основных `@StateObject`:

- `WindowService`
- `PermissionsService`
- `LayoutStorageService`

Они передаются в SwiftUI-иерархию через `environmentObject`.

При появлении главного окна вызывается `setupServices()`:

1. `StatusBarService.shared.setup(...)` — создаёт Menu Bar item и меню.
2. `ScreenMonitorService.shared.setup(...)` — передаёт сервисы для автоматического применения раскладок.

`AppDelegate`:

- проверяет разрешения при запуске;
- сохраняет ссылку на главное окно;
- не завершает приложение при закрытии последнего окна, чтобы оно продолжало работать из Menu Bar;
- умеет заново показать главное окно при повторном открытии приложения.

## Модели данных

### `WindowInfo`

Файл: `WindowManager/Models/WindowInfo.swift`

Описывает одно сохранённое окно:

| Поле | Назначение |
| --- | --- |
| `id` | UUID записи окна |
| `appName` | `localizedName` приложения |
| `windowTitle` | Заголовок окна из Accessibility API |
| `frame` | Абсолютный `CGRect` в координатах `NSScreen` |
| `relativeFrame` | Нормализованный frame относительно экрана |
| `screenIndex` | Индекс экрана, на котором окно было захвачено |
| `timestamp` | Время захвата |

`relativeFrame` — ключевой механизм устойчивости к переподключению мониторов. Вместо того чтобы полагаться только на абсолютные координаты, приложение сохраняет доли положения и размера окна относительно конкретного экрана:

```text
x      = (window.x - screen.x) / screen.width
y      = (window.y - screen.y) / screen.height
width  = window.width / screen.width
height = window.height / screen.height
```

При восстановлении эти значения пересчитываются в текущий frame экрана.

### `Layout`

Файл: `WindowManager/Models/Layout.swift`

Описывает сохранённую раскладку:

| Поле | Назначение |
| --- | --- |
| `id` | UUID раскладки |
| `name` | Пользовательское имя |
| `windows` | Список сохранённых окон |
| `createdAt` | Дата создания |
| `lastUsed` | Последнее применение раскладки |
| `screenConfiguration` | Конфигурация экранов на момент сохранения |

### `ScreenConfiguration`

Хранит отсортированный список идентификаторов экранов и их количество. Используется для поиска раскладок, подходящих под текущий набор дисплеев.

Идентификатор экрана строится так:

1. Если доступен `NSScreenNumber`, используется `screen_<number>`.
2. Иначе fallback: `screen_<width>x<height>_<x>_<y>`.

## Сервисы

### `PermissionsService`

Файл: `WindowManager/Services/PermissionsService.swift`

Отвечает за проверку и запрос разрешений macOS:

- Accessibility: `AXIsProcessTrustedWithOptions`.
- Screen Recording: попытка прочитать информацию об окнах через `CGWindowListCopyWindowInfo`.

Также открывает соответствующие страницы System Settings через URL-схемы `x-apple.systempreferences`.

### `WindowService`

Файл: `WindowManager/Services/WindowService.swift`

Главный сервис работы с окнами.

#### Захват раскладки

`captureCurrentLayout()`:

1. Проверяет Accessibility-разрешение.
2. Получает `NSWorkspace.shared.runningApplications`.
3. Фильтрует обычные приложения с `activationPolicy == .regular`.
4. Для каждого приложения создаёт `AXUIElementCreateApplication(pid)`.
5. Читает `kAXWindowsAttribute`.
6. Для каждого окна читает:
   - `kAXTitleAttribute`;
   - `kAXPositionAttribute`;
   - `kAXSizeAttribute`.
7. Отбрасывает слишком маленькие окна и окна вне всех экранов.
8. Определяет экран по максимальной площади пересечения окна с экраном.
9. Сохраняет абсолютный `frame` и нормализованный `relativeFrame`.

#### Координаты AX и NSScreen

Accessibility/Quartz и `NSScreen` используют разные оси Y:

- `NSScreen`: начало координат в нижнем левом углу основного экрана, Y растёт вверх.
- AX/Quartz: начало координат в верхнем левом углу основного экрана, Y растёт вниз.

Поэтому сервис содержит конвертеры:

- `screenFrameToAXOrigin(_:)`
- `axOriginToScreenFrame(axOrigin:size:)`

Формула для перехода из `NSScreen` frame в AX origin:

```text
axY = mainScreenHeight - screenY - windowHeight
```

#### Восстановление раскладки

`restoreLayout(_:)`:

1. Проверяет Accessibility-разрешение.
2. Получает текущие запущенные приложения и список экранов.
3. Для каждого `WindowInfo` вычисляет `targetFrame`.
4. Ищет приложение по `localizedName == appName`.
5. Ищет окно по заголовку. Если у приложения одно окно, использует его как fallback.
6. Устанавливает позицию и размер через AX API.

`setWindowFrame(...)` выставляет позицию и размер в несколько шагов:

1. Позиция.
2. Небольшая пауза.
3. Размер.
4. Небольшая пауза.
5. Повторная позиция.
6. Отложенная проверка drift через 0.5 секунды и дополнительная коррекция при необходимости.

Повторная установка позиции нужна потому, что некоторые приложения могут клипать размер окна и тем самым смещать позицию.

### `LayoutStorageService`

Файл: `WindowManager/Services/LayoutStorageService.swift`

Хранит массив `Layout` в `UserDefaults`:

- ключ: `SavedLayouts`;
- кодирование: `JSONEncoder`;
- даты: `.iso8601`.

Методы:

- `saveLayout(_:)`
- `deleteLayout(_:)`
- `updateLayout(_:)`
- `markLayoutAsUsed(_:)`

### `ScreenMonitorService`

Файл: `WindowManager/Services/ScreenMonitorService.swift`

Отслеживает `NSApplication.didChangeScreenParametersNotification` с debounce 0.5 секунды.

При изменении экранов:

1. Собирает новую `ScreenConfiguration`.
2. Сравнивает её с текущей.
3. Если конфигурация изменилась и Auto-apply включён, ищет сохранённые раскладки с такой же конфигурацией.
4. Сортирует найденные раскладки по `lastUsed`.
5. Через 1 секунду применяет самую свежую раскладку.
6. Отправляет уведомление `Window Manager — Layout '<name>' applied automatically`.

Auto-apply хранится в `UserDefaults` под ключом `autoApplyEnabled`. Значение по умолчанию — `true`.

### `StatusBarService`

Файл: `WindowManager/Services/StatusBarService.swift`

Создаёт `NSStatusItem` с системной иконкой `macwindow.on.rectangle` и динамическое меню.

Меню обновляется перед каждым открытием и содержит:

1. список сохранённых раскладок;
2. `Save Current Layout...`;
3. `Auto-apply Layouts`;
4. `Open Window`;
5. `Quit`.

Для запуска сохранения из Menu Bar сервис открывает главное окно и отправляет уведомление `ShowSaveLayoutAlert`, которое слушает `ContentView`.

## UI-компоненты

### `ContentView`

Файл: `WindowManager/Views/ContentView.swift`

Главное окно приложения. Состоит из левой панели и основной области.

Левая панель:

- иконка и название приложения;
- краткое описание;
- статус Active;
- переключатель Auto-apply.

Основная область:

- `Display Configuration` — текущие экраны;
- `Quick Actions` — сохранение текущей раскладки и refresh;
- `Saved Layouts` — список раскладок.

Сохранение раскладки открывает `SaveLayoutSheet`, который показывает:

- имя раскладки;
- конфигурацию дисплеев;
- список найденных окон.

### `LayoutListView`

Файл: `WindowManager/Views/LayoutListView.swift`

Показывает сохранённые раскладки. Для каждой раскладки отображает:

- имя;
- количество окон;
- дату создания;
- дату последнего использования, если есть;
- кнопку Restore.

Контекстное меню позволяет восстановить или удалить раскладку.

### `PermissionsView`

Файл: `WindowManager/Views/PermissionsView.swift`

Settings-экран для проверки и выдачи разрешений Accessibility и Screen Recording.

## Ограничения и поведение на краях

1. **Приложение не запускает отсутствующие приложения.** Если приложение из раскладки не запущено, соответствующее окно пропускается.
2. **Окна сопоставляются по заголовкам.** Динамические заголовки могут мешать точному восстановлению.
3. **Некоторые окна нельзя двигать.** Отдельные приложения запрещают изменение frame через Accessibility API или сразу корректируют его обратно.
4. **Права macOS критичны.** Без Accessibility восстановление и захват не работают.
5. **Screen Recording определяется эвристически.** Сервис проверяет возможность читать имена окон через `CGWindowListCopyWindowInfo`.
6. **Экспорт раскладок отсутствует.** Сейчас раскладки живут только в локальном `UserDefaults`.
7. **Auto-apply привязан к `ScreenConfiguration`.** Если идентификаторы экранов меняются нестабильно, подходящая раскладка может не найтись.

## Проверка сборки

Команда для локальной проверки:

```bash
xcodebuild \
  -project WindowManager.xcodeproj \
  -scheme WindowManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

Если Xcode выбирает несколько destination для Apple Silicon и Intel, это нормально; можно явно указать `arch=arm64` или `arch=x86_64` при необходимости.

## Возможные направления развития

- Экспорт/импорт раскладок в JSON.
- Редактирование сохранённой раскладки без пересохранения.
- Более устойчивое сопоставление окон: bundle identifier, process identifier, AXRole, AXSubrole.
- Автозапуск приложений, отсутствующих при восстановлении.
- Горячие клавиши для сохранения и применения раскладок.
- Поддержка исключений: не сохранять/не восстанавливать конкретные приложения или окна.
- Отображение визуальной схемы экранов и окон перед сохранением.
