# Sistema de Evaluación Adaptativa de Aspirantes a Practicantes
**Área de Innovación (Software y Sistemas) · Documento de diseño para sustentación académica**

> Cada decisión técnica va acompañada de su **porqué**. Los archivos citados existen en este repositorio y están probados.

---

## 0. Visión general y decisiones de arquitectura

```
 ┌──────────────────────┐        ┌────────────────────────────── SUPABASE ──────────────────────────────┐
 │ App móvil (Kotlin)   │  JWT   │  Auth ANÓNIMA ──► usuarios (rol aspirante)                            │
 │ ASPIRANTE + "Bit"    ├───────►│  Edge Functions (Deno/TS, service_role)                               │
 │ • nombre + carrera   │        │    clasificar-carrera ─► palabras clave / Gemini (lista cerrada)       │
 │                      │        │    iniciar-evaluacion ─► asigna 5 semillas DE SU CARRERA              │
 │ • 20 preguntas       │        │    siguiente-pregunta ─► motor adaptativo ─► Gemini ─► VALIDADOR ─┐  │
 │ • "Proceso           │        │                                         (2 fallos) ─► BANCO FIJO ─┤  │
 │   completado"        │        │    finalizar-evaluacion ─► calcular_resultado() ─► Gemini (retro) │  │
 └──────────────────────┘        │  PostgreSQL + RLS                                                 ▼  │
                                 │    respuestas (INSERT) ─► trigger califica ─► trigger semilla ─► ALERTA │
                                 │    resultados / alertas / preguntas  ◄── solo docente/admin           │
                                 └───────────────────────────────────────────────────────────────────────┘
                                                  Gemini API (gratis) ◄── la clave NUNCA sale del servidor
```

| Decisión | Alternativa descartada | Justificación |
|---|---|---|
| **App móvil en Kotlin + Jetpack Compose** | Flutter (plan inicial) | El proyecto se creó en Android Studio con la plantilla oficial de Compose. Es el stack **nativo y recomendado por Google** para Android, no requiere instalar otro SDK ni aprender Dart, y Supabase tiene SDK para Kotlin (`supabase-kt`, MIT). Como el público objetivo usa Android, el beneficio multiplataforma de Flutter no compensa una segunda cadena de herramientas. |
| **Solo app Android (sin aplicación web)** | App móvil + panel web | El alcance se centra en la experiencia del aspirante. Los resultados quedan guardados y protegidos en Supabase, y el docente los consulta desde el panel de Supabase. Así hay una sola aplicación que construir, probar y sustentar. |
| **Aspirante sin login ni registro** (sesión anónima de Supabase) | Cuentas con correo y contraseña | El aspirante solo escribe su nombre y su carrera. Por debajo, Supabase le crea una **identidad anónima** con su propio JWT. Así la RLS sigue funcionando igual: solo puede insertar SUS respuestas y nunca leer resultados. La sesión queda guardada en el teléfono, así que si cierra la app retoma donde iba y no puede repetir la prueba en ese dispositivo. |
| **Cronómetro por pregunta medido por el SERVIDOR** | Contar el tiempo solo en la app | La app muestra la cuenta regresiva, pero quien decide es la base de datos. Guarda `mostrada_en` la primera vez que entrega la pregunta y el trigger de calificación marca como **incorrecta y `tiempo_agotado`** cualquier respuesta que llegue después del límite (+8 s de margen por la red). Cerrar y reabrir la app o cambiar la hora del celular no da tiempo extra. |
| **Mascota pixel art "Bit"** dibujada con código (Canvas) | Imágenes PNG o GIF | Es un diseño propio (sin derechos de terceros), pesa casi nada y escala nítido. Anima respiración, parpadeo y saludo. Sus tips son de **estrategia y ánimo**: nunca revelan si una respuesta fue correcta. |
| **Supabase** (Postgres + Auth + Edge Functions) | Backend propio en Node/Django | Auth, BD y funciones *serverless* en el plan gratuito. La seguridad se declara en SQL (RLS) y es **auditable**: se puede mostrar a un tutor. |
| **Lógica sensible en el servidor** | Lógica en la app | Un APK se puede descompilar. Si la app conociera la respuesta correcta o el puntaje, el aspirante podría verlos. Por eso **la app solo recibe enunciado y opciones**. |
| **Calificación con trigger SQL** | Calificar en la app o en la Edge Function | El trigger corre siempre, sin importar desde dónde se inserte la respuesta, e **ignora** cualquier `es_correcta` que mande el cliente. |
| **Gemini API (gratis)** solo para rellenar plantillas y redactar retroalimentación | IA que genera preguntas libres | Requisito: *la IA no inventa estructura*. Con plantillas + validador + banco de respaldo el sistema **funciona aunque la IA falle o se agote la cuota**. |
| **Python** para el banco y la validación offline | Hacerlo a mano en SQL | Python valida el banco, **ejecuta el código** de las preguntas para comprobar que la opción marcada es la salida real y genera `seed.sql`. Así el banco nunca entra roto a producción. |

---

## PARTE 1 · Las 5 plantillas JSON

Archivos: [`plantillas/`](../plantillas)

| Plantilla | Tipo | Áreas permitidas | Formato de respuesta |
|---|---|---|---|
| `PL-OM-01` | opcion_multiple | las 4 | `{"opcion":"B"}` |
| `PL-CS-01` | codigo_salida | lógica, programación, BD | `{"opcion":"A"}` |
| `PL-CC-01` | completar_codigo | lógica, programación, BD | `{"opcion":"C"}` |
| `PL-CP-01` | caso_practico | actitud, programación, BD | `{"opcion":"B"}` |
| `PL-VF-01` | verdadero_falso_justificado | las 4 | `{"valor":false,"justificacion":"A"}` |

Cada plantilla trae: `id_plantilla`, `area`, `tema`, `nivel`, `tipo`, `estructura` (con `"___"` donde escribe la IA), `restricciones` y `ejemplo_salida`.

**Decisiones de diseño:**
1. **`area`, `tema` y `nivel` los fija el motor adaptativo**, no la IA. En la estructura aparecen como `{{area}}`, `{{tema}}` y `{{nivel}}` y el backend los reemplaza antes de enviar el prompt. La IA solo ve `"___"`.
2. **Todas las preguntas se califican de forma objetiva**, incluso el caso práctico y el V/F justificado. Eso permite exigir *exactamente una correcta* y calificar automáticamente sin otra IA que juzgue.
3. **V/F justificado:** cuenta como correcta solo si acierta el valor **y** la justificación. La probabilidad de acertar al azar baja de 1/2 a 1/6.
4. **completar_codigo** marca su hueco como `[[HUECO]]` y no como `___`, para no confundirlo con un campo que debe rellenar la IA.
5. **Catálogo cerrado de temas** ([`catalogo_temas.json`](../plantillas/catalogo_temas.json)): 23 temas en 4 áreas, cada uno con `nivel_minimo` y `palabras_clave`. Así la IA no puede proponer temas nuevos.

---

## PARTE 2 · Prompt exacto para Gemini

Archivo: [`supabase/functions/_shared/prompt.ts`](../supabase/functions/_shared/prompt.ts)

El prompt tiene dos capas:
- **Instrucción de sistema fija (`SISTEMA_GENERADOR`):** define el rol (*"generador de preguntas, NO inventas estructura"*) y 12 reglas estrictas: solo JSON, una sola correcta, sin "todas las anteriores", código determinista, sin datos reales, etc.
- **Mensaje por solicitud (`promptGenerarPregunta`):**
  1. La plantilla con `area`, `tema` y `nivel` ya fijados.
  2. Sus restricciones.
  3. El ejemplo de salida, marcado como *"no lo copies"*.
  4. Los parámetros del motor.
  5. El contexto **anónimo** del aspirante: nivel detectado, resultado de las semillas, debilidades y últimas 5 respuestas.
  6. La lista de preguntas ya usadas.
  7. Los errores del validador, si es el segundo intento.
  8. *"Devuelve SOLO el JSON"*.

Garantías técnicas adicionales:
- `responseMimeType: "application/json"` obliga a Gemini a responder JSON.
- Si el validador rechaza el primer intento, **sus errores se reenvían** a Gemini para que los corrija en el segundo.
- Después de validar, el backend **baraja las opciones** (Fisher-Yates), porque los LLM tienden a poner la correcta en la "A". Por eso el prompt prohíbe mencionar letras en la explicación.
- **Privacidad:** a Gemini nunca se le envían nombre, correo ni identificadores del aspirante.

La retroalimentación para el docente usa `SISTEMA_RETROALIMENTACION`. Gemini recibe métricas ya calculadas por SQL y **no puede alterar el puntaje**: solo redacta el resumen, 3 recomendaciones, un plan de práctica y una pregunta sugerida para la entrevista.

---

## PARTE 3 · Validador (dos versiones gemelas)

| Versión | Archivo | Uso |
|---|---|---|
| TypeScript | [`_shared/validador.ts`](../supabase/functions/_shared/validador.ts) | Producción (Edge Function) |
| Python | [`python_scripts/validador.py`](../python_scripts/validador.py) | Offline: banco fijo, pruebas y notebooks |

| # | Regla | Cómo se verifica |
|---|---|---|
| 1 | Estructura completa | Campos obligatorios, mismas claves que el molde, sin campos extra, sin `"___"`, lenguaje permitido, exactamente un `[[HUECO]]` |
| 2 | Exactamente una correcta | La letra existe, hay N opciones, **no hay opciones repetidas** (normalizadas) y no hay frases prohibidas (comparadas por palabra completa) |
| 3 | Tema obligatorio | El área está permitida para el tipo, el tema existe en el catálogo, el texto contiene una palabra clave del tema y coincide con lo pedido por el motor |
| 4 | Longitud | Rangos por campo (`restricciones.longitud`) |
| 5 | No repetida | SHA-256 del texto normalizado (minúsculas, sin tildes, sin espacios dobles) comparado con las preguntas ya vistas por el aspirante |
| 6 | Coherencia con el nivel | Nivel 1–3 igual al pedido, ≥ `nivel_minimo` del tema y **líneas de código dentro del rango del nivel** (N1: 1–6, N2: 2–12, N3: 3–20) |
| + | Ejecución (solo Python) | Ejecuta el código de las preguntas `codigo_salida` en Python con `python -I` y un tiempo límite de 3 s, y compara la salida real con la opción correcta |

**Evidencia:** 19 pruebas unitarias en Python y 8 pruebas en Deno, que incluyen la paridad: el validador TS acepta exactamente las mismas 60 preguntas que el Python. Durante el desarrollo el validador detectó **dos errores reales** en el banco escrito a mano.

---

## PARTE 4 · Las 5 preguntas semilla (según la carrera)

Archivos: [`banco/semillas.json`](../banco/semillas.json) (10 preguntas) y [`banco/carreras.json`](../banco/carreras.json) (qué 5 usa cada carrera).

La IA interpreta la carrera que escribe el aspirante y la ubica en un **catálogo cerrado**. Cada carrera tiene sus **5 semillas** y un **reparto de las 15 preguntas adaptativas** por área:

| Carrera | Semillas (orden) | Reparto adaptativo (lóg / prog / BD / act) |
|---|---|---|
| Ingeniería de Sistemas | SEM-01, 02, 03, 04, 05 | 4 / 4 / 4 / 3 |
| Ingeniería de Software | SEM-06, 02, 07, 04, 05 | 3 / 6 / 3 / 3 |
| Tecnología en Desarrollo de Software | SEM-01, 08, 09, 02, 05 | 4 / 5 / 3 / 3 |
| Otra carrera afín | SEM-01, 08, 09, 10, 05 | 5 / 4 / 3 / 3 |

| Semilla | Área / tema | Nivel | Tipo | Qué mide |
|---|---|---|---|---|
| SEM-01 | lógica / secuencias | 1 | opción múltiple | Razonamiento inductivo sin lenguaje de programación (calentamiento) |
| SEM-02 | programación / ciclos | 2 | código-salida | Traza mental de un ciclo con `continue` y un acumulador |
| SEM-03 | BD / agregación | 2 | completar código | WHERE vs HAVING: separa quien memoriza de quien entiende |
| SEM-04 | programación / recursión | 3 | V/F justificado | Abstracción y justificación (pregunta difícil) |
| SEM-05 | actitud / aprendizaje autónomo | 2 | caso práctico | Reacción ante lo desconocido (está en todas las carreras) |
| SEM-06 | lógica / proposicional | 1 | opción múltiple | Implicación lógica, base de las condiciones |
| SEM-07 | programación / POO | 2 | código-salida | Herencia y sobrescritura (clave en Ing. de Software) |
| SEM-08 | programación / condicionales | 1 | código-salida | Lectura de un `if/else` simple |
| SEM-09 | BD / SELECT | 1 | completar código | SQL mínimo: `SELECT *` |
| SEM-10 | lógica / deductivo | 2 | opción múltiple | *Modus tollens* en contexto cotidiano |

Las carreras tecnológicas y afines reciben semillas **más básicas** (tres de nivel 1), para que la alerta de nivel bajo sea justa con cada perfil.

- **Nivel inicial:** 5 aciertos → N3 (ALTO); 3–4 → N2 (MEDIO); 0–2 → N1 (BAJO).
- **Alerta de nivel bajo:** si falla **3 o más de las 5**, el trigger `evaluar_semilla()` inserta una fila en `alertas`, que solo puede leer el docente. Ocurre **en la base de datos y en el mismo instante** en que se envía la quinta respuesta, sin depender de la app.
- **Estilo de razonamiento:** cada opción de las semillas tiene un rasgo (`analitico`, `memoristico`, `impulsivo`, `proactivo`…). El docente ve el conteo, por ejemplo `{"analitico":3,"memoristico":1,"proactivo":1}`.
- Las semillas **no se barajan**, para que los rasgos y la comparación entre aspirantes sean consistentes.

---

## PARTE 5 · Flujo completo

### Aspirante (app Kotlin): sin login ni registro
```
Intro: Bit saluda ─► "¿Cómo te llamas?" ─► (sesión anónima invisible)
   ─► "¿Qué carrera estudias?" texto libre ─► POST clasificar-carrera (palabras clave → Gemini → "otra_afin")
        (o toca una carrera sugerida)        ─► Bit confirma: "Estudias Ingeniería de Software, ¿es correcto?"
   ─► POST iniciar-evaluacion {nombre, carrera}  (crea evaluación + asigna las 5 semillas de esa carrera)
   ─► loop 20 veces:
        POST siguiente-pregunta ─► muestra 1 pregunta (sin respuesta, nivel ni tema) + Bit da tips en la esquina
        INSERT respuestas       ─► trigger califica (el aspirante no puede leerla)
   ─► POST finalizar-evaluacion ─► Bit agradece ─► "Proceso completado. Valida con tu profesor." ─► Salir
Al reabrir la app: POST iniciar-evaluacion {reanudar} ─► continúa la pregunta pendiente o muestra el final.
```

### Motor adaptativo, preguntas 6 a 20 ([`motor_adaptativo.ts`](../supabase/functions/_shared/motor_adaptativo.ts))
1. **Nivel:** parte del nivel de las semillas. **2 aciertos seguidos suben** un nivel y **2 fallos seguidos lo bajan**. Pedir una racha de 2 evita que un acierto por azar dispare la dificultad (histéresis).
2. **Área:** la que tenga más cupo pendiente según el reparto de la **carrera** (por ejemplo, Software tiene 6 de programación). Si hay empate, la más débil.
3. **Tema:** primero los temas débiles (< 50 % de acierto), luego los no evaluados y al final los fuertes. No se repite el tema inmediato anterior y ningún tema se pregunta más de 3 veces.
4. **Tipo:** el menos usado entre las plantillas compatibles con el área, sin repetir el tipo anterior.
5. **Generación:** Gemini → validador. Si falla, segundo intento con los errores. Si vuelve a fallar → **banco fijo**, relajando criterios en orden: tema+nivel → nivel → nivel ±1 → área → cualquiera. Cada intento queda registrado en `eventos_ia`.

### Revisión del docente (en el panel de Supabase)
No hay aplicación web. El docente o el admin entran a **supabase.com → Table Editor** y revisan estas tablas:
- `alertas`: aspirantes con nivel BAJO en las semillas. Se puede marcar `atendida` y agregar una `nota_docente`.
- `resultados`: puntaje, fortalezas, debilidades, recomendaciones de la IA y estilo de razonamiento.
- `usuarios` + `aspirantes`: nombre y carrera de cada aspirante.
- `respuestas` + `preguntas_generadas`: historial pregunta por pregunta (correcta, tiempo, tiempo agotado, origen IA/banco).

Desde el Table Editor también se puede exportar cualquier tabla a CSV.

---

## PARTE 6 · Modelo de datos y RLS

Archivos: [`supabase/migrations/`](../supabase/migrations) · Pruebas: [`supabase/tests/pruebas_rls.sql`](../supabase/tests/pruebas_rls.sql)

| Tabla | Propósito | Aspirante | Docente | Admin |
|---|---|---|---|---|
| `usuarios` | Espejo de `auth.users` con el **rol** y el nombre (el aspirante es anónimo: sin email) | lee su fila | lee todas | todo |
| `aspirantes` | Carrera elegida y texto que escribió | lee y edita el suyo | lee | todo |
| `carreras` | Catálogo de carreras con su reparto por área | lee las activas | lee | todo |
| `semillas_carrera` | Las 5 semillas de cada carrera | — | lee | todo |
| `temas`, `plantillas`, `banco_preguntas_fijo` | Catálogos (contienen respuestas) | — | lee | todo |
| `evaluaciones` | Estado y progreso (sin notas) | lee la suya | lee | todo |
| `preguntas_generadas` | Preguntas asignadas, **con la respuesta correcta** | — (usa la vista segura) | lee | todo |
| `v_preguntas_aspirante` | **Vista** con solo `id, orden, tipo, contenido, respondida` | lee las suyas | — | — |
| `respuestas` | Lo único que escribe el aspirante | **solo INSERT** | lee | todo |
| `resultados` | Puntaje, fortalezas, debilidades, recomendaciones | — | lee | todo |
| `alertas` | Nivel bajo en semillas | — | lee y marca atendida | todo |
| `eventos_ia` | Auditoría de la IA | — | lee | todo |

**Por qué el aspirante no puede ver sus resultados "ni por API":**
1. Con **RLS activado y sin política**, una tabla es invisible. `resultados` y `alertas` no tienen ninguna política para el aspirante.
2. `respuestas` permite INSERT pero **no SELECT**: el aspirante escribe y no puede leer `es_correcta`.
3. Las preguntas solo se exponen a través de una **vista sin columnas sensibles**, filtrada por `auth.uid()`.
4. El rol vive en `usuarios` y **solo el admin puede hacer UPDATE**: un aspirante no puede ascenderse a docente. Todo usuario nuevo nace como aspirante (trigger).
5. Las funciones `calcular_resultado` y `evaluar_semilla` tienen `REVOKE EXECUTE`, así que no se pueden invocar por `/rpc`.
6. `pruebas_rls.sql` **demuestra** todo lo anterior suplantando a un aspirante y a un docente ficticios. Termina en `ROLLBACK`, así que no deja datos.

**Tiempo límite** (migración `0004_tiempo_limite.sql` y [`_shared/tiempos.ts`](../supabase/functions/_shared/tiempos.ts)):

| Tipo | Segundos |
|---|---|
| Opción múltiple | 60 |
| V/F justificado | 75 |
| Caso práctico | 90 |
| Completar código | 100 |
| Código-salida | 120 |

Depende del **tipo** y no del nivel, para que el cronómetro no le revele al aspirante su dificultad. Al llegar a 0, la app envía lo que esté marcado (o nada) y pasa sola a la siguiente; una pregunta sin responder cuenta como incorrecta. El docente ve qué respuestas fueron por tiempo agotado.

**Puntaje:** ponderado por nivel (una pregunta N3 vale el triple que una N1): `100 × Σ(nivel de las acertadas) / Σ(nivel de todas)`. **Fortaleza:** tema con ≥ 70 % de acierto y al menos 2 preguntas. **Debilidad:** tema con < 50 %.

---

## PARTE 7 · Pantallas y diseño visual

**Referencia visual:** *Task Management & To-Do List App* (Figma Community).

| Token | Color | Uso |
|---|---|---|
| Violeta | `#5F33E1` | Botones principales, progreso, selección |
| Violeta suave | `#EDE8FF` | Chips y tarjetas seleccionables |
| Lavanda | `#F7F5FF` | Fondo de pantalla |
| Rosa / Naranja / Azul | `#F478B8` / `#FF9142` / `#0087FF` | Acentos por área (actitud / BD / lógica) |
| Texto | `#24252C` / `#6E6A7C` | Principal / secundario |

Las formas son redondeadas (16–24 dp) y el botón principal ocupa todo el ancho, con 56 dp de alto. La fuente de la referencia es *Lexend Deca* (licencia OFL); por ahora se usa la del sistema.

### App móvil del aspirante (Kotlin, ya implementada en `app/src/main/java/com/dji/myapplication/`)
| # | Pantalla | Contenido |
|---|---|---|
| 1 | Intro | Bit grande con globo de diálogo, título y "¡Vamos!" |
| 2 | Nombre | Bit pregunta "¿Cómo te llamas?" y aparece un campo de texto |
| 3 | Carrera | Bit pregunta la carrera. Texto libre que interpreta la IA, o carreras sugeridas para tocar |
| 4 | Confirmar carrera | Bit confirma lo que entendió y muestra las reglas. Botones "Sí, empezar" y "No, quiero corregirla" |
| 5 | Pregunta | "Pregunta X de 20", progreso, **cronómetro circular** (violeta → naranja bajo el 40 % → rojo y latiendo en los últimos 10 s; al llegar a 0 pasa sola), contexto, enunciado, bloque de código y opciones A–D (o V/F + "¿Por qué?"). **Bit en la esquina** da tips y, al tocarlo, da otro. **Botón atrás bloqueado.** Nunca indica si acertó |
| 6 | Final | Bit agradece. **"Proceso completado. Valida con tu profesor."** y "Salir" |

**Bit** ([`Mascota.kt`](../app/src/main/java/com/dji/myapplication/ui/mascota/Mascota.kt), [`Tips.kt`](../app/src/main/java/com/dji/myapplication/ui/mascota/Tips.kt)):
- Es un sprite de 18×25 píxeles dibujado con `Canvas`.
- **Animaciones:** respira (sube y baja 1 píxel), parpadea al azar cada 2,5 a 4,5 s y levanta el brazo mientras habla.
- **Cuándo habla en las preguntas:**
  - En momentos clave: la 1 ("las primeras 5 me ayudan a conocerte"), la 6 ("ahora se ajustan a tu ritmo"), la mitad, cuando quedan 3 y la última.
  - Cada tres preguntas da un tip según el tipo de pregunta.
  - Con el cronómetro: a mitad de tiempo, en los últimos 10 segundos y cuando se acaba ("¡Se acabó el tiempo! Vamos con la siguiente.").
  - Al tocarlo da otro tip.
- **Regla de diseño:** ningún mensaje depende de si el aspirante acertó.

Arquitectura: `MainActivity` → `AppAspirante` → **máquina de estados** (`Pantalla`) en `EvaluacionViewModel` → `EvaluacionRepositorio` (Supabase). No se usa una librería de navegación: con un flujo lineal, un `when` sobre un estado sellado es más fácil de explicar y probar.

---

## PARTE 8 · Cronograma (6 meses)

| Mes | Entregables | Estado |
|---|---|---|
| **1** · Investigación y diseño | Requisitos, este documento, modelo de datos, proyecto Supabase, RLS | ✅ Diseño y SQL listos; falta crear el proyecto en Supabase |
| **2** · Plantillas y banco | 5 plantillas, catálogo, 5 semillas, banco ≥ 50 (Python + validación por ejecución). Meta: 100 preguntas con revisión por pares | ✅ 50 + 5 listas · 🔲 ampliar a 100 |
| **3** · Backend e IA | Edge Functions, motor adaptativo, Gemini, retroalimentación, pruebas RLS | ✅ Código listo y verificado · 🔲 desplegar y probar con Gemini real |
| **4** · App móvil | Kotlin + Compose: entrada sin login, carrera por IA, mascota Bit, 6 pantallas, APK de prueba | ✅ Compila y abre en el emulador · 🔲 prueba completa contra Supabase |
| **5** · Contenido y robustez | Ampliar el banco a 100 preguntas, ajustar tiempos y umbrales, manejo sin conexión, pruebas en celulares reales | 🔲 |
| **6** · Pruebas y cierre | Piloto con 5–10 aspirantes ficticios, ajuste de umbrales, manual de usuario, presentación | 🔲 |

---

## PARTE 9 · Estructura de carpetas

```
APP_E/
├── app/                         ← App móvil del ASPIRANTE (Kotlin + Jetpack Compose)
│   └── src/main/java/com/dji/myapplication/
│       ├── MainActivity.kt
│       ├── data/                Modelos.kt, EvaluacionRepositorio.kt (Supabase, sesión anónima)
│       └── ui/                  AppAspirante.kt, EvaluacionViewModel.kt,
│                                pantallas/ · componentes/ · mascota/ (Bit) · theme/
│   (detalle de cada archivo en ESTRUCTURA.md)
├── gradle/, build.gradle.kts    ← Configuración Android (no mover: Android Studio abre APP_E)
├── supabase/
│   ├── migrations/              001 esquema · 002 funciones/triggers · 003 RLS · 004 tiempo límite
│   ├── INSTALAR_TODO.sql        Las 4 migraciones + seed en un solo archivo (python_scripts/armar_instalador.py)
│   ├── seed.sql                 GENERADO por python_scripts/generar_seed.py
│   ├── tests/pruebas_rls.sql    Evidencia de seguridad
│   └── functions/
│       ├── _shared/             validador.ts, motor_adaptativo.ts, prompt.ts, gemini.ts, carreras.ts, supabase.ts
│       ├── clasificar-carrera/  iniciar-evaluacion/  siguiente-pregunta/  finalizar-evaluacion/
│       └── tests/               Pruebas Deno (paridad del validador + motor)
├── plantillas/                  5 plantillas JSON + catalogo_temas.json  (fuente de verdad)
├── banco/                       semillas.json (10) + banco_fijo.json (50) + carreras.json  (escrito por humanos)
├── python_scripts/              validador.py, generar_seed.py, tests/
└── docs/                        Este documento + PUESTA_EN_MARCHA.md
```
