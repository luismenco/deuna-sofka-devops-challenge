# RFC-002 — Costeo por tipo de transacción

## 1. Contexto

Deuna! procesa transacciones monetarias y no monetarias sobre una arquitectura de microservicios en AWS.

Cada flujo transaccional consume un conjunto diferente de servicios AWS como Lambda, API Gateway, RDS Aurora, SQS y S3. Cada servicio tiene su propio modelo de costeo y gran parte de la infraestructura es compartida entre los diferentes flujos.

Para este escenario propongo una solución que permita estimar cuánto cuesta procesar una transacción monetaria y una no monetaria, utilizando el consumo observado en los flujos y los costos reportados por AWS.

## 2. Definición del problema

AWS permite consultar el costo y consumo de los recursos mediante herramientas como AWS Cost Explorer, pero cuando la infraestructura es compartida este costo no puede asociarse directamente a una transacción monetaria o no monetaria.

Por ejemplo, Cost Explorer puede mostrar el costo por servicio durante un período y permitir filtros mediante tags como `team`, `service`, `component` o `environment`:

| Servicio AWS | Costo mensual |
| --- | ---: |
| Amazon Aurora | $8,000 |
| Amazon ECS | $3,500 |
| AWS Lambda | $1,200 |
| Amazon API Gateway | $800 |
| Amazon SQS | $300 |
| Amazon S3 | $200 |
| **Total** | **$14,000** |

Esta información permite conocer cuánto cuesta cada servicio, pero no cuánto cuesta procesar cada tipo de transacción.

Para realizar esta estimación necesito identificar si una transacción es `MONETARY` o `NON_MONETARY`, mantener esta información durante su recorrido y relacionar el consumo observado con los costos reportados por AWS.

Para el cálculo dividiría los costos en dos grupos:

- **Costos directos:** servicios cuyo consumo puedo relacionar con cada tipo de transacción.
- **Costos compartidos:** servicios utilizados por ambos tipos de transacción y cuyo costo necesito distribuir utilizando un driver definido.

El resultado será una estimación del costo promedio por tipo de transacción y no un cálculo exacto por request individual.

## 3. Objetivos

- Identificar las transacciones como `MONETARY` o `NON_MONETARY`.
- Mantener el tipo de transacción durante todo el flujo.
- Obtener los costos de los servicios utilizados en AWS.
- Diferenciar costos directos y compartidos.
- Definir un criterio simple para distribuir los costos compartidos.
- Calcular el costo aproximado por tipo de transacción.
- Automatizar la recolección y cálculo de la información.
- Presentar los resultados a producto y finanzas.

## 4. Solución propuesta

### 4.1 Identificación y medición de transacciones

Propongo instrumentar las aplicaciones con **OpenTelemetry** para identificar el tipo de transacción y generar métricas de consumo por servicio.

Cada transacción se clasificaría utilizando atributos como:

```text
transaction.id   = "UUID"
transaction.type = "MONETARY | NON_MONETARY"
```

Para identificar el componente que procesa la transacción utilizaría `service.name`, lo que permite agrupar las métricas por servicio y tipo de transacción.

Ejemplo:

```text
transactions_total{
  transaction_type="MONETARY",
  service_name="payments-api"
}
```

En flujos síncronos mantendría `transaction.type` durante las llamadas entre microservicios. En flujos asíncronos, como SQS, propagaría esta información como metadata del mensaje para que el consumidor mantenga la clasificación original.

La telemetría se enviaría a la plataforma de observabilidad existente, donde podría consultar el volumen procesado por cada servicio.

| Servicio | MONETARY | NON_MONETARY | Total |
| --- | ---: | ---: | ---: |
| payments-api | 2,000,000 | 0 | 2,000,000 |
| transactions-worker | 1,500,000 | 500,000 | 2,000,000 |
| customer-api | 0 | 4,000,000 | 4,000,000 |

Estas métricas me permiten conocer qué servicios participan en cada tipo de transacción y qué proporción de su consumo corresponde a cada categoría. Esta información será una de las entradas para el modelo de atribución de costos.

### 4.2 Modelo de atribución de costos

Clasificaría los costos en dos grupos según la posibilidad de relacionar su consumo con las transacciones procesadas.

#### Costos directos

Para servicios donde puedo medir el consumo por tipo de transacción utilizaría las métricas obtenidas en el punto anterior como driver de atribución.

Por ejemplo:

| Servicio | Driver de atribución |
| --- | --- |
| API Gateway | Requests procesados |
| Lambda | Invocaciones |
| SQS | Mensajes procesados |
| S3 | Requests/operaciones |

Para un componente utilizado por ambos tipos de transacción calcularía la proporción de consumo:

```text
MONETARY     = requests MONETARY / requests totales
NON_MONETARY = requests NON_MONETARY / requests totales
```

Después aplicaría esta proporción al costo del componente obtenido desde AWS.

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

Para componentes donde no puedo relacionar directamente el modelo de facturación con una transacción, como Aurora o capacidad compartida de ECS, utilizaría inicialmente el volumen de transacciones como driver de distribución.

Ejemplo:

```text
Costo Aurora = $8,000

MONETARY     = 3,000,000 transacciones (30%)
NON_MONETARY = 7,000,000 transacciones (70%)

Costo atribuido:

MONETARY     = $2,400
NON_MONETARY = $5,600
```

Inicialmente mantendría este modelo simple y trazable. Si posteriormente se requiere mayor precisión, lo evolucionaría utilizando drivers específicos, por ejemplo duración y memoria en Lambda, CPU/memoria en ECS o carga e I/O en Aurora.

### 4.3 Obtención de costos desde AWS

Para obtener los costos utilizaría los servicios de **AWS Billing and Cost Management**.

Utilizaría **AWS Cost Explorer** principalmente para consultar y validar costos por servicio, cuenta, región, período y tags de asignación de costos.

Para alimentar el proceso automatizado utilizaría **AWS Data Exports / Cost and Usage Report (CUR)**, almacenando la información detallada de costos y uso en Amazon S3.

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
Athena
     │
     ▼
Costos por servicio/componente
```

Mantendría además una estrategia de tagging consistente para poder relacionar los registros de billing con los componentes de la plataforma.

Por ejemplo:

```text
environment = production
service     = payments
component   = payments-worker
team        = transactions
```

### 4.4 Pipeline automatizado de cálculo

Para automatizar el cálculo propongo un proceso batch mensual iniciado por **EventBridge Scheduler**.

Elegiría una ejecución mensual porque el objetivo no requiere calcular costos en tiempo real y permite trabajar con la información consolidada de billing del período.

![cost-calculation](../diagrams/rfc-002-costeo-transacciones.png)

Utilizaría una función Lambda como procesador del modelo de costos con dos fuentes principales de información:

- **Costos AWS:** obtenidos desde AWS Data Exports / CUR y consultados mediante Athena.
- **Métricas transaccionales:** cantidad de transacciones `MONETARY` y `NON_MONETARY` obtenidas desde la plataforma de observabilidad.

El proceso sería:

1. Consultar los costos AWS del período agrupados por servicio o componente.
2. Consultar las transacciones `MONETARY` y `NON_MONETARY` procesadas por cada componente.
3. Calcular la proporción de consumo por tipo de transacción.
4. Aplicar el modelo de atribución definido en `4.2`.
5. Sumar los costos atribuidos a cada tipo de transacción.
6. Dividir el costo atribuido entre la cantidad de transacciones procesadas.
7. Almacenar el resultado mensual en S3.

#### Ejemplo de cálculo

Supongamos que durante el período se procesaron:

```text
MONETARY       = 600 transacciones
NON_MONETARY   = 400 transacciones
TOTAL          = 1,000 transacciones
```

Para componentes donde tengo una métrica de consumo por `transaction.type`, utilizaría la distribución observada en cada componente.

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

Para infraestructura compartida donde no tengo una métrica directa de consumo por tipo utilizaría inicialmente la proporción global de transacciones:

```text
Aurora
Costo AWS      = $500

MONETARY       = 60% → $300
NON_MONETARY   = 40% → $200
```

El resultado sería:

| Componente | Costo AWS | MONETARY | NON_MONETARY |
| --- | ---: | ---: | ---: |
| API Gateway | $100 | $60 | $40 |
| Lambda | $200 | $180 | $20 |
| Aurora | $500 | $300 | $200 |
| **Total** | **$800** | **$540** | **$260** |

Finalmente calcularía el costo promedio por transacción:

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

Para recursos compartidos como Aurora considero esta distribución una primera aproximación. Si el nivel de precisión requerido aumenta, utilizaría drivers más específicos como carga de base de datos, I/O o tiempo de ejecución.

También permitiría reprocesar un período determinado si AWS registra posteriormente ajustes en la información de facturación.

### 4.5 Presentación de resultados

Los resultados agregados quedarían almacenados en S3 y disponibles para consulta mediante Athena.

Para producto y finanzas presentaría la información mediante un dashboard en **Amazon QuickSight** o en la plataforma de visualización existente.

Priorizaría indicadores que permitan entender rápidamente el costo de cada flujo:

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

Mantendría también el detalle por componente para que ingeniería pueda identificar qué servicios tienen mayor impacto sobre el costo de cada tipo de transacción y dónde existen oportunidades de optimización.