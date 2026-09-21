# cri — глибоке code review

Дата: baseline review

## Статус remediation

Перший remediation pass виконано:

- додано `Cri::PathSecurity` для canonical path authorization;
- built-in filesystem tools, permission checks і `file.read` тепер блокують existing symlink escapes;
- WASM3 runtime оновлює memory pointer/size після guest calls, зокрема після `alloc` і `cri_call`;
- додано regression tests для symlink escapes та safe missing write targets;
- plugin package extraction тепер перевіряє entry types, duplicate/traversal paths, entry count і uncompressed size, а також виконує лише одну extraction pass у тимчасову директорію;
- HTTP effects тепер мають connect/read timeouts, request/response size limits і не follow-ять redirects;
- TUI mutations тепер перевіряють panel→buffer references, відхиляють duplicate panel IDs, не залишають orphan buffer при collision і коректно переносять focus після panel removal;
- `Ctrl-E`/`Ctrl-Y` тепер проходять повний decoder→keymap→action шлях, а Prompt submit перевіряє focused panel context;
- cursor movement тепер auto-scroll-ить focused panel, а TUI має базовий Visual mode, selection range і host clipboard/OSC52 yank;
- перший Plugin UI vertical slice готовий: `[[ui.actions]]` → host ActionRegistry → serialized context → WASM invoker → validated `ui.notification` → UiRuntime;
- `ui.buffer.create` тепер створює owner-namespaced buffer через host UI sink з ID/content limits;
- додано реальний Zig freestanding WASM fixture, який проходить `wasm3` від action до створеного buffer;
- real Zig fixture тепер також проходить `ui.buffer.append`, `ui.buffer.replace`, `ui.highlight.define`, `ui.highlight.set`, `ui.panel.open` і `ui.panel.focus` з owner/range/position validation;
- Agent loop тепер має bounded input, response, tool-call, argument і tool-result budgets;
- TUI model submissions запускаються в окремому Crystal fiber, тому input/render loop не блокується під час provider I/O; generic cancellation/deadline context ще pending.
- package install перевіряє compressed size та SHA-256 до/після extraction, щоб виявляти package replacement під час install;
- WASM cancellation не виділяється окремо: runtime має використовувати спільний execution/cancellation механізм host;
- додано мінімальний deny-by-default `CapabilityBroker` з fiber-aware `PendingApproval`, event-backed allow/deny і gate для effects та Host ToolRouter; model/provider capability не експонується;
- додано host-owned `Auth::Broker` з OpenAI API-token flow, opaque `CredentialRef` і декларативною конфігурацією Codex ChatGPT flows;
- додано власний versioned `$XDG_CONFIG_HOME/cri/auth.json` store з `0700/0600`, lock-файлом і atomic writes; pi/Codex credential files не імпортуються.

Цей документ зберігає baseline review; findings нижче не видаляються після виправлення, щоб залишалася audit history.

## Загальний висновок

Архітектурний фундамент хороший для прототипу: невелике ядро, абстракція provider, host-mediated effects, WASM без WASI, окремі buffer/panel/workspace, декларативний keymap.

До production-ready стану ще далеко. Основні проблеми:

- filesystem sandbox обходиться через symlink;
- WASM runtime може працювати із застарілим memory pointer;
- plugin package extraction недостатньо захищений;
- задокументований plugin UI API ще фактично не реалізований;
- TUI не має selection/yank, а кілька key bindings недосяжні;
- слабко захищені глобальні ID та інваріанти UI;
- є розрив між API документацією й реалізацією.

Тести проходять, але не покривають найнебезпечніші сценарії.

## Критичні findings

### 1. Filesystem sandbox обходиться через symlink

Файли: `src/cri/host_tools.cr`, `src/cri/permissions.cr`, `src/cri/effects/handler.cr`.

Перевірка робиться через лексичний `File.expand_path`, а потім файл відкривається окремо. Symlink усередині дозволеного root може вести за межі root. Це стосується built-in `read_file`, plugin `file.read` і майбутніх filesystem effects.

Потрібен один `SafePathResolver`, який:

1. canonicalize root через `File.real_path`;
2. canonicalize existing target;
3. перевіряє containment canonical path;
4. для нових файлів canonicalize parent directory;
5. за потреби відхиляє symlink через `lstat`.

### 2. WASM memory pointer може стати невалідним після `cri_alloc`

Файл: `src/cri/wasm/wasm3_runtime.cr`.

Memory pointer кешується, потім викликається guest allocator, який потенційно може виконати `memory.grow`, і host записує request у стару область. Memory оновлюється після `cri_call`, але не після `cri_alloc`.

Потрібно refresh-ити memory pointer і size після кожного guest call, який може змінити memory.

## Високий пріоритет

### 3. Plugin package extraction допускає небезпечні tar entries і decompression bomb

Файл: `src/cri/plugin_package.cr`.

Перевіряються імена, але не типи entries, symlink/hardlink targets, device/FIFO entries, extracted size і кількість entries.

Потрібно дозволити тільки regular files/directories, обмежити кількість entries і сумарний uncompressed size, а також перевіряти дерево після extraction.

### 4. Effect HTTP не має достатнього timeout і response limit

Файл: `src/cri/effects/handler.cr`.

HTTP effect використовує transport без явного connect/read timeout і max response bytes. Дозволений host може зависнути або повернути необмежений body.

Потрібен окремий testable HTTP gateway із timeout, byte limit, redirect policy та cancellation.

### 5. Plugin UI API поки існує лише в документації

`docs/plugin-ui-api.md` описує manifest actions, host adapters і `ui.*` effects, але manifest parser, registry, action bridge і effect mutations ще не завершені.

Потрібен вертикальний slice:

```text
manifest action
→ host adapter
→ WASM call
→ validated UI effect
→ UiRuntime mutation
```

### 6. UI stores не захищають ID та referential integrity

Проблеми: мовчазний overwrite buffers/panels, дублювання panel ID у layout, dangling panel після видалення buffer, невикористаний owner.

Потрібні typed/qualified IDs, collision errors, ownership checks, `BufferInUse` policy та транзакційний UI mutation validator.

### 7. Read-only cursor є, але selection/copy ще немає

Немає Visual mode, selection anchor/head, selected range, yank/copy action або clipboard abstraction. Cursor належить `TextBuffer`, тому два views одного buffer не можуть мати незалежні cursors.

Правильна майбутня модель:

```text
BufferView
  cursor
  selection
  scroll
  mode
```

### 8. `Ctrl-E` і `Ctrl-Y` bindings недосяжні

Keymap має bindings, але decoder не має відповідних key variants і відкидає control bytes.

Потрібен decoder-to-keymap integration test.

### 9. Enter і `x` у NORMAL впливають на Prompt незалежно від focused panel

Глобальні bindings викликають `input.submit`/`input.clear`, навіть якщо focus на read-only panel. Actions мають перевіряти panel capability або бути context-scoped.

## Середній пріоритет

### 10. Cursor не приводить viewport за собою

Коли cursor виходить за viewport, renderer повертає `nil`, але panel не scroll-иться. Потрібна `ensure_cursor_visible`.

### 11. Cursor/display geometry не підтримує реальну terminal width

Використовується `String#size`, що неправильно для wide CJK, combining characters, emoji і tabs. Потрібен display-width/grapheme layer.

### 12. EventHandler порушує Open/Closed principle

Центральний `case action` містить усі built-in actions, хоча вже існує `ActionRegistry`. Нові actions вимагають редагування central dispatcher.

### 13. Renderer має забагато відповідальностей

Layout, panel geometry, content rendering, styling, diff, cursor placement і terminal I/O змішані в одному класі. Варто виділити LayoutEngine, FrameComposer, TerminalDiff, AnsiBackend і CursorProjector.

### 14. Manifest parser — неповна власна реалізація TOML

Ручний parser не покриває повну TOML semantics: escapes, multiline values, comments, typed diagnostics. Краще використати TOML parser або формально описати обмежений grammar.

### 15. Tool schemas фактично відсутні

Extension tools рекламують загальну object schema без required arguments, types, enums і descriptions. Потрібна підтримка JSON Schema.

### 16. Silent collision policy у registries

Commands, tools, extensions, actions, buffers, workspaces і panels можуть мовчки перезаписуватися. Потрібна явна policy: reject, namespace або explicit override.

### 17. Event buses не ізолюють subscriber failures і не мають unsubscribe

Один subscriber може зупинити dispatch для наступних. Dynamic extensions також потребуватимуть unsubscribe tokens.

### 18. TUI application не має cancellation model

Provider request блокує event flow, не має cancellation token або request generation для відкидання late stream chunks.

### 19. OpenAI streaming приймає неповну відповідь як успішну

**Виправлено.** OpenAI SSE тепер вимагає `[DONE]`, відхиляє malformed JSON chunks і має regression tests для truncated/malformed streams.

## SOLID

### Single Responsibility

Добре розділені `Agent`, `Provider`, `Tool`, `Session`, `GrantStore`, `Panel`, `Buffer`, `Workspace`.

Порушення: `Renderer`, `EventHandler`, `EffectHandler`, `PluginTooling` мають надто багато відповідальностей.

### Open/Closed

Найслабше місце: нові effects, UI actions, key semantics і manifest sections вимагають редагувати центральні `case` statements. Потрібні реєстровані handlers.

### Liskov Substitution

Provider/runtime abstractions загалом працюють. Але fallback `complete_stream` має бути явно відрізнений від справжнього streaming.

### Interface Segregation

Provider і Runtime достатньо малі. Plugin UI SDK має отримувати вузькі capability interfaces, а не весь `UiRuntime`.

### Dependency Inversion

`Agent → Provider` і `Agent → ToolRouter` зроблені добре. Effect HTTP, filesystem, Process tooling і renderer напряму залежать від глобальних/static API, що ускладнює тестування.

## DRY

Основні повтори:

1. Path containment дублюється у built-in tools і permissions.
2. Є два подібні EventBus implementations.
3. Registry classes повторюють Hash/overwrite pattern.
4. Action dispatch розділений між EventHandler і ActionRegistry.
5. UI ownership validation не централізована.
6. Terminal geometry рахується окремо для rendering і cursor projection.

Ці повтори важливі не лише для стилю: вони можуть розходитися в security та invariant checks.

## Що вже зроблено добре

- WASM extensions не мають WASI/imports.
- Є gas, memory і effect-loop limits.
- Host-mediated effects — правильний напрямок.
- Permission request і grants розділені.
- Network matching має hostname boundaries.
- OpenAI client перевіряє HTTP status і має timeout.
- Agent має обмежений tool-call loop.
- TUI не робить full clear на кожен frame.
- Raw buffer text санітизується перед ANSI.
- Buffer/panel/workspace модель краща за монолітний terminal UI.

## Рекомендований порядок виправлень

### Етап 1 — security

1. `SafePathResolver` і symlink tests. **Зроблено.**
2. Refresh WASM memory після guest allocation. **Зроблено.**
3. Безпечна tar extraction policy. **Базовий hardening і post-extraction SHA-256 TOCTOU detection зроблено; external tar isolation ще follow-up.**
4. HTTP effect timeout і byte limit. **Зроблено.**
5. Collision/ownership checks для plugin resources. **Базові TUI collision/reference checks зроблено; plugin ownership ще follow-up.**

### Етап 2 — UI correctness

1. Виправити control-key decoder. **Зроблено для Ctrl-E/Ctrl-Y.**
2. Заборонити `input.submit/clear` поза Prompt context. **Submit захищено; окремого default `x` binding у поточній конфігурації немає.**
3. Додати cursor-follow scrolling. **Зроблено для вертикального viewport.**
4. Перенести cursor/selection/scroll у `BufferView`. **Свідомо відкладено: поточній моделі достатньо одного стану на shared `TextBuffer`; повертатися до цього лише за потреби незалежних views.**
5. Реалізувати Visual selection та yank/copy. **Зроблено базовий Visual/yank через host clipboard.**

### Етап 3 — plugin UI contract

1. Manifest `[[ui.actions]]`. **Зроблено.**
2. Host action adapter. **Зроблено.**
3. Serializable UI context. **Зроблено.**
4. Validated UI effect handlers. **Зроблено для `ui.notification`, buffer create/append/replace, highlight define/set, panel open/focus.**
5. Namespace/ownership enforcement. **Ще pending для UI resources.**
6. Zig SDK helpers. **Ще pending.**
7. End-to-end fixture. **Зроблено для реального Zig/WASM buffer/highlight effects; panel effects ще pending.**

### Етап 4 — maintainability

1. ActionRegistry як єдиний dispatcher.
2. Розділити Renderer.
3. Розділити EffectHandler за effect type.
4. Замінити custom TOML parser.
5. Додати JSON Schema для tools.
6. CI: format + default specs + wasm3 specs + security fixtures.

## Перші конкретні кроки

Першими виправляються boundary/security дефекти:

1. централізований canonical path resolver;
2. regression tests для traversal і symlink;
3. refresh WASM memory metadata після `cri_alloc`;
4. regression fixture для guest `memory.grow`.
