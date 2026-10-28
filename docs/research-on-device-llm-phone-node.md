# Локальные LLM и телефон как вычислительная нода для TyLog

> Статус: техническое исследование и план проверки.  
> Проверено: 19 октября 2026 года.  
> Главный принцип: ниже отдельно указаны подтверждённые факты, инженерные оценки и то, что необходимо измерить на физических телефонах.

## 1. Короткий ответ

Запустить LLM на телефоне можно тремя разными способами:

1. **LLM внутри TyLog** — модель выполняется непосредственно в приложении, без сети.
2. **Телефон как локальный сервер** — Android foreground service держит модель в памяти и предоставляет API другим устройствам в локальной сети.
3. **Несколько устройств как система** — одна нода выбирается для выполнения запроса либо модель физически делится между нодами.

Для TyLog реалистичен такой порядок:

- сначала локальный inference на одном телефоне;
- затем RAG по заметкам TyLog;
- затем добровольно включаемый LAN-режим «телефон как нода»;
- discovery и распределение запросов — только после рабочего LAN-прототипа;
- split inference, libp2p, IPFS и mesh не нужны в первой версии.

Для **Huawei P30** и **Samsung Galaxy A24** безопасный исходный вариант — **`llama.cpp` + GGUF + CPU + модель 0.6–1.7B в Q4**. Он не требует GMS и не зависит от закрытого NPU SDK. Модель 3B можно проверить, но не принимать заранее за интерактивно пригодную. 7B для этих устройств не является разумным baseline.

**Нельзя честно назвать tok/s, расход батареи или максимальный контекст P30/A24 без физического измерения.** Найденные публикации показывают общую реализуемость и методы оптимизации, но не заменяют испытание конкретного SoC, версии Android, охлаждения и объёма доступной RAM.

---

## 2. Что уже есть в TyLog

Репозиторий TyLog уже содержит большую часть необходимой архитектурной основы:

- Flutter/Dart UI;
- Rust через `flutter_rust_bridge`;
- локальный inference embeddings через ONNX Runtime;
- platform-specific `cfg` и stub для неподдерживаемых платформ;
- один загруженный экземпляр модели, защищённый глобальным mutex;
- локальный semantic search и FTS;
- явная загрузка моделей пользователем.

Следовательно, генеративную модель не надо встраивать как отдельную подсистему приложения. Минимальное расширение:

```text
Flutter UI
   │
flutter_rust_bridge
   │
Rust orchestration
   ├── existing embedding/search
   └── generation backend
         ├── Android: llama.cpp / GGUF
         └── macOS: llama.cpp Metal или MLX
```

Рекомендованный новый слой — `generation.rs` рядом с существующим embedding-кодом. Один экземпляр модели и одна очередь генерации предпочтительнее параллельных копий: на телефоне ограничителем будет RAM, а не конкурентность запросов.

Не следует переиспользовать embedding-модель как генеративную. Embeddings, retrieval и generation — разные модели и разные вычислительные задачи.

---

## 3. Что означает «телефон как нода»

Термин охватывает четыре существенно разные архитектуры.

### 3.1 Автономная нода

Все данные и вычисления находятся на одном телефоне:

```text
заметки → chunks → embeddings/index → retrieval → prompt → local LLM → ответ
```

Преимущества:

- работа без интернета;
- содержимое заметок не покидает устройство;
- нет обязательного облачного провайдера;
- предсказуемая доступность;
- отсутствие оплаты за каждый запрос.

Ограничения:

- качество малой модели ниже крупной облачной;
- нагрев и расход батареи;
- ограничение RAM и KV-cache;
- более низкая скорость prefill и generation;
- модель занимает сотни мегабайт или несколько гигабайт.

Это наиболее полезный и наименее сложный вариант для TyLog.

### 3.2 Телефон как LAN inference server

Телефон запускает foreground service и слушает только локальный интерфейс:

```text
ноутбук / другой телефон
          │ HTTPS или HTTP в доверенной LAN
          ▼
 Android foreground service
          │
     local LLM runtime
```

Минимальный контракт:

```text
GET  /health
GET  /v1/models
POST /v1/chat/completions
```

OpenAI-compatible JSON полезен не из-за OpenAI, а как уже сложившийся переносимый контракт. TyLog сможет одинаково обращаться к модели внутри процесса, к телефону в LAN и к домашнему серверу.

Обязательные меры:

- сервер выключен по умолчанию;
- явное включение пользователем;
- foreground notification;
- bind на выбранный LAN-адрес, не на публичный интерфейс;
- pairing и токен с возможностью отзыва;
- TLS либо доверенная изолированная сеть;
- ограничение размера prompt, concurrency и времени запроса;
- отображение температуры, батареи и активных клиентов;
- остановка при критическом нагреве или низком заряде.

### 3.3 Пул независимых нод

Модель не делится. Каждое устройство объявляет возможности, а scheduler выбирает ноду:

```text
node A: Qwen 0.6B, battery 70%, busy=false
node B: Qwen 1.7B, charging=true, busy=true
node C: desktop 7B, available=true
```

Это проще и устойчивее настоящего distributed inference. Для TyLog это разумный второй сетевой этап:

- discovery: ручной адрес, затем mDNS/DNS-SD;
- capability advertisement;
- выбор по модели, RAM, температуре, заряду и занятости;
- данные отправляются только выбранной ноде;
- при отсутствии нод запрос остаётся локальным.

### 3.4 Модель разделена между телефонами

Pipeline/model parallelism распределяет слои или нейроны между устройствами. Это соответствует идее коллективных вычислений, но имеет тяжёлые ограничения:

- каждый токен создаёт последовательную сетевую зависимость;
- Wi-Fi latency и разрывы соединения замедляют весь pipeline;
- heterogeneous устройства создают straggler problem;
- нужно распределять model shards и согласовывать версии;
- промежуточные activations тоже могут раскрывать информацию;
- отказ одной ноды останавливает генерацию;
- сложность значительно выше, чем у пула независимых серверов.

**Вывод:** для TyLog сначала нужен пул независимых нод. Физическое разделение одной модели — исследовательский эксперимент, а не первая продуктовая архитектура.

---

## 4. Рантаймы

### 4.1 `llama.cpp`

**Рекомендованный baseline для Android.**

Почему:

- ARM64 CPU;
- GGUF и широкий выбор квантизаций;
- Android можно собирать без GMS;
- один формат модели для Android/macOS/Linux;
- Metal на macOS;
- зрелый CLI/server полезен для предварительных испытаний;
- контролируемые context, threads, batch и memory mapping.

Цена:

- JNI/C ABI или тонкая Rust-обёртка;
- производительность CPU зависит от конкретного SoC;
- GPU/Vulkan не гарантирует выигрыш на старых Mali;
- NPU обычно не используется автоматически.

Источник: https://github.com/ggml-org/llama.cpp

### 4.2 LiteRT-LM / Google AI Edge

Перспективный Android runtime с CPU/GPU/NPU backend и готовыми путями для поддерживаемых моделей.

Подходит, когда:

- целевые устройства входят в реально проверенную матрицу;
- модель доступна в поддерживаемом формате;
- GPU/NPU delegate даёт измеримый выигрыш;
- допустима зависимость от Android/Google AI Edge stack.

Не следует выбирать его единственным runtime для P30 до реального испытания. Наличие NPU в спецификации SoC не означает, что delegate поддерживает все операции конкретного transformer.

Источники:

- https://ai.google.dev/edge/litert-lm/overview
- https://ai.google.dev/edge/litert-lm/android

### 4.3 ExecuTorch

Уместен при PyTorch-first pipeline и необходимости экспортировать собственные модели в `.pte`. Имеет mobile backends и vendor integrations, но для TyLog добавляет второй модельный toolchain без доказанной необходимости.

Источник: https://docs.pytorch.org/executorch/stable/

### 4.4 ONNX Runtime GenAI

Архитектурно близок существующему ONNX-пути TyLog. Может быть полезен, если выбранная модель и execution provider хорошо поддерживаются. Однако существование ONNX Runtime в проекте не делает ORT GenAI автоматически самым коротким путём: генеративные модели, KV-cache, tokenizer и operator coverage требуют отдельной проверки.

Источник: https://github.com/microsoft/onnxruntime-genai

### 4.5 MLC LLM

Компилирует модели под разные GPU/backend. Полезен для оптимизированных сборок и современных устройств, но создаёт build matrix «модель × quantization × target». До измеримого недостатка `llama.cpp` это лишняя сложность.

Источник: https://github.com/mlc-ai/mlc-llm

### 4.6 MNN и NCNN

Лёгкие mobile inference engines с ARM/GPU оптимизациями. Их стоит сравнить отдельным benchmark только после CPU-baseline. Переход оправдан, если на P30/A24 они дают устойчивое улучшение при той же модели и качестве.

Источники:

- https://github.com/alibaba/MNN
- https://github.com/Tencent/ncnn

### 4.7 MLX

Сильный вариант для Apple Silicon/macOS благодаря unified memory и Metal. Для TyLog на macOS разумны два варианта:

- тот же GGUF/`llama.cpp`, чтобы минимизировать форматы;
- MLX, если измеренный выигрыш оправдает отдельный backend.

Источник: https://github.com/ml-explore/mlx

### Решение по runtime

| Цель | Первый выбор | Когда менять |
|---|---|---|
| Huawei P30 | `llama.cpp`, CPU, GGUF | только после benchmark MNN/LiteRT delegate |
| Galaxy A24 | `llama.cpp`, CPU, GGUF | если Vulkan/LiteRT/MNN доказуемо быстрее и стабильны |
| macOS Apple Silicon | `llama.cpp` Metal | MLX при измеримом выигрыше |
| Современный Android flagship | `llama.cpp` или LiteRT-LM | выбор по одинаковому benchmark |
| LAN API | тонкий сервер над тем же backend | не вводить второй inference engine |

---

## 5. Какие модели проверять

Для P30/A24 нужен не «лучший leaderboard model», а минимальная модель, которая:

- выполняет конкретные функции TyLog;
- понимает русский, английский и португальский;
- имеет приемлемую лицензию;
- конвертируется в GGUF;
- не вызывает OOM с практическим контекстом;
- сохраняет интерактивную скорость после нагрева.

### Кандидаты

| Модель | Роль в испытании | Комментарий |
|---|---|---|
| **Qwen3 0.6B Instruct, Q4** | минимальный smoke test | малый footprint; проверяет весь pipeline |
| **Gemma 3 1B IT, Q4** | компактный multilingual baseline | хороший кандидат для summarization и rewriting |
| **Qwen2.5 1.5B Instruct, Q4** | основной консервативный кандидат | multilingual; зрелые GGUF-конверсии |
| **Qwen3 1.7B, Q4** | основной современный кандидат | проверить качество/скорость против Qwen2.5 |
| **Llama 3.2 1B Instruct, Q4** | контрольный baseline | сравнение runtime; языковое качество проверять отдельно |
| **Qwen2.5 3B / Qwen3 4B, Q4** | верхняя граница, не baseline | только если 1–1.7B недостаточно качественны |

Не надо скачивать все модели в TyLog. Phase 0 использует внешнюю test harness и выбирает максимум две модели для приложения.

### Память

Теоретическая нижняя граница только для 4-bit весов:

| Параметры | 4-bit веса, без overhead |
|---:|---:|
| 0.6B | 0.30 GB |
| 1.0B | 0.50 GB |
| 1.7B | 0.85 GB |
| 3.0B | 1.50 GB |
| 4.0B | 2.00 GB |
| 7.0B | 3.50 GB |

Реальный GGUF и runtime RAM больше. Дополнительно требуются:

- tensors, которые остались в более высокой точности;
- metadata и tokenizer;
- runtime buffers;
- prompt/evaluation buffers;
- KV-cache;
- память Flutter, Rust, базы и ОС.

Поэтому «модель весит 1 GB» не означает «ей достаточно 1 GB RAM».

### Контекст и KV-cache

Заявленный максимум context модели — не практический мобильный target. Для первого испытания:

- 1K tokens — базовый сценарий;
- 2K — нормальный target;
- 4K — верхняя исходная точка;
- больше — только после замера RAM, latency и качества retrieval.

TyLog уже может извлекать релевантные фрагменты. Хороший retrieval обычно полезнее, чем помещение всей базы заметок в prompt.

---

## 6. Реалистичные функции TyLog

Малая локальная модель подходит для ограниченных преобразований:

- заголовок и краткое резюме заметки;
- извлечение тегов, задач, дат и сущностей;
- переписывание и сокращение;
- перевод коротких фрагментов;
- ответ по нескольким найденным заметкам с цитатами;
- нормализация текста перед Typst;
- локальная классификация и routing;
- генерация поискового запроса.

Не стоит обещать:

- надёжный сложный reasoning уровня крупных облачных моделей;
- длинный автономный research;
- корректные ответы без retrieval/citations;
- обработку всей базы в одном prompt;
- постоянный background inference без влияния на батарею.

### Минимальный RAG для TyLog

```text
1. пользователь задаёт вопрос
2. существующий local search возвращает top-k chunks
3. TyLog формирует короткий prompt
4. local LLM получает только эти chunks
5. ответ содержит IDs исходных заметок
6. UI открывает цитату по ID
```

Полезные ограничения:

- `top-k` 3–6;
- строгий budget prompt;
- требование «если данных нет — сообщи»;
- citations генерируются из retrieval metadata, а не из свободного текста модели;
- streaming ответа;
- cancellation;
- один generation job одновременно.

---

## 7. Децентрализация: точные тезисы

### 7.1 Что действительно децентрализуется

On-device LLM устраняет обязательный центральный inference provider. Пользователь контролирует:

- модель;
- данные;
- вычислительное устройство;
- доступ к API;
- срок хранения контекста;
- возможность работать офлайн.

Но одна локальная модель ещё не создаёт распределённую систему. Корректное различие:

| Термин | Что происходит |
|---|---|
| local computing | вычисление на устройстве пользователя |
| edge computing | вычисление рядом с источником данных |
| peer-to-peer | ноды соединяются без обязательного центрального relay |
| federated learning | ноды совместно обучают модель, не передавая сырые данные |
| federated inference | запрос/вычисление распределяется между независимыми нодами |
| split inference | части одной модели выполняются на разных узлах |
| distributed inference | inference использует ресурсы нескольких узлов |
| decentralized storage | данные адресуются/реплицируются между несколькими владельцами |

Эти понятия нельзя смешивать в одном утверждении.

### 7.2 Сильный тезис для работы

> Смартфон способен быть автономной edge-нódой персональной вычислительной среды: хранить приватный корпус, выполнять retrieval и малую генеративную модель локально, а при явном согласии предоставлять стандартизированный inference API соседним устройствам. Децентрализация здесь достигается прежде всего устранением обязательного облачного посредника; распределение одной модели между телефонами является отдельной оптимизационной задачей.

### 7.3 Ограничения тезиса

- модельные файлы обычно всё равно распространяются через централизованные registries;
- обновления и подписи требуют trust model;
- локальный API не становится безопасным только потому, что находится в LAN;
- metadata, prompts и activations могут раскрывать информацию;
- маленькая локальная модель может требовать cloud fallback;
- энергопотребление переносится с дата-центра на пользовательское устройство;
- старые телефоны могут поддерживать автономность, но не высокую throughput.

---

## 8. Научная и инженерная база

Ниже — наиболее полезные первичные публикации, сохранённые локально в каталоге `articles` и добавленные в канонический `thesis/references.bib`.

### 8.1 MobileLLM

**MobileLLM: Optimizing Sub-billion Parameter Language Models for On-Device Use Cases**  
Liu et al., 2024, arXiv:2402.14905.

Значение: показывает, что sub-billion models требуют архитектурной оптимизации, а не только уменьшения большой модели. Полезно для обоснования отдельного класса on-device SLM.

Локально: `articles/liu-2024-mobilellm-optimizing-sub-billion-parameter-language-models.pdf`

### 8.2 MELTing Point

**MELTing Point: Mobile Evaluation of Language Transformers**  
Laskaridis et al., 2024, arXiv:2403.12844.

Значение: методика оценки language models на реальных мобильных устройствах; latency, energy, memory и platform variability. Это основание не переносить чужой tok/s на P30/A24.

Локально: `articles/laskaridis-2024-melting-point-mobile-evaluation-of-language-transformers.pdf`

### 8.3 PowerInfer-2

**PowerInfer-2: Fast Large Language Model Inference on a Smartphone**  
Xue et al., 2024, arXiv:2406.06282.

Значение: heterogeneous CPU/NPU execution и работа с ограниченной памятью/хранилищем. Доказывает возможность сложной оптимизации smartphone inference, но не означает, что реализация переносима на Kirin 980 или Helio G99.

Локально: `articles/xue-2024-powerinfer-2-fast-large-language-model-inference-on-a-smartphone.pdf`

### 8.4 LinguaLinked

**LinguaLinked: A Distributed Large Language Model Inference System for Mobile Devices**  
Zhao et al., 2023, arXiv:2312.00388.

Значение: partitioning модели между mobile devices с учётом network и memory constraints. Это основной источник для раздела о телефонах как совместно работающих inference-нódах.

Локально: `articles/zhao-2023-lingualinked-distributed-llm-inference-for-mobile-devices.pdf`

### 8.5 LLM in a Flash

**LLM in a Flash: Efficient Large Language Model Inference with Limited Memory**  
Alizadeh et al., 2023, arXiv:2312.11514.

Значение: inference модели, не помещающейся полностью в DRAM, с использованием flash storage и exploitation sparsity. Полезно как метод, но требует runtime-level реализации; это не функция, которую TyLog должен писать самостоятельно.

Локально: `articles/alizadeh-2023-llm-in-a-flash-efficient-inference-with-limited-memory.pdf`

### 8.6 LLM as a System Service

**LLM as a System Service on Mobile Devices**  
Yin et al., 2024, arXiv:2403.11805.

Значение: модель как общий системный сервис вместо отдельной копии в каждом приложении; переиспользование модели и KV state. Прямо поддерживает архитектуру phone-node/foreground service.

Локально: `articles/yin-2024-llm-as-a-system-service-on-mobile-devices.pdf`

### 8.7 Qwen3 Technical Report

**Qwen3 Technical Report**  
Yang et al., 2025, arXiv:2505.09388.

Значение: модельная база для современных компактных Qwen3, multilingual capabilities и model family. Для продукта всё равно требуется отдельная проверка конкретного checkpoint и quantization.

Локально: `articles/yang-2025-qwen3-technical-report.pdf`

### 8.8 Официальная документация

- `llama.cpp`: https://github.com/ggml-org/llama.cpp
- LiteRT-LM overview: https://ai.google.dev/edge/litert-lm/overview
- LiteRT-LM Android: https://ai.google.dev/edge/litert-lm/android
- Gemma 3 model card: https://ai.google.dev/gemma/docs/core/model_card_3
- Android foreground services: https://developer.android.com/develop/background-work/services/fgs
- Android NSD/mDNS: https://developer.android.com/develop/connectivity/wifi/use-nsd
- ExecuTorch: https://docs.pytorch.org/executorch/stable/
- ONNX Runtime GenAI: https://github.com/microsoft/onnxruntime-genai
- MLC LLM: https://github.com/mlc-ai/mlc-llm

---

## 9. Эксперимент: что измерять на P30 и A24

### 9.1 Test matrix

Минимальная матрица:

```text
devices:
  - Huawei P30 / Kirin 980
  - Samsung Galaxy A24 / Helio G99

models:
  - Qwen3 0.6B Q4
  - Gemma 3 1B Q4
  - один из Qwen2.5 1.5B Q4 или Qwen3 1.7B Q4

contexts:
  - 1024
  - 2048
  - 4096 только если стабильно

runtime:
  - llama.cpp CPU baseline
```

Не добавлять сразу Vulkan, MNN, LiteRT и ONNX. Сначала одна воспроизводимая точка. Второй backend нужен только для сравнения с baseline.

### 9.2 Метрики

Для каждого сочетания:

- версия телефона, Android/EMUI и RAM;
- точное имя файла модели и SHA-256;
- размер файла;
- время холодной загрузки;
- время тёплой загрузки;
- peak RSS/PSS;
- prompt processing tokens/s;
- time to first token;
- generation tokens/s;
- температура до и после;
- частоты CPU и признаки throttling;
- расход батареи за фиксированный 15- или 30-минутный сценарий;
- число OOM/crash;
- качество на фиксированном ru/en/pt наборе;
- правильность citations в RAG;
- поведение после выключения экрана — отдельно для server mode.

### 9.3 Нагрузки

Нужны три воспроизводимых сценария:

1. **Короткое преобразование** — 300-token prompt, 100-token answer.
2. **RAG** — 1500-token prompt, 250-token answer.
3. **Непрерывная генерация** — 15 минут для thermal steady state.

Один и тот же prompt запускается не менее трёх раз после warm-up. Холодный запуск измеряется отдельно.

### 9.4 Критерии решения

Предлагаемые, но продуктово изменяемые пороги:

- модель загружается без риска OOM;
- UI не блокируется;
- отмена запроса работает;
- TTFT приемлем для выбранной функции;
- скорость не падает катастрофически после прогрева;
- 30-минутный node mode не падает;
- ответы по заметкам содержат проверяемые source IDs;
- модель даёт полезное качество на русском и португальском;
- размер модели приемлем для добровольной загрузки.

Численный порог tok/s не следует задавать до первого измерения: summarization, tagging и чат имеют разные UX-требования.

---

## 10. Поэтапная реализация

### Phase 0 — без изменения TyLog

- собрать или установить `llama.cpp` test runner для arm64 Android;
- проверить три модели на P30/A24;
- сохранить raw benchmark logs;
- выбрать одну основную и одну резервную модель;
- решить, оправдана ли вообще генерация на этих телефонах.

**Выход:** таблица измерений и решение go/no-go.

### Phase 1 — локальная генерация внутри TyLog

- тонкая Rust-обёртка над выбранным backend;
- `load`, `generate_stream`, `cancel`, `unload`;
- один model instance и одна очередь;
- явная загрузка модели;
- ограниченные функции: summary/tags/rewrite;
- streaming и cancellation;
- никаких server/mesh функций.

**Выход:** offline generation на одном устройстве.

### Phase 2 — локальный RAG

- существующий retrieval;
- prompt budget;
- top-k chunks;
- citations по ID заметок;
- фиксированный evaluation set ru/en/pt;
- сравнение с cloud baseline.

**Выход:** приватные ответы по заметкам.

### Phase 3 — телефон как LAN-нода

- foreground service;
- health/models/chat endpoints;
- pairing/authentication;
- private-interface binding;
- лимиты prompt/concurrency;
- thermal/battery stop conditions;
- ручное добавление IP в TyLog.

**Выход:** одна безопасно управляемая phone-node.

### Phase 4 — discovery и scheduler

- mDNS/DNS-SD;
- capabilities;
- выбор доступной ноды;
- failover;
- ручной fallback при блокировке multicast.

**Выход:** пул независимых нод.

### Phase 5 — только исследовательский

- LinguaLinked-подобное partitioning;
- split inference;
- libp2p transport;
- content-addressed model distribution;
- federated optimization.

Переходить сюда только при доказанной потребности, которую не решает пул независимых inference servers.

---

## 11. Риски

| Риск | Что делать |
|---|---|
| OOM | Q4, 0.6–1.7B, короткий context, preflight memory check |
| KV-cache растёт с context | retrieval и prompt budget вместо длинного prompt |
| Нагрев и throttling | steady-state benchmark, thermal stop, node mode у зарядки |
| Расход батареи | explicit mode, battery threshold, не запускать постоянно |
| Нет GMS/неработающий delegate | CPU/GGUF baseline без Google-зависимости |
| Android убивает процесс | foreground service; не обещать daemon без notification |
| LAN endpoint доступен постороннему | pairing, auth, bind policy, TLS/isolated LAN |
| Prompt содержит приватные данные | local by default, явный выбор remote node |
| Малая модель галлюцинирует | retrieval, source IDs, constrained tasks, cloud fallback |
| Model supply-chain | hashes, manifests, license, signed update metadata |
| Разные backend дают разные outputs | фиксированный evaluation corpus и version pinning |
| Mesh усложняет продукт | не внедрять до измеримой необходимости |

---

## 12. Итоговое решение

Для TyLog локальная LLM **технически возможна уже на текущей архитектурной базе**. На Huawei P30 и Galaxy A24 разумно начинать с `llama.cpp`, GGUF, CPU, Q4 и моделей 0.6–1.7B. Это минимальный переносимый путь, не зависящий от GMS и vendor NPU.

Первый полезный продукт — не «децентрализованная сеть LLM», а:

```text
локальный поиск TyLog
+ малая локальная генерация
+ цитаты на заметки
+ необязательный LAN API
```

Телефон как нода реалистичен в форме явно включаемого foreground service. Пул независимых нод практичнее разделения одной модели. Split inference и mesh имеют научную ценность, но должны оставаться отдельной экспериментальной фазой.

Следующее действие — не писать интеграционный код, а выполнить Phase 0 на физических P30 и A24. Только эти измерения дадут честные значения скорости, RAM, батареи и нагрева и позволят выбрать модель для TyLog.
