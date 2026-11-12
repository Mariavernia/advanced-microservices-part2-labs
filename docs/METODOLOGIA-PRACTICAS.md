# Cómo trabajamos en los laboratorios

> **Hacer, observar, razonar y corregir**. El objetivo no es ejecutar comandos hasta conseguir `PASS`, sino entender qué comportamiento del sistema demuestra cada prueba.

## Qué se automatiza y qué no

| Tipo | Herramientas | Uso durante la clase |
|---|---|---|
| Preparación del puesto | `scripts/login.sh`, `scripts/preflight.sh` | Al empezar o ante problemas de acceso, sin consumir el tiempo del laboratorio |
| Preparación técnica segura | Generadores de Secrets ficticios, datos de ejemplo o imágenes proporcionadas | Solo para tareas repetitivas ajenas al objetivo del módulo |
| **Trabajo principal** | YAML, `kubectl`, logs, EndpointSlices, SQL/Redis, HTTP, Git, CI | **Lo hace el alumno**, paso a paso y en su namespace |
| Comprobación final | `labs/*/scripts/verify.sh` | **Al terminar**: detecta errores, pero no sustituye la investigación |
| Recuperación/diagnóstico del instructor | Scripts `deploy.sh`, `cleanup.sh`, smoke tests | Utilidades de rescate y soporte; **no son el camino normal del alumno** |

Los scripts no son la solución del ejercicio. **Una salida PASS sin evidencias ni explicación no significa práctica completada.**

## El ciclo de cada actividad

1. **Predicción.** Antes de cambiar el sistema, indica qué esperas y por qué.
2. **Decisión o modificación.** Inspecciona el manifiesto, cambia el campo apropiado o aplica los recursos de forma progresiva.
3. **Observación.** Comprueba al menos dos señales distintas: respuesta HTTP, logs, objeto Kubernetes, eventos, métricas, ReplicaSets, etc.
4. **Diagnóstico.** Explica qué capa falla (cliente, Gateway, Service, DNS, aplicación, almacenamiento, Kubernetes) y qué evidencia descarta otras hipótesis.
5. **Recuperación.** Corrige y demuestra que el sistema vuelve a un estado funcional.
6. **Verificación.** Solo entonces ejecuta el verificador automatizado.

## Evidencia mínima por ejercicio

Registra un breve texto en tu propio repositorio o notas:

- **Predije**: qué sucedería y cuál era el motivo.
- **Cambié**: qué recurso/campo modificaste (sin copiar secretos ni tokens).
- **Observé**: salida o métrica concreta, con el comando o endpoint.
- **Concluyo**: qué concepto demuestra la evidencia y cuál es su limitación.

No hace falta un informe largo. Cuatro frases precisas y una o dos evidencias son preferibles a diez capturas sin interpretar.

## Si te quedas bloqueado

- Comprueba primero contexto y namespace, Pods, eventos y logs.
- Lee el apartado SUPPORT del laboratorio.
- Pide una pista sobre **qué mirar**, no un script que rehaga toda la práctica.
- Si el entorno se ha desconfigurado, el instructor puede utilizar herramientas de recuperación. Registra qué provocó el problema antes de continuar.

## Principios del curso

- El código de los servicios Java viene preparado cuando programarlo no es el objetivo del módulo; no es un ejercicio de sintaxis de Spring.
- Cada alumno opera en **su namespace**. No se alteran RBAC, políticas compartidas ni recursos de compañeros.
- Se prefieren cambios pequeños, reversibles y visibles antes que desplegar todos los componentes a la vez.
- Los fallos inducidos deben restaurarse antes de continuar al siguiente laboratorio.
- Los ejercicios avanzados opcionales no bloquean el recorrido principal.
