# Deuna! — AWS Infrastructure Challenge

Este repositorio contiene mi propuesta para resolver el challenge técnico de infraestructura y ambientes AWS.

La solución está dividida en cuatro tareas que cubren observabilidad, FinOps, Infrastructure as Code y gestión de incidentes.

## Enfoque

Decidí abordar cada tarea mediante un **RFC (Request for Comments)** para documentar de forma simple el contexto, la solución propuesta y las principales decisiones técnicas.

Este formato me permite mantener cada problema separado y explicar no solo la solución, sino también el criterio utilizado para tomar las decisiones de diseño.

Para la implementación de IaC, el RFC documenta las decisiones tomadas y el directorio `terraform/` contiene la implementación.

## Soluciones

### Tarea 1 — Monitoreo de capacidad máxima en ECS

Solución orientada a eventos para detectar servicios ECS que alcanzan su `MaxCapacity`, generar alertas accionables y centralizar los eventos en la plataforma de observabilidad.

**RFC:** [RFC-001 — Monitoreo de capacidad máxima de microservicios en Amazon ECS](tasks/rfc-001-monitoreo-ecs.md)

---

### Tarea 2 — Costeo por tipo de transacción

Modelo para estimar el costo de transacciones `MONETARY` y `NON_MONETARY`, combinando métricas de consumo con información de AWS Billing y definiendo un modelo de calculo para el costo de la infraestructura compartida.

**RFC:** [RFC-002 — Costeo por tipo de transacción](tasks/rfc-002-costeo-transacciones.md)

---

### Tarea 3 — Implementación IaC con Terraform

Implementación de infraestructura AWS utilizando Terraform.

Incluye:

- VPC.
- AWS KMS.
- Amazon S3.
- Amazon Aurora PostgreSQL.
- AWS Secrets Manager.
- Remote State.
- Terraform Workspaces.
- Validaciones de seguridad y costos.

**RFC:** [RFC-003 — Infraestructura AWS con Terraform](tasks/rfc-003-iac.md)

**Código:** [`terraform/`](terraform/)

---

### Tarea 4 — Gestión de incidente en producción

Propuesta para gestionar un incidente de saturación en ECS, cubriendo diagnóstico, identificación del cuello de botella, mitigación, recuperación y postmortem.

**RFC:** [RFC-004 — Gestión de incidente por saturación de capacidad en ECS](tasks/rfc-004-SRE.md)

## Estructura

```text
.
├── README.md
├── docs/
│   ├── RFC-001.md
│   ├── RFC-002.md
│   ├── RFC-003.md
│   └── RFC-004.md
│
├── diagrams/
│   ├── rfc-001-ecs-events.png
│   └── rfc-002-costeo-transacciones.png
│
└── terraform/
    ├── modules/
    │   ├── vpc/
    │   ├── kms/
    │   ├── s3/
    │   └── aurora/
    ├── workspaces/
    ├── backend.tf
    ├── providers.tf
    ├── versions.tf
    ├── variables.tf
    ├── locals.tf
    └── main.tf
```

## Criterios de diseño

Las soluciones fueron planteadas considerando los ejes definidos para el challenge:

- **Costo-eficiencia:** optimización de recursos y visibilidad de costos.
- **Seguridad:** least privilege, encriptación y control de acceso.
- **Operación:** IaC, automatización y reducción de tareas manuales.
- **Observabilidad:** métricas, eventos, trazabilidad y alertas accionables.