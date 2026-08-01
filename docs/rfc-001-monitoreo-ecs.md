# RFC-001 — Monitoreo de capacidad máxima de microservicios en Amazon ECS

**Estado:** Propuesto

## 1. Contexto

Deuna! opera múltiples microservicios sobre Amazon ECS, cada uno con límites independientes de escalamiento. Los servicios utilizan políticas de Auto Scaling basadas en CPU y memoria, con un umbral del 60 %, y pueden escalar horizontalmente hasta alcanzar la capacidad máxima configurada.

La plataforma principal de observabilidad es externa a AWS y utiliza CloudWatch Logs como fuente de ingesta.

Este RFC propone una solución para detectar cuándo un servicio ECS alcanza su capacidad máxima de tareas, generar alertas accionables y proporcionar visibilidad centralizada al equipo de guardia, procurando bajo costo y mínima carga operacional.

## 2. Definición del problema

Cuando un servicio ECS alcanza el máximo de tareas configurado, ya no puede continuar escalando horizontalmente. Si la carga sigue aumentando, pueden aparecer problemas de latencia, errores o degradación del servicio.

Se necesita detectar esta condición para todos los servicios del clúster, considerando que cada uno puede tener un `MaxCapacity` diferente. La señal debe llegar a la plataforma de observabilidad actual y permitir alertar al equipo de guardia cuando la condición requiera atención, evitando alertas innecesarias ante picos temporales.

## 3. Objetivos

* Detectar cuando un servicio ECS alcanza el `MaxCapacity` configurado.
* Integrar la señal con la plataforma de observabilidad existente a través de CloudWatch Logs.
* Generar alertas con contexto suficiente para facilitar el diagnóstico.
* Evitar ruido por eventos transitorios o repetitivos.
* Tener una vista centralizada del estado de capacidad de los servicios ECS.
* Mantener una solución simple, de bajo costo y con poca carga operativa.

## 4. Solución propuesta

### 4.1 Mecanismo de detección

La detección se basa en los eventos generados por **Application Auto Scaling** cuando un servicio alcanza la capacidad máxima configurada.

Application Auto Scaling publica eventos de tipo `Application Auto Scaling Scaling Activity State Change` en Amazon EventBridge. Estos eventos incluyen información sobre el recurso escalado, la capacidad anterior, la nueva capacidad y los límites configurados.

La propiedad `scaledToMax = true` permite identificar específicamente una actividad de scale-out que alcanzó el `MaxCapacity`.

#### Solución — Arquitectura orientada a eventos

La solución utiliza **Amazon EventBridge** para capturar eventos generados por Application Auto Scaling cuando ocurre una actividad de escalamiento sobre los servicios ECS.

![ecs-events](../diagrams/frc-001-ecs-events.png)

El flujo funciona de la siguiente manera:

### Application Auto Scaling genera el evento de escalamiento

Cuando ocurre una actividad de escalamiento, Application Auto Scaling publica un evento `Application Auto Scaling Scaling Activity State Change` en EventBridge.

Se configura una regla para procesar únicamente eventos asociados al escalamiento del `DesiredCount` de servicios ECS que hayan alcanzado su capacidad máxima:

```json
{
  "source": [
    "aws.application-autoscaling"
  ],
  "detail-type": [
    "Application Auto Scaling Scaling Activity State Change"
  ],
  "detail": {
    "serviceNamespace": [
      "ecs"
    ],
    "scalableDimension": [
      "ecs:service:DesiredCount"
    ],
    "scaledToMax": [
      true
    ]
  }
}
```

El filtro `serviceNamespace = ecs` evita procesar eventos de otros servicios soportados por Application Auto Scaling. `scalableDimension = ecs:service:DesiredCount` limita la regla al escalamiento de tareas de servicios ECS.

Finalmente, `scaledToMax = true` permite procesar únicamente eventos donde el escalamiento alcanzó el `MaxCapacity` configurado.

### EventBridge invoca la función Lambda

La regla de EventBridge utiliza una función Lambda como target.

El evento recibido contiene información relacionada con el servicio y la actividad de escalamiento, incluyendo:

- `resourceId`
- `oldDesiredCapacity`
- `newDesiredCapacity`
- `minCapacity`
- `maxCapacity`
- `scaledToMax`
- `direction`
- `statusCode`

La función Lambda procesa y normaliza esta información. Si se requiere mayor contexto operacional, puede enriquecer el evento consultando información adicional del servicio ECS o métricas disponibles en CloudWatch ejemplo cpu y memoria al momento de generarse el vento.

### Lambda genera el evento de observabilidad

Lambda genera un evento JSON estructurado con la información necesaria para identificar el servicio y su estado de capacidad.

Ejemplo:

```json
{
  "event_type": "ecs.capacity.max_reached",
  "cluster": "payments-cluster",
  "service": "payments-processor",
  "desired_tasks": 10,
  "max_tasks": 10,
  "capacity_percent": 100,
  "status": "MAX_CAPACITY_REACHED",
  "timestamp": "2026-08-01T07:47:00Z"
}
```

### CloudWatch Logs centraliza los eventos

Lambda registra los eventos generados en un Log Group dedicado.

La plataforma externa de observabilidad utiliza la integración existente con CloudWatch Logs para ingerir estos eventos y utilizarlos en alertas y dashboards.

> **Nota:** EventBridge realiza el filtrado inicial utilizando la información proporcionada por Application Auto Scaling. La función Lambda queda encargada de normalizar y, cuando sea necesario, enriquecer el evento antes de enviarlo al flujo de observabilidad.  


### 4.2 Diseño de alertas

Cuando se recibe un evento con `scaledToMax = true`, la plataforma externa genera una alerta indicando que el servicio ECS alcanzó su capacidad máxima configurada.

La alerta debe contener suficiente contexto para que el equipo de guardia pueda identificar rápidamente el servicio y evaluar su estado.

Ejemplo:

```text
[ECS MAX CAPACITY] payments-processor

Environment: production
Cluster: payments-cluster
Service: payments-processor
Capacity: 10/10 tasks
CPU: 72%
Memory: 64%
Region: us-east-1

Status: MAX_CAPACITY_REACHED
```

La alerta debe incluir como mínimo:

- Ambiente y región.
- Cluster y servicio afectado.
- Capacidad actual y `MaxCapacity`.
- CPU y memoria al momento de procesar el evento.
- Timestamp del evento.
- Enlace al dashboard o runbook, si está disponible.

Alcanzar `MaxCapacity` genera la alerta de capacidad. Las métricas de CPU y memoria se incluyen como contexto para facilitar el diagnóstico, pero no determinan por sí solas la severidad de la alerta.

### 4.3 Reducción de ruido

La reducción de ruido se aplica desde el inicio del flujo. La regla de EventBridge procesa únicamente eventos de Application Auto Scaling asociados a servicios ECS que hayan alcanzado su capacidad máxima.

Los eventos deben cumplir las siguientes condiciones:

- `serviceNamespace = ecs`
- `scalableDimension = ecs:service:DesiredCount`
- `scaledToMax = true`

Esto evita ejecutar la función Lambda para actividades normales de scale-out y reduce la cantidad de eventos enviados a la plataforma de observabilidad.

Sobre los eventos resultantes se pueden aplicar las siguientes reglas:

- **Deduplicación:** agrupar eventos por `environment + cluster + service`, evitando múltiples alertas para el mismo servicio durante una misma condición.
- **Ventana de tiempo:** evitar notificaciones repetidas del mismo servicio dentro de un período configurable.
- **Priorización por ambiente:** los eventos de producción pueden generar una notificación al equipo de guardia, mientras que los ambientes no productivos pueden mantenerse únicamente como eventos visibles en el dashboard.
- **Enriquecimiento:** incluir capacidad, CPU y memoria dentro de una misma alerta evita generar señales independientes para información relacionada con el mismo evento.

El objetivo es que un evento `scaledToMax` produzca una única señal accionable por servicio y no múltiples alertas asociadas al mismo evento de escalamiento.

### 4.4 Dashboard

El dashboard se construye en la plataforma externa de observabilidad a partir de los eventos ingeridos desde CloudWatch Logs.

El objetivo es dar al equipo de guardia una vista rápida de los servicios que han alcanzado su capacidad máxima y facilitar el análisis de eventos recurrentes.

#### Vista general

La vista principal muestra los servicios que han generado eventos `MAX_CAPACITY_REACHED` dentro del período seleccionado.

| Servicio | Cluster | Capacidad | CPU | Memoria | Último evento |
| --- | --- | ---: | ---: | ---: | --- |
| payments-processor | payments-cluster | 10/10 | 82% | 76% | hace 2 min |
| transfers-api | transactions-cluster | 15/15 | 68% | 61% | hace 18 min |

Indicadores principales:

- Servicios que alcanzaron `MaxCapacity`.
- Cantidad de eventos `MAX_CAPACITY_REACHED`.
- Servicios con mayor recurrencia de eventos.
- Eventos agrupados por ambiente o cluster.
- Alertas activas asociadas a capacidad máxima.

#### Vista por servicio

Al seleccionar un servicio se muestra el detalle de los eventos de capacidad dentro del rango de tiempo seleccionado:

- Capacidad alcanzada y `MaxCapacity`.
- CPU y memoria registradas al momento del evento.
- Fecha y hora de cada evento.
- Historial de eventos `MAX_CAPACITY_REACHED`.
- Frecuencia con la que el servicio alcanza su capacidad máxima.

Cuando la plataforma de observabilidad disponga de otras fuentes de métricas o APM, esta vista puede correlacionarse con latencia, errores y throughput para facilitar el análisis del impacto.

> **Nota:** el dashboard está orientado a visualizar eventos de capacidad máxima y no el estado en tiempo real de todos los servicios ECS. La arquitectura genera eventos cuando Application Auto Scaling reporta `scaledToMax = true`.

### 4.5 Remediación automatizada

Como extensión de la solución, la alerta puede incluir una acción asociada a un **runbook de remediación** para aumentar temporalmente la capacidad máxima del servicio afectado.

El objetivo es reducir el tiempo de respuesta del equipo de guardia sin realizar cambios manuales directamente sobre la infraestructura.

El flujo propuesto es:

```text
MAX_CAPACITY_REACHED
        │
        ▼
External Observability Platform
        │
        │ Trigger Runbook
        ▼
Automation / Runbook
```

#### Reconciliación con Terraform

El aumento de `MaxCapacity` realizado durante el incidente genera una diferencia entre el estado real de AWS y la configuración declarada en Terraform.

Para evitar mantener este **drift**, la remediación debe iniciar un segundo flujo que proponga el cambio correspondiente en el repositorio de infraestructura:

```text
Runbook
   │
   ├── Update MaxCapacity in AWS
   │
   └── Trigger IaC reconciliation
                │
                ▼
        Terraform Repository
                │
                ▼
          Pull Request
                │
        Validate / Plan / Review
                │
                ▼
              Merge
```

El cambio permanente de infraestructura se mantiene bajo el flujo normal de IaC, incluyendo validación, `terraform plan`, revisión y aprobación antes del `apply`.

> **Nota:** el aumento automático de `MaxCapacity` debe considerarse una acción de mitigación y no una solución definitiva. Alcanzar frecuentemente el límite puede indicar problemas de dimensionamiento, performance, dependencias o configuración de las políticas de escalamiento.

## Referencias

1. AWS — Amazon ECS Service Auto Scaling  
   https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html

2. AWS — Viewing scaling activities for Application Auto Scaling  
   https://docs.aws.amazon.com/autoscaling/application/userguide/application-auto-scaling-scaling-activities.html

3. AWS — Application Auto Scaling `DescribeScalingActivities`  
   https://docs.aws.amazon.com/autoscaling/application/APIReference/API_DescribeScalingActivities.html
