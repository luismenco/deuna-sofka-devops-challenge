# RFC-003 — Infraestructura AWS con Terraform

## 1. Contexto

Para implementar la infraestructura requerida propongo utilizar **Terraform**, manteniendo la configuración de los recursos AWS como código y permitiendo reutilizar la misma implementación entre diferentes ambientes.

La solución incluye los siguientes componentes:

- VPC con subnets públicas y privadas.
- AWS KMS para encriptación de datos en reposo.
- Amazon S3 para almacenamiento.
- Amazon Aurora PostgreSQL.
- AWS Secrets Manager para gestionar las credenciales administrativas de Aurora.

La implementación está organizada de forma modular para separar responsabilidades, reutilizar componentes y mantener las configuraciones específicas de cada ambiente fuera de los módulos.

## 2. Estructura del repositorio

Organicé el código dentro del directorio `terraform/` de la siguiente forma:

```text
terraform/
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── kms/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── s3/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── aurora/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── workspaces/
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
│
├── backend.tf
├── providers.tf
├── versions.tf
├── variables.tf
├── locals.tf
├── data.tf
├── main.tf
└── outputs.tf
```

Utilizo `modules/` para encapsular cada componente de infraestructura y mantener responsabilidades separadas. El módulo raíz se encarga de consumir estos módulos y definir sus dependencias.

En `workspaces/` mantengo los valores específicos de cada ambiente, por ejemplo:

- CIDRs.
- Availability Zones.
- Subnets.
- NAT Gateway.
- Retención de backups.
- Configuraciones que puedan variar entre `dev`, `staging` y `prod`.

Para separar el estado de cada ambiente utilizo Terraform Workspaces:

```bash
terraform workspace select dev

terraform plan -var-file="workspaces/dev.tfvars"

terraform apply -var-file="workspaces/dev.tfvars"

terraform destroy -var-file="workspaces/dev.tfvars"
```

De esta forma separo la configuración del ambiente mediante `.tfvars` y su estado mediante Terraform Workspaces.

## 3. Componentes implementados

### 3.1 VPC

Aunque el reto no requiere explícitamente crear la VPC, decidí incluir un módulo básico de networking para poder desplegar Aurora sobre una red controlada.

El módulo crea:

- VPC.
- Subnets públicas distribuidas entre Availability Zones.
- Subnets privadas distribuidas entre Availability Zones.
- Internet Gateway para las subnets públicas.
- NAT Gateway configurable para salida a Internet desde las subnets privadas.
- Route Tables y asociaciones correspondientes.

Aurora se despliega únicamente sobre las subnets privadas.

Dejé el NAT Gateway configurable para evitar su costo en ambientes que no lo requieran y habilitarlo cuando existan workloads privados que necesiten salida a Internet, por ejemplo futuros servicios ECS o funciones Lambda.

### 3.2 KMS

Implementé una **Customer Managed KMS Key** simétrica para centralizar la encriptación de los recursos que manejan información sensible.

La configuración incluye:

- `SYMMETRIC_DEFAULT`.
- `ENCRYPT_DECRYPT`.
- Rotación automática.
- Ventana de eliminación configurable.
- Alias para facilitar su identificación.
- Key Policy basada en least privilege.

La Key Policy diferencia los principals que pueden administrar la llave de aquellos que únicamente necesitan utilizarla para operaciones criptográficas.

Esto permite evitar asignar permisos administrativos de KMS a workloads que solamente requieren cifrar o descifrar información.

### 3.3 S3

Para S3 implementé los siguientes controles:

- Server-side encryption utilizando la KMS Key creada.
- S3 Bucket Key.
- Versionado.
- Block Public Access.
- `BucketOwnerEnforced`.
- Lifecycle policy.
- Restricción de conexiones sin TLS mediante Bucket Policy.

Además de seguridad, incluí algunas consideraciones de costo.

S3 Bucket Key permite reducir las solicitudes realizadas hacia KMS y, por lo tanto, el costo asociado al uso de SSE-KMS.

La Lifecycle Policy permite mover objetos a clases de almacenamiento de menor costo y administrar versiones anteriores según la política de retención definida.

### 3.4 Aurora PostgreSQL

Aurora PostgreSQL se despliega únicamente sobre las subnets privadas de la VPC.

La configuración incluye:

- Encriptación en reposo con la KMS Key.
- DB Subnet Group privado.
- Security Group dedicado.
- Puerto PostgreSQL `5432` restringido a Security Groups autorizados.
- Backups automáticos.
- Deletion Protection configurable por ambiente.
- Final Snapshot cuando el ambiente lo requiera.
- Performance Insights.
- Enhanced Monitoring.

No habilito acceso público a las instancias del cluster.

La intención es que el acceso a la base de datos se realice únicamente desde workloads autorizados dentro de la red.

### 3.5 Secrets Manager

Para las credenciales administrativas de Aurora decidí utilizar la integración nativa entre RDS y AWS Secrets Manager:

```hcl
master_username             = "pgadmin"
manage_master_user_password = true
```

De esta forma no genero ni almaceno el password de `pgadmin` directamente en Terraform.

RDS genera las credenciales y administra el Secret en AWS Secrets Manager. El Secret utiliza la Customer Managed KMS Key definida para la solución y RDS administra la rotación de las credenciales.

El acceso al Secret se restringe mediante una Resource Policy a principals explícitamente autorizados.

Para el ambiente de prueba autorizo al principal utilizado para ejecutar Terraform. En producción reemplazaría este acceso por los IAM Roles específicos de los workloads que necesiten conectarse a Aurora.

## 4. Estado remoto de Terraform

Para el estado de Terraform utilizo un backend remoto en Amazon S3:

```hcl
terraform {
  backend "s3" {
    bucket       = "terraform-state-bucket"
    key          = "deuna/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

La decisión de utilizar estado remoto permite evitar archivos `tfstate` locales y facilita la ejecución de Terraform desde CI/CD o por diferentes miembros del equipo.

Para el backend considero:

- S3 para almacenamiento remoto.
- Cifrado del state en reposo.
- S3 lockfile para evitar modificaciones concurrentes.
- Versionado del bucket para recuperación ante cambios accidentales.
- Un state independiente por Terraform Workspace.

No utilizo DynamoDB para state locking, ya que utilizo el mecanismo de lockfile soportado por el backend S3.

El bucket del backend debe existir previamente y mantenerse separado de los recursos administrados por este mismo state.

## 5. Validaciones antes del apply

Antes de ejecutar un `apply` propongo validar formato, configuración, seguridad y costo del cambio.

Como validación básica ejecutaría:

```bash
terraform fmt -check -recursive

terraform validate

terraform plan \
  -var-file="workspaces/dev.tfvars"
```

Para un pipeline de CI/CD agregaría:

| Herramienta | Uso |
| --- | --- |
| `terraform fmt` | Validar formato del código. |
| `terraform validate` | Validar la configuración Terraform. |
| `TFLint` | Detectar errores y malas prácticas de Terraform/AWS. |
| `Trivy` | Detectar configuraciones inseguras en IaC. |
| `Infracost` | Estimar el impacto en costos del cambio. |
| `terraform plan` | Revisar los cambios antes del despliegue. |

El flujo que propondría sería:

```text
Pull Request
     │
     ▼
Terraform fmt / validate
     │
     ▼
TFLint
     │
     ▼
Trivy
     │
     ▼
Infracost
     │
     ▼
Terraform Plan
     │
     ▼
Review / Approval
     │
     ▼
Terraform Apply
```

Para producción, el `apply` requeriría aprobación previa después de revisar el resultado del `plan`, los controles de seguridad y el impacto estimado en costos.

## 6. Consideraciones de seguridad

Los principales controles que apliqué en la implementación son:

- Customer Managed KMS Key para encriptación.
- Rotación automática de la KMS Key.
- S3 sin acceso público.
- Acceso a S3 únicamente mediante TLS.
- Aurora desplegado en subnets privadas.
- Aurora sin acceso público.
- Security Groups con acceso restringido.
- Credenciales de `pgadmin` fuera del código Terraform.
- Credenciales administradas mediante Secrets Manager.
- Acceso al Secret restringido mediante IAM y Resource Policy.
- Terraform State remoto y cifrado.
- Validaciones de seguridad antes del despliegue.

## 7. Despliegue por ambiente

Cada ambiente utiliza un Terraform Workspace y su correspondiente archivo `.tfvars`.

Por ejemplo, para `dev`:

```bash
terraform init

terraform workspace select dev

terraform plan \
  -var-file="workspaces/dev.tfvars"

terraform apply \
  -var-file="workspaces/dev.tfvars"
```

Para crear un nuevo ambiente:

```bash
terraform workspace new staging

terraform plan \
  -var-file="workspaces/staging.tfvars"
```

Con este modelo puedo reutilizar los mismos módulos y mantener separados tanto la configuración como el estado de cada ambiente.