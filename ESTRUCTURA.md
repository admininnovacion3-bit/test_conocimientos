# Estructura del proyecto APP_E

Guía para entender **cómo está organizado** el proyecto y **qué hace cada archivo**.

El proyecto tiene dos partes que trabajan juntas:

| Parte | Tecnología | Dónde está | Quién la usa |
|---|---|---|---|
| **App móvil del aspirante** | Kotlin + Jetpack Compose (Android Studio) | `app/` | El aspirante, en su celular |
| **Servidor (backend)** | Supabase: PostgreSQL + Edge Functions en TypeScript | `supabase/` | La app, por internet |

Además hay **datos escritos por humanos** (`plantillas/`, `banco/`) y **scripts de Python** (`python_scripts/`) que los validan y los convierten en SQL.

> **Para abrir la app:** en Android Studio abre la carpeta **`APP_E`** (la raíz), no `app/`. Gradle solo compila `app/`; las demás carpetas no le afectan.

---

## 1. Mapa general

```
APP_E/
├── app/                    ← APP ANDROID (Kotlin). Lo que se instala en el celular
├── gradle/                 ← Versiones de librerías y wrapper de Gradle
├── supabase/               ← SERVIDOR: base de datos, seguridad y funciones
├── plantillas/             ← Moldes JSON que la IA rellena + catálogo de temas
├── banco/                  ← Preguntas escritas por humanos + carreras
├── python_scripts/         ← Validan el banco y generan el SQL
├── docs/                   ← Diseño del sistema y guía de instalación
├── build.gradle.kts        ┐
├── settings.gradle.kts     │ Configuración de Gradle para todo el proyecto
├── gradle.properties       │
├── gradlew / gradlew.bat   ┘
├── local.properties        ← URL y clave PÚBLICA de Supabase (no se sube a git)
├── README.md               ← Resumen corto del proyecto
└── ESTRUCTURA.md           ← Este archivo
```

**Carpetas generadas automáticamente** (no se editan; se pueden borrar y se regeneran solas): `build/`, `app/build/`, `.gradle/`, `.kotlin/`, `.idea/`, `supabase/.temp/`.

---

## 2. Cómo viaja una pregunta

```
 CELULAR (app/)                                SERVIDOR (supabase/)
 ─────────────                                 ────────────────────
 PreguntaScreen  ──pide la siguiente──►  functions/siguiente-pregunta
                                            │  motor_adaptativo.ts  → elige área, tema, nivel y tipo
                                            │  prompt.ts + gemini.ts → la IA rellena una plantilla
                                            │  validador.ts          → revisa la pregunta (6 reglas)
                                            │  (si falla 2 veces)    → usa banco_preguntas_fijo
                 ◄── enunciado + opciones ──┘  (NUNCA la respuesta correcta)
 el aspirante elige y toca "Siguiente"
                 ──INSERT en respuestas──►  trigger calificar_respuesta() (SQL)
                                               califica, revisa el tiempo y guarda es_correcta
                                               (el aspirante NO puede leer ese resultado: RLS)
```

---

## 3. `app/`: la aplicación Android (Kotlin)

```
app/
├── build.gradle.kts                 Configuración del módulo: SDK, dependencias y lectura de local.properties
└── src/
    ├── main/
    │   ├── AndroidManifest.xml      Declara la app, su único permiso (INTERNET) y la pantalla inicial
    │   ├── res/                     Recursos: ícono, nombre de la app, tema base
    │   └── java/com/dji/myapplication/
    │       ├── MainActivity.kt
    │       ├── data/                ← DATOS: hablar con Supabase
    │       │   ├── Modelos.kt
    │       │   └── EvaluacionRepositorio.kt
    │       └── ui/                  ← INTERFAZ
    │           ├── AppAspirante.kt
    │           ├── EvaluacionViewModel.kt
    │           ├── pantallas/       ← una pantalla por archivo
    │           ├── componentes/     ← piezas visuales reutilizables
    │           ├── mascota/         ← Bit y sus mensajes
    │           └── theme/           ← colores, letras y formas
    └── test/java/com/dji/myapplication/   ← pruebas unitarias
```

### Arquitectura (MVVM simple)

```
Pantallas (Compose)  ──eventos──►  EvaluacionViewModel  ──llamadas──►  EvaluacionRepositorio  ──►  Supabase
       ▲                                   │
       └──────── estado (pantalla, error, tip) ◄┘
```

- **Las pantallas solo dibujan.** No contienen lógica de negocio: cuando el aspirante toca algo, llaman a una función del ViewModel.
- **El ViewModel decide** qué pantalla mostrar y guarda el estado.
- **El Repositorio** es el único que conoce Supabase.

### Archivo por archivo

| Archivo | Qué hace |
|---|---|
| **`MainActivity.kt`** | Punto de entrada de Android. Aplica el tema (`EvaluacionTheme`) y muestra `AppAspirante`. |
| **`data/Modelos.kt`** | Clases de datos que llegan del servidor o se envían a él: `PreguntaAspirante` (enunciado, opciones, código, tiempo límite y tiempo restante), `Carrera`, `ClasificacionCarrera`, `IniciarRespuesta`, `SiguienteRespuesta` y `NuevaRespuesta`. **No existe ningún campo para la respuesta correcta**, así que la app no puede mostrarla. |
| **`data/EvaluacionRepositorio.kt`** | Única puerta hacia Supabase. Crea la **sesión anónima** (el aspirante no hace login), lee la lista de carreras, llama a las 4 Edge Functions e inserta las respuestas. |
| **`ui/AppAspirante.kt`** | Raíz de la interfaz: según el estado del ViewModel muestra la pantalla que toca, con una transición suave. |
| **`ui/EvaluacionViewModel.kt`** | **Cerebro de la app.** Define las pantallas posibles (`Pantalla`: Cargando, Intro, Nombre, ElegirCarrera, ConfirmarCarrera, Pregunta, Final) y las acciones: `confirmarNombre`, `interpretarCarrera`, `empezar`, `responder` y los tips de Bit. Al abrir la app retoma la evaluación si había una en curso. También evita enviar dos veces la misma respuesta. |

#### `ui/pantallas/`: lo que ve el aspirante, en orden

| Archivo | Pantalla |
|---|---|
| `IntroScreen.kt` | 1. Bit se presenta. Botón "¡Vamos!". |
| `NombreScreen.kt` | 2. "¿Cómo te llamas?". Al continuar se crea la sesión anónima. |
| `CarreraScreen.kt` | 3. "¿Qué carrera estudias?": texto libre que interpreta la IA, o carreras sugeridas. **4.** Confirmación de la carrera con las reglas de la prueba. |
| `PreguntaScreen.kt` | 5. Una pregunta: progreso, **cronómetro**, enunciado, bloque de código, opciones A–D (o Verdadero/Falso + "¿Por qué?") y Bit en la esquina. Si el tiempo llega a 0, envía lo marcado y pasa a la siguiente. El botón "atrás" está bloqueado. |
| `FinalScreen.kt` | 6. "Proceso completado. Valida con tu profesor." **Nunca muestra puntaje.** |

#### `ui/componentes/Componentes.kt`: piezas reutilizables

| Pieza | Uso |
|---|---|
| `BotonPrincipal` | Botón violeta de ancho completo (con indicador de carga). |
| `TarjetaOpcion` | Cada opción A, B, C, D de una pregunta. |
| `BloqueCodigo` | Código en fondo oscuro con letra monoespaciada; muestra `[[HUECO]]` como `______`. |
| `ChipSeleccion` | Botones "Verdadero" y "Falso". |
| `Cronometro` | Anillo con los segundos: violeta, naranja bajo el 40 % y rojo latiendo en los últimos 10 s. |
| `MensajeError` | Caja roja con mensajes de error. |
| `EspacioVertical` | Separación estándar de 12 dp entre elementos. |

#### `ui/mascota/`: Bit

| Archivo | Qué hace |
|---|---|
| `Mascota.kt` | Dibuja a **Bit** píxel por píxel con `Canvas`, a partir de una matriz de letras (cada letra es un color). Anima respiración, parpadeo y saludo. También contiene `GloboDialogo` (globo de texto), `GuiaEnEsquina` (Bit pequeño con tips durante las preguntas) y `EscenaBit` (Bit grande en las pantallas iniciales). |
| `Tips.kt` | Textos de Bit: hitos (pregunta 1, 6, mitad, últimas), tips según el tipo de pregunta y avisos del cronómetro. **Regla:** ningún mensaje revela si el aspirante acertó. |

#### `ui/theme/`: identidad visual

| Archivo | Qué hace |
|---|---|
| `Color.kt` | Paleta tomada de la referencia de Figma (violeta `#5F33E1`, lavanda, naranja…). |
| `Theme.kt` | `EvaluacionTheme`: aplica colores y formas redondeadas a toda la app. |
| `Type.kt` | Tamaños y pesos de letra. |

#### `res/`: recursos de Android

| Archivo o carpeta | Qué es |
|---|---|
| `values/strings.xml` | Nombre visible de la app: "Evaluación Innovación". |
| `values/themes.xml` | Tema base de Android (`Theme.EvaluacionAspirantes`) que se ve antes de que cargue Compose. |
| `drawable/ic_launcher_*.xml`, `mipmap-*/` | Ícono de la app en todas las densidades de pantalla. |
| `xml/backup_rules.xml`, `xml/data_extraction_rules.xml` | Reglas de copia de seguridad de Android (exigidas por el manifiesto). |

#### `test/`: pruebas unitarias

Se ejecutan con `./gradlew :app:testDebugUnitTest`, o con clic derecho → *Run* en Android Studio.

| Archivo | Qué comprueba |
|---|---|
| `ModelosTest.kt` | Que el JSON del servidor se interprete bien (opciones ordenadas, V/F, valores por defecto) y que la app no guarde una respuesta correcta aunque llegue por error. |
| `TipsTest.kt` | Que ningún mensaje de Bit delate si el aspirante acertó, y que los avisos del cronómetro y los hitos aparezcan cuando deben. |

---

## 4. Configuración de Gradle (raíz)

| Archivo | Qué hace |
|---|---|
| `settings.gradle.kts` | Nombre del proyecto (`EvaluacionAspirantes`), repositorios y módulos incluidos (solo `:app`). |
| `build.gradle.kts` | Declara los plugins (Android, Compose, serialización JSON). |
| `gradle/libs.versions.toml` | **Catálogo de versiones**: todas las librerías y sus versiones en un solo lugar (Compose, Supabase, Ktor, JUnit). |
| `gradle.properties` | Opciones de Gradle (memoria, estilo de código). |
| `gradle/wrapper/`, `gradlew`, `gradlew.bat` | El *wrapper*: descarga y usa siempre la misma versión de Gradle. |
| `gradle/gradle-daemon-jvm.properties` | Versión de Java que usa Gradle. |
| `local.properties` | Ruta del SDK de Android + `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`. **No se sube a git.** La clave *secreta* de Supabase nunca va aquí. |
| `.gitignore`, `app/.gitignore` | Archivos que git debe ignorar (compilados, claves locales, cachés). |

---

## 5. `supabase/`: el servidor

```
supabase/
├── migrations/          ← SQL que crea la base de datos, en orden
├── functions/           ← Edge Functions (TypeScript/Deno) que llama la app
├── tests/pruebas_rls.sql
├── seed.sql             ← GENERADO: datos iniciales
└── INSTALAR_TODO.sql    ← GENERADO: migraciones + seed en un solo archivo
```

### `migrations/`: la base de datos

| Archivo | Qué crea |
|---|---|
| `…0001_esquema.sql` | Las tablas: `usuarios`, `aspirantes`, `carreras`, `temas`, `plantillas`, `banco_preguntas_fijo`, `semillas_carrera`, `evaluaciones`, `preguntas_generadas`, `respuestas`, `resultados`, `alertas` y `eventos_ia`. |
| `…0002_funciones_triggers.sql` | Lógica dentro de la BD: alta automática de usuarios como *aspirante*, **calificación** de cada respuesta, **alerta de nivel BAJO** (3 o más fallos en las 5 semillas) y cálculo del resultado final. |
| `…0003_rls.sql` | **Seguridad (Row Level Security):** el aspirante solo puede insertar sus respuestas y leer sus preguntas sin la respuesta correcta; nunca resultados ni alertas. El docente y el admin pueden leer todo. |
| `…0004_tiempo_limite.sql` | **Cronómetro del lado del servidor:** guarda cuándo se mostró cada pregunta y rechaza las respuestas tardías. |

### `functions/`: lo que la app llama por internet

| Función | Qué hace |
|---|---|
| `clasificar-carrera/` | Recibe la carrera escrita por el aspirante y la ubica en el catálogo: primero por palabras clave y, si es ambiguo, con Gemini sobre una lista cerrada. |
| `iniciar-evaluacion/` | Guarda nombre y carrera, crea la evaluación y le asigna las 5 semillas de su carrera. También permite **reanudar** al reabrir la app. |
| `siguiente-pregunta/` | Entrega la pregunta pendiente o genera la siguiente (motor adaptativo, luego IA, luego validador; si falla, banco fijo). Devuelve el tiempo restante según el reloj del servidor. |
| `finalizar-evaluacion/` | Calcula el resultado, pide a Gemini la retroalimentación **para el docente** y cierra la evaluación. |

| `_shared/` (código común) | Qué hace |
|---|---|
| `supabase.ts` | Cliente con privilegios de servidor e identificación de quién llama (desde su sesión). |
| `motor_adaptativo.ts` | Decide área, tema, nivel y tipo de la siguiente pregunta: 2 aciertos seguidos suben el nivel y 2 fallos seguidos lo bajan. |
| `validador.ts` | Revisa cada pregunta de la IA con 6 reglas (estructura, una sola correcta, tema, longitud, no repetida, nivel) y baraja las opciones. |
| `prompt.ts` | Textos exactos que se envían a Gemini (generar pregunta, clasificar carrera, retroalimentación). |
| `gemini.ts` | Llamada HTTP a la API de Gemini; pide respuesta en JSON. |
| `carreras.ts` | Clasificación de la carrera por palabras clave (sin IA). |
| `tiempos.ts` | Tiempo límite por tipo de pregunta (60 a 120 s) y cálculo del tiempo restante. |
| `tests/validador_motor_test.ts` | 8 pruebas: el validador TS acepta las mismas 60 preguntas que el de Python, más pruebas del motor y de la clasificación de carreras. |

### Otros

| Archivo | Qué hace |
|---|---|
| `tests/pruebas_rls.sql` | Demuestra la seguridad: suplanta a un aspirante y a un docente ficticios y comprueba qué puede ver cada uno. Termina en `ROLLBACK`, así que no deja datos. |
| `seed.sql` | **Generado** por `python_scripts/generar_seed.py`: temas, plantillas, carreras y preguntas. |
| `INSTALAR_TODO.sql` | **Generado** por `python_scripts/armar_instalador.py`: todo junto para pegarlo una vez en el SQL Editor. |

---

## 6. `plantillas/` y `banco/`: el contenido (escrito por humanos)

| Archivo | Qué contiene |
|---|---|
| `plantillas/PL-OM-01_opcion_multiple.json` | Molde de pregunta de opción múltiple. |
| `plantillas/PL-CS-01_codigo_salida.json` | Molde "¿qué imprime este código?". |
| `plantillas/PL-CC-01_completar_codigo.json` | Molde "completa el `[[HUECO]]`". |
| `plantillas/PL-CP-01_caso_practico.json` | Molde de situación de trabajo (actitud). |
| `plantillas/PL-VF-01_verdadero_falso_justificado.json` | Molde de verdadero/falso con justificación. |
| `plantillas/catalogo_temas.json` | Los 23 temas permitidos en 4 áreas, con nivel mínimo y palabras clave. |
| `banco/semillas.json` | 10 preguntas semilla (cada carrera usa 5). |
| `banco/banco_fijo.json` | 50 preguntas de respaldo para cuando la IA falla. |
| `banco/carreras.json` | Las 4 carreras: sus 5 semillas y cuántas preguntas adaptativas van a cada área. |

Cada plantilla tiene campos `"___"` que la IA rellena; **la IA nunca inventa la estructura**.

---

## 7. `python_scripts/`: herramientas offline

| Archivo | Qué hace | Cómo se usa |
|---|---|---|
| `validador.py` | Las mismas 6 reglas del validador TS. Además **ejecuta el código Python** de las preguntas para comprobar que la opción marcada como correcta es la salida real. | `python python_scripts/validador.py banco/banco_fijo.json` |
| `generar_seed.py` | Valida todo el contenido y, solo si no hay errores, genera `supabase/seed.sql`. | `python python_scripts/generar_seed.py` |
| `armar_instalador.py` | Une las migraciones y el seed en `supabase/INSTALAR_TODO.sql`. | `python python_scripts/armar_instalador.py` |
| `tests/test_validador.py` | 19 pruebas del validador. | `python -m unittest discover -s python_scripts/tests` |

---

## 8. `docs/`

| Archivo | Contenido |
|---|---|
| `DISENO_SISTEMA.md` | Documento de sustentación: decisiones técnicas con su justificación, plantillas, prompt, validador, semillas, flujos, modelo de datos, pantallas y cronograma. |
| `PUESTA_EN_MARCHA.md` | Pasos para instalar Supabase, desplegar funciones, configurar la app y ejecutar las pruebas. |

---

## 9. ¿Dónde cambio…?

| Si quieres… | Edita… |
|---|---|
| Un texto o el diseño de una pantalla | `app/…/ui/pantallas/<Pantalla>.kt` |
| Colores de la app | `app/…/ui/theme/Color.kt` |
| Lo que dice Bit | `app/…/ui/mascota/Tips.kt` |
| El dibujo de Bit | Las matrices `QUIETO` y `SALUDO` en `app/…/ui/mascota/Mascota.kt` |
| El tiempo de cada tipo de pregunta | `supabase/functions/_shared/tiempos.ts` y luego desplegar `siguiente-pregunta` e `iniciar-evaluacion` |
| Agregar preguntas al banco | `banco/banco_fijo.json` → `generar_seed.py` → ejecutar `seed.sql` en Supabase |
| Agregar una carrera | `banco/carreras.json` → `generar_seed.py` → ejecutar `seed.sql` |
| Cómo sube o baja la dificultad | `supabase/functions/_shared/motor_adaptativo.ts` |
| Qué ve cada rol en la BD | `supabase/migrations/…0003_rls.sql` (con una migración nueva) |
| La URL o la clave pública de Supabase | `local.properties` |
