# Práctica: de `git push` a producción en AWS

En esta práctica vas a montar, en **tu propia cuenta** de GitHub y de AWS, el mismo
pipeline que vimos en la presentación:

```
 git push ─► CI (pruebas, build, escaneo) ─► imagen en GHCR ─► CD ─► EC2 staging ─► (tú apruebas) ─► EC2 production
```

- **Tiempo:** 45–60 minutos.
- **Costo:** $0 con el plan gratuito de AWS si destruyes todo al terminar (paso 7).
- Los comandos funcionan igual en **PowerShell**, Git Bash, macOS y Linux.

> **¿Por qué hay argumentos entre comillas, como `"-var-file=staging.tfvars"`?**
> PowerShell parte en dos los argumentos que empiezan con `-` y contienen un punto,
> y Terraform responde `No positional arguments are expected`. Con comillas
> funciona en cualquier terminal, así que los dejamos así siempre.

---

## Antes de empezar

Necesitas:

| Herramienta | Para qué | Comprobar |
|---|---|---|
| Cuenta de GitHub | Repositorio, Actions y registro de imágenes (GHCR) | — |
| Cuenta de AWS (el plan *Free* sirve) | Servidores EC2 | — |
| [Git](https://git-scm.com/downloads) | Clonar y subir cambios | `git --version` |
| [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.10 | Crear la infraestructura | `terraform version` |
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | Credenciales y comandos sueltos | `aws --version` |

Configura el AWS CLI con un usuario **administrador** de tu cuenta de práctica y
comprueba que responde:

```bash
aws sts get-caller-identity
```

Si ves tu número de cuenta (`"Account": "1234..."`), estás listo.

---

## Paso 1. Haz tu copia del repositorio

1. En GitHub, abre el repositorio de la práctica y presiona **Fork**. Déjalo **público**
   (los ambientes con aprobación son gratis solo en repos públicos).
2. En tu fork, entra a la pestaña **Actions** y presiona
   **I understand my workflows, go ahead and enable them**.
   En los forks, Actions viene apagado.
3. Clónalo:
   ```bash
   git clone https://github.com/<tu-usuario>/todo-api.git
   cd todo-api
   ```
4. Cambia el usuario del autor por el tuyo en todo el repositorio.
   En VS Code: **Ctrl+Shift+H** → busca `felisfer` → reemplaza por `<tu-usuario>` →
   **Replace All**. Son pocos archivos (`variables.tf`, `CODEOWNERS`, `.env.example`…).
5. Sube el cambio:
   ```bash
   git commit -am "chore: usar mi usuario de GitHub"
   git push
   ```

## Paso 2. Publica la primera imagen

El `push` del paso anterior dispara el workflow **CI**: corre las pruebas, construye
la imagen y la publica en `ghcr.io/<tu-usuario>/todo-api`.

1. En **Actions**, espera a que **CI** termine en verde ✅ (2–4 min).
2. Justo después se ejecuta **CD** y **falla** ❌. Es normal: todavía no hay servidores
   ni credenciales de AWS. Lo arreglamos en los pasos 3 a 5.
3. Haz pública la imagen para que la EC2 pueda descargarla sin contraseña:
   tu perfil de GitHub → **Packages** → `todo-api` → **Package settings** →
   **Change visibility** → **Public**.

## Paso 3. Prepara AWS (bootstrap)

El *bootstrap* se ejecuta **una sola vez** por cuenta y crea:

- Un **bucket S3** donde Terraform guarda el estado de la infraestructura.
- Un **usuario IAM** (`todo-api-github-deploy`) que GitHub Actions usará para desplegar.
  Solo puede buscar instancias y mandarles comandos a las que tienen la etiqueta
  `App=todo-api`; nada más (mínimo privilegio).
- Los archivos `infra/app/staging.s3.tfbackend` y `production.s3.tfbackend`, que le
  dicen a Terraform en qué bucket guardar el estado de cada ambiente.

```bash
cd infra/bootstrap
terraform init
terraform apply
```

Revisa el plan y escribe `yes`. Después crea la **llave de acceso** del usuario:

```bash
aws iam create-access-key --user-name todo-api-github-deploy
```

Copia `AccessKeyId` y `SecretAccessKey` a un lugar seguro y temporal: **el secreto
solo se muestra esta vez**. Nunca lo subas al repositorio.

> **¿Por qué la llave no la crea Terraform?** Terraform guarda en su archivo de estado
> todo lo que crea. Si creara la llave, el secreto quedaría en texto plano en ese archivo.

<details>
<summary><b>¿Por qué un usuario con llaves y no OIDC, como en la presentación?</b></summary>

Lo ideal es **OIDC**: GitHub pide credenciales *temporales* a AWS en cada ejecución
y no se guarda ninguna llave. Pero al preparar esta práctica, AWS respondió:

```
... is not authorized to perform: iam:CreateOpenIDConnectProvider ...
with an explicit deny in a service control policy
```

Algunas cuentas nuevas de AWS pertenecen a una **organización** con una
*Service Control Policy* (SCP): una regla que está **por encima** de IAM y bloquea
ciertas acciones. Un *deny* de una SCP no se puede anular ni siendo administrador.
Puedes ver si tu cuenta pertenece a una organización con:

```bash
aws organizations describe-organization
```

Si `MasterAccountId` no es tu número de cuenta, tu cuenta es miembro de una
organización ajena. Las empresas usan SCPs justamente así: como *guardrails* que
nadie dentro de la cuenta puede saltarse.

Por eso, por defecto, el bootstrap crea un usuario con llaves (**plan B**) y lo
compensamos con permisos mínimos, secretos por ambiente y borrando la llave al
terminar. Si tu cuenta sí permite OIDC, ve a [Opcional: usar OIDC](#opcional-usar-oidc).
</details>

## Paso 4. Configura GitHub

En tu fork: **Settings** → **Environments**. Es posible que `staging` ya aparezca:
GitHub lo crea solo cuando CD intentó desplegar en el paso 2. Si es así, entra a él;
si no, créalo con **New environment**.

1. `staging`:
   En **Environment secrets** → **Add environment secret**, agrega dos:
   - `AWS_ACCESS_KEY_ID` = tu `AccessKeyId`
   - `AWS_SECRET_ACCESS_KEY` = tu `SecretAccessKey`
2. **New environment** → `production` → **Configure environment**:
   - Marca **Required reviewers** y agrégate a ti. Así producción espera tu aprobación.
   - Agrega los **mismos dos secretos**.

Se guardan como secretos *del ambiente* (no del repositorio) para que solo los jobs
de despliegue puedan leerlos, y los de producción solo después de aprobar.

## Paso 5. Crea los servidores

`infra/app` crea **una EC2 por ambiente** (`t3.micro`, incluida en el plan gratuito),
sin puerto 22: se administran con AWS Systems Manager (SSM).

```bash
cd ../app

terraform init "-backend-config=staging.s3.tfbackend"
terraform apply "-var-file=staging.tfvars"

terraform init -reconfigure "-backend-config=production.s3.tfbackend"
terraform apply "-var-file=production.tfvars"
```

Es el **mismo código** para los dos ambientes; solo cambian los archivos de
configuración. `-reconfigure` cambia al estado del otro ambiente.

Espera **2–3 minutos** (la instancia instala Docker y arranca la app) y prueba:

```bash
terraform output url
```

Abre `<url>/health` en el navegador (en PowerShell usa `curl.exe`, no `curl`).
Debes ver `{"status":"ok", ...}`.

## Paso 6. Prueba el pipeline completo

1. Haz un cambio pequeño en una rama, por ejemplo en `src/app.js`, y abre un PR:
   ```bash
   git switch -c feat/mi-cambio
   git commit -am "feat: mi primer cambio desplegado"
   git push -u origin feat/mi-cambio
   ```
2. Revisa que **CI** pase en el PR y haz **merge**.
3. En **Actions** → **CD**: `deploy-staging` corre solo ✅.
4. `deploy-production` espera → **Review deployments** → aprueba ✅.
5. Abre `<url>/health` de cada ambiente: el campo `version` es el SHA de tu commit.

**Rollback:** **Actions** → **CD** → **Run workflow** → elige el ambiente y pega el
SHA de un commit anterior. Como cada imagen se etiqueta con su SHA, regresar es
volver a desplegar una imagen que ya existe.

## Paso 7. Limpia (¡no te lo saltes!)

Destruye los servidores, que son lo que consume horas del plan gratuito:

```bash
cd infra/app

terraform init -reconfigure "-backend-config=production.s3.tfbackend"
terraform destroy "-var-file=production.tfvars"

terraform init -reconfigure "-backend-config=staging.s3.tfbackend"
terraform destroy "-var-file=staging.tfvars"
```

Borra la llave de acceso (es una credencial que ya no necesitas):

```bash
aws iam list-access-keys --user-name todo-api-github-deploy
aws iam delete-access-key --user-name todo-api-github-deploy --access-key-id <AccessKeyId>
```

Comprueba que no quedó ninguna instancia (la tabla debe salir vacía):

```bash
aws ec2 describe-instances --region us-east-2 --filters "Name=tag:Project,Values=todo-api" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output table
```

El bucket y el usuario del bootstrap no cuestan prácticamente nada; puedes dejarlos
para repetir la práctica. Si quieres borrar todo:

1. En la consola de AWS: **S3** → `todo-api-tfstate-<tu-cuenta>` → **Empty**.
   Hazlo desde la consola: el bucket tiene versionado y `aws s3 rm` deja las
   versiones anteriores.
2. `cd infra/bootstrap` y `terraform destroy`.

> Con el plan *Free*, AWS no te cobra aunque olvides algo: la cuenta se cierra sola
> al acabarse los créditos o a los 6 meses. Aun así, limpia: es un buen hábito.

---

## Problemas comunes

| Mensaje | Causa | Solución |
|---|---|---|
| `No positional arguments are expected` | PowerShell partió un argumento con `-` y `.` | Ponlo entre comillas: `"-var-file=staging.tfvars"` |
| `explicit deny in a service control policy` al crear EC2 o el bucket | Tu cuenta solo permite trabajar en una región | Cambia `default` de `region` en `infra/bootstrap/variables.tf` e `infra/app/variables.tf`, y en GitHub crea la variable `AWS_REGION` (**Settings** → **Secrets and variables** → **Actions** → **Variables**) |
| CD: `no hay instancia en ejecución para el ambiente` | No existen los servidores, o están en otra región | Haz el paso 5; revisa que la región coincida |
| CD: `Could not load credentials` o `Credentials could not be loaded` | Faltan los secretos en ese ambiente | Revisa el paso 4: los secretos van en **cada** ambiente |
| CD: `InvalidInstanceId` | La instancia aún no se registra en SSM | Espera 2–3 min y usa **Re-run failed jobs** |
| La EC2 no arranca la app / `docker pull` denegado | La imagen en GHCR es privada | Paso 2, punto 3 |
| `terraform init`: `Failed to read file ... .s3.tfbackend` | No has corrido el bootstrap | Haz el paso 3 |
| `DeleteConflict` al destruir el bootstrap | El usuario todavía tiene llaves | Borra la llave (paso 7) |
| `BucketNotEmpty` al destruir el bootstrap | El bucket tiene versiones | Vacíalo desde la consola (paso 7) |

---

## Opcional: usar OIDC

Si `aws organizations describe-organization` dice que tu cuenta no pertenece a una
organización (o que tú la administras), puedes usar OIDC y no guardar ninguna llave:

```bash
cd infra/bootstrap
terraform apply -var "use_github_oidc=true"
```

Esto reemplaza el usuario por un **proveedor OIDC + rol IAM**. El rol solo acepta jobs
de **tu** repositorio que corren en los ambientes `staging` o `production`
(condición `sub` en `infra/bootstrap/main.tf`). Luego, en GitHub:

1. **Borra** los secretos `AWS_ACCESS_KEY_ID` y `AWS_SECRET_ACCESS_KEY` de ambos ambientes.
2. En **Settings** → **Secrets and variables** → **Actions** → **Variables**, crea
   `AWS_ROLE_ARN` con la salida `github_deploy_role_arn`.

Usa **una** de las dos opciones, no ambas: con la variable y los secretos a la vez,
la action intenta asumir el rol usando las llaves y falla.

## Notas de seguridad

- La llave del plan B es de larga duración: vive solo en los secretos de los ambientes,
  tiene permisos mínimos y se borra al terminar. Si se filtra, desactívala de inmediato:
  `aws iam update-access-key --user-name todo-api-github-deploy --access-key-id <id> --status Inactive`.
- Las instancias no exponen SSH. Para entrar: `aws ssm start-session --target <instance-id>`.
- IMDSv2 obligatorio y disco cifrado.
- El estado de Terraform (`*.tfstate`) y los `.s3.tfbackend` están en `.gitignore`:
  contienen datos de tu cuenta y no se suben.
