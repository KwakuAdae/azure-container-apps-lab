# Azure Container Apps Lab with Terraform: Website from ACR to Container Apps

A hands-on lab that builds a containerized website, stores it in **Azure Container Registry (ACR)**, and runs it on **Azure Container Apps** with HTTPS, autoscaling (including scale to zero), and blue/green releases using **revisions and traffic splitting**. All infrastructure is defined with **Terraform** (`azurerm` provider).

```
  your laptop / Cloud Shell
          │  az acr build (the image is built in Azure, no local Docker needed)
          ▼
 ┌─ terraform/1-registry ──────────────────────────────────────────────────────────┐
 │ ┌──────────────────────────┐      AcrPull      ┌──────────────────────────────┐ │
 │ │ Azure Container Registry │ ◄──────────────── │ user-assigned managed        │ │
 │ │   website:v1, v2, v3     │                   │ identity (no passwords)      │ │
 │ └──────────────────────────┘                   └──────────────┬───────────────┘ │
 │   resource group · Log Analytics workspace                    │                 │
 └───────────────────────────────────────────────────────────────┼─────────────────┘
 ┌─ terraform/2-app ─────────────────────────────────────────────▼─────────────────┐
 │ Container Apps environment (logs → Log Analytics)                                │
 │   container app "website"   ingress: external HTTPS → port 8080                  │
 │     ├── revision website--v1   80% ──┐                                           │
 │     └── revision website--v2   20% ──┤  ◄── https://website.<env-domain>         │
 │            label "green" ────────────┼───── https://website---green.<env-domain> │
 │   scale: 0 to 5 replicas, HTTP rule (20 concurrent requests per replica)         │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

## What you will learn

- Write Terraform for **Azure Container Registry**, **Log Analytics**, a **managed identity** and an **AcrPull** role assignment
- Build images in the cloud with **ACR Tasks** (`az acr build`)
- Split infrastructure into **two Terraform layers** connected with `terraform_remote_state`, and why the split is needed here
- Define a **Container Apps environment** and a **container app** (`azurerm_container_app`): ingress, registry identity, CPU/memory, probes, and an **HTTP scale rule**
- Watch **scale to zero** and cold starts
- Release new versions as **revisions**, test them on a **label URL**, shift traffic gradually (canary) and roll back, all by changing Terraform variables
- Test Terraform offline with **`terraform test`** and mock providers
- Read container logs with `az containerapp logs show` and Log Analytics

## Project structure

```
azure-container-apps-lab/
├── app/
│   ├── Dockerfile          # nginx (unprivileged, port 8080), version/color baked in at build time
│   ├── nginx.conf          # /health and /version.json endpoints
│   ├── index.html          # the website
│   └── .dockerignore
├── terraform/
│   ├── 1-registry/                 # layer 1: what must exist before the first image
│   │   ├── versions.tf             # providers (azurerm, random)
│   │   ├── variables.tf            # location, prefix, acr_sku ...
│   │   ├── main.tf                 # resource group, Log Analytics, ACR, identity + AcrPull
│   │   ├── outputs.tf              # used by scripts and by layer 2
│   │   ├── terraform.tfvars.example
│   │   └── tests/registry.tftest.hcl
│   └── 2-app/                      # layer 2: environment + container app
│       ├── versions.tf             # provider + remote state of layer 1
│       ├── variables.tf            # image_tag, traffic, scaling
│       ├── main.tf                 # azurerm_container_app_environment, azurerm_container_app
│       ├── outputs.tf              # app_url, label_urls, traffic
│       └── tests/app.tftest.hcl
├── scripts/
│   ├── config.sh               # shared helpers
│   ├── 01-create-registry.sh   # register providers + terraform apply (layer 1)
│   ├── 02-build-image.sh       # az acr build → website:<tag>
│   ├── 03-deploy-app.sh        # terraform apply (layer 2), first revision 100%
│   ├── 04-release.sh           # new revision with 0% traffic + "green" label
│   ├── 05-shift-traffic.sh     # canary / cut over / roll back
│   ├── 06-watch-versions.sh    # count which version answers
│   ├── 07-load-test.sh         # watch the scale rule add replicas
│   └── 99-destroy.sh           # terraform destroy, both layers
└── docs/
    ├── concepts.md             # Container Apps vs AKS vs App Service, how it fits together
    ├── revisions-and-traffic.md
    └── troubleshooting.md
```

The scripts are thin wrappers. Every step also shows the plain `terraform` command so you can run it yourself.

## Prerequisites

| Tool | Notes |
|------|-------|
| Azure subscription | A free account works. You need **Owner** or **User Access Administrator** to create the AcrPull role assignment. |
| Terraform 1.7+ | `terraform version` |
| Azure CLI 2.62+ | `az version`. Terraform authenticates with your `az login` session. |
| bash, curl, python3 | For the helper scripts |
| Docker | **Optional.** Only for `02-build-image.sh ... --local` and running the site locally |

**Azure Cloud Shell** (Bash) has Terraform, the Azure CLI and everything else already installed.

```bash
az login
az account set --subscription "<your subscription name or id>"
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)   # the scripts do this for you
```

## Quick start

```bash
git clone https://github.com/KwakuAdae/azure-container-apps-lab.git
cd azure-container-apps-lab

./scripts/01-create-registry.sh        # ~2 min (type yes)
./scripts/02-build-image.sh v1 blue    # ~1 min
./scripts/03-deploy-app.sh v1          # ~3 min (type yes), prints your https URL
```

Open the printed URL. When you are finished: `./scripts/99-destroy.sh`.

---

## Step-by-step guide

### Step 0: (Optional) Run the website locally

```bash
docker build -t website:local --build-arg APP_VERSION=local --build-arg APP_COLOR=orange app/
docker run --rm -p 8080:8080 website:local
# http://localhost:8080   http://localhost:8080/health   http://localhost:8080/version.json
```

The image is `nginx-unprivileged`, listens on **8080**, and runs as a non-root user. The build args `APP_VERSION` and `APP_COLOR` are baked into the page so you can see which version served each request.

### Step 1: Why two Terraform layers?

A container app cannot be created until its image exists in the registry, and the registry is created by Terraform. So the lab splits into:

| Layer | Contains | Applied |
|-------|----------|---------|
| `terraform/1-registry` | resource group, Log Analytics, ACR, managed identity, AcrPull | once |
| *(between them)* | `az acr build` pushes `website:v1` | every new version |
| `terraform/2-app` | Container Apps environment, container app, traffic split | first deploy and every release |

Layer 2 reads layer 1's outputs with a `terraform_remote_state` data source (local state files, to keep the lab simple):

```hcl
data "terraform_remote_state" "registry" {
  backend = "local"
  config  = { path = "${path.module}/../1-registry/terraform.tfstate" }
}
```

> For a team, store both states in an Azure Storage account (`backend "azurerm"`) so state is shared and locked.

### Step 2: Create the registry layer

```bash
./scripts/01-create-registry.sh
```

The script registers the resource providers (`Microsoft.App`, `Microsoft.OperationalInsights`, `Microsoft.ContainerRegistry`, `Microsoft.ManagedIdentity`), then runs:

```bash
terraform -chdir=terraform/1-registry init
terraform -chdir=terraform/1-registry apply
```

What `main.tf` creates:

1. **Resource group** `rg-acalab` in `eastus` (change with `terraform.tfvars`, see `terraform.tfvars.example`).
2. **Log Analytics workspace**: the Container Apps environment sends container output and system events here.
3. **Azure Container Registry** on the **Basic** SKU with `admin_enabled = false`. The name must be globally unique, so a `random_string` suffix is added (e.g. `acracalabk2m9q`).
4. **User-assigned managed identity** `id-acalab-acrpull` and an **AcrPull** role assignment scoped to the registry only.

Why a user-assigned identity? It exists *before* the app does, so the role assignment is already in place when the app pulls its first image. A system-assigned identity is only created with the app, so the very first image pull would fail.

Check it:

```bash
terraform -chdir=terraform/1-registry output
az acr show -n $(terraform -chdir=terraform/1-registry output -raw acr_name) \
  --query "{server:loginServer, sku:sku.name, admin:adminUserEnabled}" -o table
```

### Step 3: Build and push the image with ACR Tasks

```bash
./scripts/02-build-image.sh v1 blue
```

`az acr build` uploads the `app/` folder, builds it **inside Azure** for `linux/amd64`, and pushes `website:v1`. You do not need Docker, and it works the same from an Apple Silicon Mac.

Build the versions you will release later now, so they are ready:

```bash
./scripts/02-build-image.sh v2 green
./scripts/02-build-image.sh v3 orange
```

> Prefer your own Docker? `./scripts/02-build-image.sh v1 blue --local` runs `az acr login`, `docker build` and `docker push`.

### Step 4: Deploy the container app

```bash
./scripts/03-deploy-app.sh v1
# same as:
terraform -chdir=terraform/2-app init
terraform -chdir=terraform/2-app apply -var image_tag=v1
```

The important parts of `terraform/2-app/main.tf`:

```hcl
resource "azurerm_container_app" "website" {
  revision_mode = "Multiple"                 # old revisions keep running → traffic splitting

  identity {                                 # the identity from layer 1 ...
    type         = "UserAssigned"
    identity_ids = [local.identity_id]
  }
  registry {                                 # ... is used to pull from ACR, no passwords
    server   = local.acr_login_server
    identity = local.identity_id
  }

  ingress {
    external_enabled = true                  # public HTTPS with a managed certificate
    target_port      = 8080
    dynamic "traffic_weight" { ... }         # from var.traffic
  }

  template {
    revision_suffix = var.image_tag          # revision name: website--v1
    min_replicas    = 0                      # scale to zero
    max_replicas    = 5
    container {
      image  = "${local.acr_login_server}/website:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"
      liveness_probe  { ... path = "/health" }
      readiness_probe { ... path = "/health" }
    }
    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = "20"             # one replica per ~20 concurrent requests
    }
  }
}
```

Open the printed URL and you see the blue **v1** page. Try the endpoints:

```bash
APP_URL=$(terraform -chdir=terraform/2-app output -raw app_url)
curl -s "$APP_URL/health"
curl -s "$APP_URL/version.json"
az containerapp revision list -n website -g rg-acalab -o table
```

### Step 5: Release v2 as a new revision (blue/green)

```bash
./scripts/04-release.sh v2 v1
```

This applies layer 2 with:

```bash
terraform -chdir=terraform/2-app apply \
  -var image_tag=v2 \
  -var 'traffic=[{tag="v1", percent=100}, {tag="v2", percent=0, label="green"}]'
```

- Changing `image_tag` changes the **template**, so Container Apps creates revision **`website--v2`**.
- `traffic` keeps **100% on v1** and gives v2 **0%** plus the label **green**.
- The label gives v2 its own URL: `https://website---green.<env-domain>` (note the **three** dashes). It is printed as the `label_urls` output.

Open the **green** URL and you see v2. The **production** URL still shows v1. Both versions are running, and you test the new one before any user sees it.

### Step 6: Shift traffic gradually, then cut over

```bash
./scripts/05-shift-traffic.sh v1 20     # canary: 20% v2, 80% v1
./scripts/06-watch-versions.sh 40
#   ~32 v1 blue
#    ~8 v2 green

./scripts/05-shift-traffic.sh v1 50
./scripts/05-shift-traffic.sh v1 100    # cut over: 100% v2
```

Each one is a normal Terraform apply that only changes the `traffic_weight` blocks. Changing traffic is a *configuration* change, so it does **not** create a new revision:

```bash
terraform -chdir=terraform/2-app apply -var image_tag=v2 \
  -var 'traffic=[{tag="v1", percent=80}, {tag="v2", percent=20, label="green"}]'
```

**Roll back** at any time, instantly, because v1 is still running:

```bash
./scripts/05-shift-traffic.sh v1 0      # 100% back to v1
```

Then release v3 the same way: `./scripts/04-release.sh v3 v2` and shift traffic.

> Prefer files over long `-var` flags? Put `image_tag` and `traffic` in `terraform/2-app/terraform.tfvars` and just run `terraform apply`. That makes every release a reviewable change in Git.

More detail: [docs/revisions-and-traffic.md](docs/revisions-and-traffic.md).

### Step 7: Autoscaling and scale to zero

```bash
./scripts/07-load-test.sh 120 60     # 2 minutes, 60 parallel workers
```

You will see the replica count climb as the HTTP rule reacts:

```
14:02:10  replicas of website--v2: 1
14:02:25  replicas of website--v2: 3
14:02:40  replicas of website--v2: 5
```

Stop sending traffic and wait about 5 minutes: the replica count drops to **0**, and the next request has a short *cold start*. For a site that must always answer instantly, keep one replica warm:

```bash
./scripts/02-build-image.sh v4 blue
terraform -chdir=terraform/2-app apply -var image_tag=v4 -var min_replicas=1 \
  -var 'traffic=[{tag="v4", percent=100}]'
```

> `min_replicas` lives in the template, so changing it creates a new revision, and a revision suffix can only be used once. Combine scaling changes with a new image tag (or add a separate suffix variable).

### Step 8: Logs and monitoring

```bash
az containerapp logs show -n website -g rg-acalab --follow --tail 20   # nginx access logs, live
az containerapp logs show -n website -g rg-acalab --type system        # pulls, scaling, probes
az containerapp exec -n website -g rg-acalab --command sh              # shell in a replica
```

Query Log Analytics (logs arrive a few minutes late):

```bash
WS_ID=$(az monitor log-analytics workspace show -g rg-acalab -n log-acalab --query customerId -o tsv)
az monitor log-analytics query -w "$WS_ID" -o table --analytics-query "
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == 'website'
| summarize requests = count() by RevisionName_s, bin(TimeGenerated, 5m)
| order by TimeGenerated desc"
```

In the portal, the app's **Metrics** blade shows *Requests*, *Replica Count* and *CPU Usage* per revision.

### Step 9: Test the Terraform offline

Both layers have tests that run with **mock providers**, so no Azure account is needed:

```bash
terraform -chdir=terraform/1-registry init -backend=false && terraform -chdir=terraform/1-registry test
terraform -chdir=terraform/2-app init -backend=false && terraform -chdir=terraform/2-app test
```

```
tests/app.tftest.hcl... in progress
  run "first_deploy_v1"... pass
  run "blue_green_release"... pass
  run "rejects_split_not_100"... pass
  run "rejects_uppercase_tag"... pass
Success! 4 passed, 0 failed.
```

They check: admin user disabled, AcrPull scoped to the registry, the image comes from your registry, the registry is pulled with the identity, a new revision starts at 0%, the green URL format, and that bad input (split not adding to 100, uppercase tag) is rejected by variable validation.

### Step 10: Clean up

```bash
./scripts/99-destroy.sh
```

Destroys layer 2 first (it depends on layer 1), then layer 1. Everything is gone after about 5 minutes.

---

## Cost

| Resource | Approximate cost |
|----------|------------------|
| Container Apps (Consumption plan) | Per second of vCPU and memory while replicas run, plus requests. The monthly **free grant** (180,000 vCPU-seconds, 360,000 GiB-seconds, 2 million requests per subscription) covers this lab. **Scaled to zero = no compute charge.** |
| Azure Container Registry, Basic | About **$0.17 per day** while it exists |
| Log Analytics | Pay per GB ingested. This lab sends a few MB. |
| ACR Tasks builds | Per second of build time, a few cents |

An afternoon with the lab costs well under $1. Run `./scripts/99-destroy.sh` when you finish.

## Troubleshooting (short list)

| Symptom | Fix |
|---------|-----|
| `MissingSubscriptionRegistration` for `Microsoft.App` | `az provider register -n Microsoft.App --wait` (step 2 does it) |
| Layer 2: `Unable to find remote state` / missing outputs | Apply layer 1 first: `./scripts/01-create-registry.sh` |
| Revision stuck provisioning, system log says `unauthorized` | The AcrPull assignment is still propagating. Wait a minute, rerun the apply |
| Image `manifest unknown` | The tag is not in ACR yet. Run `./scripts/02-build-image.sh <tag>` first |
| `AuthorizationFailed` on the role assignment | You need Owner / User Access Administrator |
| Revision suffix already exists | Suffixes are single-use. Change the template only together with a new image tag |
| `traffic percentages must add up to 100` | Fix the `traffic` variable |
| First request is slow | Cold start from zero replicas. Set `min_replicas = 1` |
| Green URL 404 | Three dashes: `website---green.<domain>`. Check `terraform output label_urls` |

More in [docs/troubleshooting.md](docs/troubleshooting.md).

## Going further

- **Remote state**: move both layers to `backend "azurerm"` in a storage account
- **CI/CD**: a GitHub Actions workflow that runs `az acr build`, then `terraform apply -var image_tag=$GITHUB_SHA` (log in with OIDC, no secrets)
- **Custom domain**: `azurerm_container_app_custom_domain` with a managed certificate
- **Secrets**: `secret` blocks with Key Vault references and the managed identity
- **Private networking**: `infrastructure_subnet_id` and `internal_load_balancer_enabled` on the environment
- **Modules**: wrap layer 2 in a reusable module and deploy a second app (an API with internal ingress)
- **Jobs**: `azurerm_container_app_job` for scheduled or event-driven tasks

## Sister labs

- [azure-aks-terraform-lab](https://github.com/KwakuAdae/azure-aks-terraform-lab): the same idea on Kubernetes (AKS) with Terraform
- [azure-aks-bicep-lab](https://github.com/KwakuAdae/azure-aks-bicep-lab): AKS with Bicep
- [aws-ecs-fargate-terraform-lab](https://github.com/KwakuAdae/aws-ecs-fargate-terraform-lab): the AWS equivalent, ECR + ECS Fargate with Terraform

## Author

**Kwaku Adae**: [github.com/KwakuAdae](https://github.com/KwakuAdae)

## License

[MIT](LICENSE)
