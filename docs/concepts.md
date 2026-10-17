# Concepts

## Where Container Apps fits

| | Azure App Service | **Azure Container Apps** | Azure Kubernetes Service (AKS) |
|---|---|---|---|
| You manage | App settings | Containers, scale rules, revisions | The cluster, node pools, upgrades, add-ons |
| Kubernetes API | No | No (runs on Kubernetes, hidden from you) | Yes, full access |
| Scale to zero | No | **Yes** | Only with extra tooling (KEDA, node autoscaling) |
| Traffic splitting | Deployment slots | **Revisions + weights** | Ingress / service mesh |
| Pricing | Per plan (VMs) | Per second of use (Consumption) or dedicated workload profiles | Per node VM |
| Good for | Web apps and APIs, code or containers | Containerized web apps, APIs, microservices, event-driven jobs | Teams that need Kubernetes itself |

On AWS, the closest service is **ECS on Fargate** (serverless containers) or **App Runner** (the simplest web container hosting).

## The building blocks

**Azure Container Registry (ACR)**
A private Docker registry. `az acr build` (ACR Tasks) builds images inside Azure. The Basic SKU is enough for labs. Standard and Premium add more storage and throughput; Premium adds geo-replication and private endpoints.

**Managed identity + AcrPull**
An identity in Microsoft Entra ID that Azure manages for you. The container app uses it to get a token for the registry, so no username or password is stored anywhere. `AcrPull` is the least-privilege built-in role for pulling images.

**Container Apps environment**
A boundary around a group of apps. Apps in the same environment share a virtual network, a default domain (`<random>.<region>.azurecontainerapps.io`), and a logging destination. Think of it like an ECS cluster or a Kubernetes namespace plus networking.

**Container app**
Your service. It has a configuration (ingress, registries, secrets, revision mode) and a **template** (containers, image, CPU/memory, environment variables, scale rules).

**Revision**
An immutable snapshot of the template. Any change to the template (new image, new env var, new scale setting) creates a new revision named `<app>--<suffix>`. Changes to configuration only (like traffic weights) do not.

**Ingress**
A built-in HTTPS front end (Envoy) with a managed certificate. `external` means reachable from the internet; `internal` means only from inside the environment. It also does the traffic splitting between revisions.

**Scale rules**
Built on KEDA. This lab uses an HTTP rule (concurrent requests per replica). Others: CPU, memory, Azure Service Bus queue length, Event Hubs, and any KEDA scaler. With `min-replicas 0`, an idle app has no running replicas and costs nothing for compute.

## Request flow

```
browser ──HTTPS──► environment ingress (Envoy, TLS)
                       │   weights: website--v1 80%, website--v2 20%
                       ├──► replica of website--v1 :8080 (nginx)
                       └──► replica of website--v2 :8080 (nginx)
```

If the selected revision has 0 replicas, the ingress holds the request while a replica starts (cold start).

## Image pull flow

```
container app ──(managed identity token)──► Microsoft Entra ID
              ──(token, AcrPull)──────────► <acr>.azurecr.io/website:v2
```

## Building blocks as Terraform resources

| Concept | Terraform resource | Layer |
|---------|--------------------|-------|
| Resource group | `azurerm_resource_group` | 1-registry |
| Log Analytics workspace | `azurerm_log_analytics_workspace` | 1-registry |
| Container registry | `azurerm_container_registry` | 1-registry |
| Managed identity | `azurerm_user_assigned_identity` | 1-registry |
| AcrPull permission | `azurerm_role_assignment` | 1-registry |
| Container Apps environment | `azurerm_container_app_environment` | 2-app |
| Container app, revisions, traffic split | `azurerm_container_app` (`template`, `ingress.traffic_weight`) | 2-app |

Revisions are not separate resources: Container Apps creates one whenever the `template` block changes.
