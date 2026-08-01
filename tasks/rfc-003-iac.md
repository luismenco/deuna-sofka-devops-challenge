# RFC-003 — Infraestructura AWS con Terraform

## 1. Contexto

La infraestructura requerida se implementa utilizando **Terraform**, manteniendo los recursos AWS como código y permitiendo desplegar la misma arquitectura en diferentes ambientes.

La solución tiene los siguientes componentes:

- VPC con subnets públicas y privadas.
- AWS KMS para encriptación de los servicios y los datos.
- Amazon S3 para almacenamiento.
- Amazon Aurora PostgreSQL.
- AWS Secrets Manager para las credenciales de Aurora.

La implementación tiene una estructura modular, reutilizable y con controles de seguridad aplicados desde IaC.

## 2. Estructura del repositorio

El código Terraform se encuentra organizado dentro del directorio `terraform/`:

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

Los módulos encapsulan la implementación de cada componente y el módulo raíz define las dependencias entre ellos.

Los archivos dentro de `workspaces/` contienen las configuraciones específicas de cada ambiente, como CIDRs, Availability Zones, configuración de NAT Gateway y parámetros que pueden variar entre ambientes `dev`, `staging` y `prod`.

Terraform Workspaces se utilizan para mantener un estado independiente por ambiente:

```bash
terraform workspace select dev

terraform plan -var-file="workspaces/dev.tfvars"

terraform apply -var-file="workspaces/dev.tfvars"

terraform destroy -var-file="workspaces/dev.tfvars"
```

## 3. Componentes implementados

### 3.1 VPC

El módulo `vpc` crea la infraestructura base de red:

- VPC.
- Subnets públicas distribuidas entre Availability Zones.
- Subnets privadas distribuidas entre Availability Zones.
- Internet Gateway para las subnets públicas.
- NAT Gateway configurable para salida a Internet desde las subnets privadas. (futuros componentes como servicios de ecs o lambdas)
- Route Tables y asociaciones correspondientes.

Aurora se despliega únicamente sobre las subnets privadas.

### 3.2 KMS

Se crea una Customer Managed KMS Key simétrica utilizada para encriptar los recursos que manejan información sensible.

La configuración incluye:

- `SYMMETRIC_DEFAULT`.
- Uso `ENCRYPT_DECRYPT`.
- Rotación automática habilitada.
- Ventana de eliminación configurable.
- Alias para facilitar su identificación.
- Key Policy basada en least privilege.

La policy diferencia entre ARNS que administran la llave y ARNS que únicamente requieren utilizarla para operaciones criptográficas.

### 3.3 S3

El módulo S3 implementa:

- Server-side encryption con la KMS Key creada.
- S3 Bucket Key habilitada.
- Versionado.
- Block Public Access.
- `BucketOwnerEnforced`.
- Lifecycle policy para costos (finops)
- Restricción de conexiones sin TLS mediante Bucket Policy(https only).

El lifecycle permite mover información a clases de almacenamiento de menor costo y administrar versiones anteriores de los objetos.

### 3.4 Aurora PostgreSQL

El cluster Aurora PostgreSQL se despliega utilizando las subnets privadas de la VPC.

La configuración incluye:

- Encriptación en reposo con KMS.
- DB Subnet Group privado.
- Security Group dedicado.
- Puerto PostgreSQL `5432` accesible únicamente desde Security Groups autorizados.
- Backups automáticos.
- Deletion Protection configurable por ambiente.
- Final Snapshot para ambientes que lo requieran.
- Performance Insights.
- Enhanced Monitoring.

No se permite acceso público a las instancias del cluster.

### 3.5 Secrets Manager

Las credenciales administrativas de Aurora son gestionadas directamente por RDS utilizando:

```hcl
master_username              = "pgadmin"
manage_master_user_password  = true
```

Esto permite que AWS genere y almacene las credenciales `username/password` en AWS Secrets Manager sin administrar la contraseña directamente desde Terraform.
la credencial rota cada 7 dias por defectos, https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-secrets-manager.html?utm_source=chatgpt.com#rds-secrets-manager-overview 
El Secret utiliza la Customer Managed KMS Key definida para la solución.

El acceso al Secret se restringe mediante una Resource Policy a principals explícitamente autorizados.

Para el ambiente de prueba se autoriza al principal utilizado para ejecutar Terraform. En un ambiente productivo este acceso debe asignarse únicamente a los IAM Roles de los workloads que requieran conectarse a la base de datos.

## 4. Estado remoto de Terraform

El estado de Terraform se almacena remotamente en Amazon S3.

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

Cada Terraform Workspace mantiene un estado independiente, evitando compartir el mismo estado entre `dev`, `staging` y `prod`.

El backend utiliza:

- S3 para almacenamiento remoto.
- Cifrado del state en reposo.
- State locking mediante S3 lockfile.
- Versionado del bucket de state para recuperación ante cambios accidentales.

No se utiliza DynamoDB para locking, utilizando el mecanismo de locking soportado actualmente por el backend S3.

El bucket utilizado como backend debe provisionarse previamente y mantenerse separado del state administrado por este repositorio.

## 5. Validaciones antes del apply

Antes de ejecutar cambios sobre AWS se propone ejecutar validaciones sintácticas, funcionales y de seguridad.

El flujo mínimo es:

```bash
terraform fmt -check -recursive

terraform validate

terraform plan \
  -var-file="workspaces/dev.tfvars"
```

Adicionalmente se pueden integrar las siguientes herramientas en CI/CD:

| Herramienta | Uso |
| --- | --- |
| `terraform fmt` | Validación de formato |
| `terraform validate` | Validación de configuración Terraform |
| `TFLint` | Detección de errores y malas prácticas Terraform/AWS |
| `Trivy` | Análisis de seguridad y configuracion de IaC |
| `Infracost` | Estimación de costos |
| `terraform plan` | Revisión de cambios antes del despliegue |

## 6. Consideraciones de seguridad

La implementación aplica los siguientes controles:

- Encriptación con Customer Managed KMS Key.
- Rotación automática de la KMS Key.
- S3 sin acceso público.
- Acceso a S3 únicamente mediante TLS.
- Aurora desplegado en subnets privadas.
- Aurora sin acceso público.
- Security Groups basados en least privilege.
- Credenciales de base de datos almacenadas en Secrets Manager.
- Contraseña de `pgadmin` fuera del código Terraform.
- Acceso al Secret restringido por IAM y Resource Policy.
- Estado Terraform almacenado remotamente y cifrado.
- Validación de seguridad de IaC antes del despliegue.

## 7. Despliegue por ambiente

Cada ambiente utiliza un Terraform Workspace y su correspondiente archivo de variables.

Ejemplo para `dev`:

```bash
terraform init

terraform workspace select dev

terraform plan \
  -var-file="workspaces/dev.tfvars"

terraform apply \
  -var-file="workspaces/dev.tfvars"
```

Para un nuevo ambiente:

```bash
terraform workspace new staging

terraform plan \
  -var-file="workspaces/staging.tfvars"
```

Este modelo permite reutilizar los mismos módulos manteniendo configuración y estado independientes para cada ambiente.