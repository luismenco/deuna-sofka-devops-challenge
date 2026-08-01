# RFC-002 — Costeo por tipo de transacción

## 1. Contexto

Deuna! procesa transacciones monetarias y no monetarias sobre una arquitectura de microservicios en AWS.

Cada flujo transaccional de Deuna! (monetario y no monetario) consume un conjunto diferente de servicios AWS: Lambda, API Gateway, RDS Aurora, SQS, S3, entre otros. Cada servicio tiene su propio modelo de costeo. Los servicios son en su mayoría compartidos entre flujos.

Se requiere estimar cuánto cuesta procesar una transacción monetaria y una no monetaria, utilizando información de consumo de los flujos y los costos reportados por AWS.

## 2. Definición del problema

AWS permite conocer el costo y consumo de los recursos utilizados por medio de AWS Cost Explorer, pero en infraestructura compartida este costo no puede asociarse directamente a una transacción monetaria o no monetaria.

Por ejemplo, Cost Explorer puede mostrar el costo por servicio durante un período, e incluso filtrar por tags configurados a nivel de cada servicio (team,servicio,componente,ambiente,etc):

| Servicio AWS | Costo mensual |
| --- | ---: |
| Amazon Aurora | $8,000 |
| Amazon ECS | $3,500 |
| AWS Lambda | $1,200 |
| Amazon API Gateway | $800 |
| Amazon SQS | $300 |
| Amazon S3 | $200 |
| **Total** | **$14,000** |

Esta información permite conocer cuánto cuesta cada servicio, pero no entrega el valor o costo x transacción.

Para calcular el costo por tipo de transacción necesitamos identificar si una transacción es monetaria o no monetaria y mantener esta información durante todo su flujo.

Los costos debemos dividirlos en dos grupos:

- **Costos directos:** servicios cuyo consumo podemos relacionar con cada tipo de transacción.
- **Costos compartidos:** servicios utilizados por ambos tipos de transacción, cuyo costo debe distribuirse proporcionalmente.

El resultado será una estimación del costo por tipo de transacción y no un cálculo exacto por request individual.

## 3. Objetivos

- Identificar las transacciones como `MONETARY` o `NON_MONETARY`.
- Mantener el tipo de transacción durante todo el flujo.
- Obtener los costos de los servicios utilizados en AWS.
- Diferenciar entre costos directos y costos compartidos.
- Distribuir los costos compartidos entre ambos tipos de transacción.
- Calcular el costo aproximado por transacción.
- Automatizar la recolección y cálculo de esta información.
- Presentar los resultados a los equipos de producto y finanzas.

## 4. Solución propuesta

### 4.1 Identificación y medición de transacciones

Las aplicaciones se instrumentan con **OpenTelemetry** para identificar el tipo de transacción y generar métricas de consumo por servicio.

Cada transacción se clasifica utilizando el atributo:

```text
transaction.id= "UUID"
transaction.type = "MONETARY | NON_MONETARY"
```

Para identificar el componente que procesa la transacción se utiliza `service.name`, permitiendo agrupar las métricas por servicio y tipo de transacción.

Ejemplo:

```text
transactions_total{
  transaction_type="MONETARY",
  service_name="payments-api"
}
```

En flujos síncronos, `transaction.type` se mantiene durante las llamadas entre microservicios. En flujos asíncronos, como SQS, se propaga como metadata del mensaje para que el consumidor mantenga la clasificación original.

La telemetría generada se envía a la plataforma de observabilidad existente, donde se puede consultar el volumen procesado por cada servicio.

| Servicio | MONETARY | NON_MONETARY | Total |
| --- | ---: | ---: | ---: |
| payments-api | 2,000,000 | 0 | 2,000,000 |
| transactions-worker | 1,500,000 | 500,000 | 2,000,000 |
| customer-api | 0 | 4,000,000 | 4,000,000 |

Estas métricas permiten conocer qué servicios participan en cada tipo de transacción y qué proporción de su carga corresponde a cada categoría. Esta información será utilizada posteriormente como entrada para el modelo de atribución de costos.

### 4.2 Modelo de atribución de costos

Los costos los clasificaria en dos grupos según la posibilidad de relacionar su consumo con las transacciones procesadas.

#### Costos directos

Para servicios donde es posible medir el consumo por tipo de transacción, la atribución se realiza utilizando las métricas obtenidas en el punto anterior.

Ejemplos:

| Servicio | Driver de atribución |
| --- | --- |
| API Gateway | Requests procesados |
| Lambda | Invocaciones |
| SQS | Mensajes procesados |
| S3 | Requests/operaciones |

Para un servicio que procesa ambos tipos de transacción se calcula la proporción de consumo:

```text
MONETARY     = requests MONETARY / requests totales
NON_MONETARY = requests NON_MONETARY / requests totales
```

Esta proporción se aplica al costo del servicio obtenido desde AWS.

Ejemplo:

```text
Costo Lambda payments-worker = $1,000

MONETARY     = 750,000 invocaciones (75%)
NON_MONETARY = 250,000 invocaciones (25%)

Costo atribuido:

MONETARY     = $750
NON_MONETARY = $250
```

#### Costos compartidos

Para componentes donde no existe una relación directa entre una transacción y el modelo de facturación, como Aurora o capacidad compartida de ECS, se utiliza inicialmente el volumen de transacciones como driver de distribución.

Ejemplo:

```text
Costo Aurora = $8,000

MONETARY     = 3,000,000 transacciones (30%)
NON_MONETARY = 7,000,000 transacciones (70%)

Costo atribuido:

MONETARY     = $2,400
NON_MONETARY = $5,600
```

Este modelo mantiene el cálculo simple y trazable. Si se requiere mayor precisión,podemos evolucionar utilizando métricas específicas de cada servicio, por ejemplo duración y memoria en Lambda, consumo de CPU/memoria en ECS o carga e I/O en Aurora.

### 4.3 Obtención de costos desde AWS

Para obtener la información de costos se utilizan los servicios de **AWS Billing and Cost Management**.

**AWS Cost Explorer** se utiliza para consultar y validar los costos por servicio, cuenta, región, período y tags de asignación de costos.

Para alimentar el proceso automatizado se propone utilizar **AWS Data Exports / Cost and Usage Report (CUR)**, almacenando la información detallada de costos y uso en Amazon S3.

```text
AWS Billing
     │
     ▼
Data Exports / CUR
     │
     ▼
Amazon S3
     │
     ▼
Costos por servicio/componente
```

Los recursos AWS deben mantener una estrategia de tagging consistente que permita identificar el componente al que pertenece el costo.

Por ejemplo:

```text
environment = production
service     = payments
component   = payments-worker
team        = transactions
```

### 4.4 Pipeline automatizado de cálculo

El cálculo se ejecuta mediante un proceso batch mensual iniciado por **EventBridge Scheduler**.

![cost-calculation](../diagrams/rfc-002-costeo-transacciones.png)

La función Lambda actúa como procesador del modelo de costos y utiliza dos fuentes de información:

- **Costos AWS:** costos del período consultados desde los datos de AWS Data Exports / CUR mediante Athena.
- **Métricas transaccionales:** cantidad de transacciones `MONETARY` y `NON_MONETARY` obtenidas desde la plataforma de observabilidad.

El proceso ejecuta los siguientes pasos:

1. Obtiene los costos AWS del período agrupados por servicio o componente.
2. Obtiene la cantidad de transacciones `MONETARY` y `NON_MONETARY` procesadas por cada componente.
3. Calcula la proporción de consumo por tipo de transacción.
4. Distribuye el costo de cada componente utilizando el modelo definido en `4.2`.
5. Suma los costos atribuidos a cada tipo de transacción.
6. Divide el costo total atribuido entre la cantidad de transacciones procesadas.
7. Almacena el resultado mensual en S3.

#### Ejemplo de cálculo

Supongamos que durante el período se procesaron:

```text
MONETARY       = 600 transacciones
NON_MONETARY   = 400 transacciones
TOTAL          = 1,000 transacciones
```

Para componentes donde existe una métrica de consumo por `transaction.type`, se utiliza la distribución observada en ese componente.

Por ejemplo:

```text
API Gateway
Costo AWS      = $100

MONETARY       = 600 requests (60%) → $60
NON_MONETARY   = 400 requests (40%) → $40
```

Otro componente puede tener una distribución diferente:

```text
Lambda
Costo AWS      = $200

MONETARY       = 900 invocaciones (90%) → $180
NON_MONETARY   = 100 invocaciones (10%) → $20
```

Para infraestructura compartida donde no existe una métrica directa de consumo por tipo, se utiliza como driver inicial la proporción global de transacciones:

```text
Aurora
Costo AWS      = $500

MONETARY       = 60% → $300
NON_MONETARY   = 40% → $200
```

El resultado de la atribución sería:

| Componente | Costo AWS | MONETARY | NON_MONETARY |
| --- | ---: | ---: | ---: |
| API Gateway | $100 | $60 | $40 |
| Lambda | $200 | $180 | $20 |
| Aurora | $500 | $300 | $200 |
| **Total** | **$800** | **$540** | **$260** |

Finalmente se calcula el costo promedio por transacción:

```text
MONETARY
$540 / 600 = $0.90 por transacción

NON_MONETARY
$260 / 400 = $0.65 por transacción
```

El resultado mensual almacenado sería:

| Período | Tipo | Transacciones | Costo atribuido | Costo promedio |
| --- | --- | ---: | ---: | ---: |
| 2026-07 | MONETARY | 600 | $540 | $0.90 |
| 2026-07 | NON_MONETARY | 400 | $260 | $0.65 |

Para recursos compartidos como Aurora, la distribución por volumen de transacciones representa una primera aproximación. El modelo puede evolucionar utilizando drivers más específicos, como carga de base de datos, I/O o tiempo de ejecución, si se requiere mayor precisión.

El proceso puede ejecutarse nuevamente para un período determinado si AWS registra ajustes posteriores en los datos de facturación.

### 4.5 Presentación de resultados

Los resultados agregados se almacenan en S3 y se consultan mediante Athena. Para los equipos de producto y finanzas se propone un dashboard en **Amazon QuickSight o grafana**  con la información mensual de costos.

El dashboard debe permitir visualizar:

- Costo total por tipo de transacción.
- Costo promedio por transacción `MONETARY` y `NON_MONETARY`.
- Cantidad de transacciones procesadas.
- Distribución del costo por servicio o componente.
- Evolución mensual del costo por transacción.

Ejemplo:

| Indicador | MONETARY | NON_MONETARY |
| --- | ---: | ---: |
| Transacciones | 3,000,000 | 7,000,000 |
| Costo atribuido | $6,000 | $8,700 |
| Costo promedio | $0.0020 | $0.00124 |

Adicionalmente, el detalle por componente permite identificar qué servicios tienen mayor impacto sobre el costo de cada tipo de transacción.