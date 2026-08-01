# RFC-004 — Gestión de incidente por saturación de capacidad en ECS

## 1. Contexto

A las `02:47 AM` se genera una alerta para el servicio `payments-processor` con las siguientes condiciones:

```text
ECS Capacity       = 10/10 tasks
Latency p99        > 4 seconds
```

El servicio alcanzó el `MaxCapacity` configurado en Application Auto Scaling y al mismo tiempo presenta un incremento significativo en la latencia.

Aunque ambas señales pueden estar relacionadas, no asumiría inicialmente que la falta de capacidad en ECS es la causa del problema. Antes de incrementar el límite de tareas, buscaría identificar dónde se está generando la degradación.

## 2. Gestión y diagnóstico del incidente

Al recibir la alerta, primero iniciaría formalmente el incidente en la plataforma utilizada por el equipo, cambiaría su estado a `IN PROGRESS` y revisaría en detalle la información disponible en la alerta.

Para este escenario partiría de las siguientes señales:

```text
Service       = payments-processor
ECS Capacity  = 10/10 tasks
Latency p99   > 4 seconds
Time          = 02:47 AM
```

A partir de ahí utilizaría la plataforma de observabilidad y las métricas disponibles en AWS para correlacionar infraestructura, aplicación y dependencias.

### 2.1 Validar métricas de infraestructura

Primero revisaría el estado de ECS para entender si existe realmente un problema de capacidad:

| Métrica | Qué buscaría validar |
| --- | --- |
| CPU / Memory | Si las tareas presentan saturación sostenida de recursos. |
| DesiredCount | Cuántas tareas está solicitando ECS Auto Scaling. |
| RunningCount | Si las tareas solicitadas están realmente ejecutándose. |
| PendingCount | Si existen problemas para aprovisionar nuevas tareas. |
| Task failures | Si hay tareas fallando, reiniciándose o con problemas de health check. |
| Scaling activity | Cuándo y por qué el servicio alcanzó `MaxCapacity`. |

Basicamente descartaria alguna configuración erronea a nivel de infra.

### 2.2 Validar métricas de aplicación

Después revisaría las señales de aplicación y las correlacionaría con el momento en que el servicio alcanzó su capacidad máxima:

| Señal | Qué buscaría validar |
| --- | --- |
| Latency | Cuándo comenzó el incremento de p95/p99. |
| Error rate | Si la degradación está generando errores. |
| Throughput | Si hubo un incremento anormal en el volumen de transacciones. |
| Logs | Errores, timeouts, connection errors o excepciones. |
| Traces | En qué componente del flujo se está concentrando la latencia. |

El objetivo es entender si la latencia aumenta porque `payments-processor` no tiene suficiente capacidad o si el servicio está esperando por otro componente.

### 2.3 Identificar el cuello de botella

Con esta información buscaría identificar dónde se concentra la degradación:

- `payments-processor`.
- Aurora PostgreSQL.
- Otros microservicios del flujo.
- Dependencias o proveedores externos.

Distributed tracing sería especialmente útil para revisar cuánto tiempo consume cada componente dentro de una transacción.

Por ejemplo:

```text
Payment transaction
      │
      ├── payments-api          80 ms
      ├── payments-processor   120 ms
      ├── Aurora               150 ms
      └── payment-provider    3.8 sec
```

En este caso no incrementaría la capacidad de ECS, ya que la mayor parte de la latencia está siendo generada por `payment-provider`.

Con el diagnóstico clasificaría inicialmente el incidente:

| Origen | Indicadores |
| --- | --- |
| infraestructura | CPU/memoria saturada, tasks pendientes o límite de escalamiento insuficiente. |
| Aplicación | Errores, excepciones, degradación después de un deployment o procesamiento anormal. |
| Base de datos | Alta latencia, conexiones agotadas, locks, queries lentas o CPU/I/O elevados. |
| Dependencia externa | Latencia, timeouts o errores concentrados en una integración externa. |

Esta clasificación define la acción de mitigación.

> **Nota:** no incrementaría inmediatamente el `MaxCapacity`. Alcanzar `10/10` es una señal importante, pero primero validaría que agregar tareas realmente ayude a recuperar el servicio y que no aumente la presión sobre Aurora u otra dependencia.

## 3. Mitigación

Una vez identificado el origen, aplicaría la acción de menor riesgo que permita recuperar el servicio sin generar downtime.

| Origen | Mitigación |
| --- | --- |
| **Capacidad ECS** | Incrementaría temporalmente `MaxCapacity` de forma controlada y monitorearía la recuperación. |
| **Capacidad del cluster** | Resolvería primero los problemas de capacidad o placement antes de intentar agregar más tasks. |
| **Cambio reciente / aplicación** | Si la degradación comenzó después de un deployment, haría rollback a la última versión estable. Si existe un feature flag, evaluaría deshabilitar temporalmente la funcionalidad afectada. |
| **Aurora** | Revisaría queries, conexiones, locks o saturación de recursos y reduciría la presión sobre la base de datos antes de agregar más capacidad en ECS. |

Si confirmo que el problema es falta de capacidad de `payments-processor`, podría incrementar temporalmente:

```text
MaxCapacity: 10 → 15
```

y observaría si la latencia, CPU y backlog comienzan a recuperarse antes de realizar otro incremento.

Si el cambio modifica infraestructura administrada mediante Terraform, posteriormente reconciliaría la configuración para evitar drift.

## 4. Validación y cierre del incidente

Después de aplicar la mitigación no cerraría inmediatamente el incidente. Primero validaría que el servicio se mantenga estable durante un período de tiempo.

Revisaría principalmente:

- Latencia p99 dentro de los valores esperados.
- Error rate normal.
- CPU y memoria estables.
- `RunningCount` y `PendingCount` sin anomalías.
- Throughput recuperado.
- Aurora y dependencias externas estables.

Una vez confirmada la recuperación:

1. Actualizaría el incidente a `RESOLVED`.
2. Documentaría las acciones y cambios realizados.
3. Comunicaría la recuperación a los equipos involucrados.
4. Crearía las tareas necesarias para cambios temporales o acciones pendientes.

El cierre confirma la recuperación del servicio. El análisis de la causa raíz se realiza en el postmortem.

## 5. Postmortem

Una vez cerrado el incidente realizaría un postmortem para entender la causa raíz y definir acciones que reduzcan la probabilidad de que vuelva a ocurrir.

Incluiría:

- **Resumen e impacto:** qué ocurrió, duración y servicios o transacciones afectadas.
- **Timeline:** detección, diagnóstico, mitigación y recuperación.
- **Root Cause:** causa principal del incidente.
- **Factores contribuyentes:** condiciones que aumentaron el impacto.
- **Mitigación:** acciones utilizadas para recuperar el servicio.
- **Action Items:** mejoras identificadas y responsable.

Los Action Items pueden incluir cambios en Auto Scaling, alertas preventivas, pruebas de carga, mejoras de observabilidad, actualización del runbook o automatización de acciones que durante el incidente tuvieron que realizarse manualmente.