# Revisions and traffic splitting (with Terraform)

## Single vs multiple revision mode

| `revision_mode` | Behaviour | Use for |
|-----------------|-----------|---------|
| `Single` (default) | Each new revision replaces the previous one automatically, with zero downtime | Simple apps, every deploy goes straight to production |
| `Multiple` | Several revisions stay active and you decide how traffic is split | Blue/green, canary, A/B testing |

This lab sets `revision_mode = "Multiple"` in `terraform/2-app/main.tf`.

## What creates a new revision?

| Change | New revision? |
|--------|---------------|
| Anything in `template { }`: image, env vars, CPU/memory, probes, `min_replicas`, scale rules, `revision_suffix` | **Yes**, named `<app>--<revision_suffix>` |
| Ingress, `traffic_weight`, registries, secrets, identity | No (configuration only) |

The lab uses the image tag as the revision suffix (`website--v1`, `website--v2`). A suffix can only be used **once** per app, so a template change must come with a new tag.

## Traffic as a Terraform variable

```hcl
variable "traffic" {
  type = list(object({
    tag     = string
    percent = number
    label   = optional(string)
  }))
}
```

becomes one `traffic_weight` block per entry:

```hcl
dynamic "traffic_weight" {
  for_each = local.traffic
  content {
    revision_suffix = traffic_weight.value.tag
    percentage      = traffic_weight.value.percent
    label           = traffic_weight.value.label
    latest_revision = false
  }
}
```

Variable validation rejects splits that do not add up to 100 and duplicate tags, before anything reaches Azure.

### A full release in tfvars form

`terraform/2-app/terraform.tfvars`, one edit per stage:

```hcl
# 1. new revision, no production traffic, testable on the green URL
image_tag = "v2"
traffic = [
  { tag = "v1", percent = 100 },
  { tag = "v2", percent = 0, label = "green" },
]

# 2. canary
traffic = [
  { tag = "v1", percent = 80 },
  { tag = "v2", percent = 20, label = "green" },
]

# 3. cut over
traffic = [
  { tag = "v2", percent = 100, label = "green" },
]

# rollback at any stage: v1 back to 100 (v1 is still running)
```

Each stage is `terraform plan` (review the diff) and `terraform apply`. In a team this becomes a pull request per stage.

## Labels

A label pins a stable URL to one revision:

```
https://<app>---<label>.<environment default domain>
```

`terraform output label_urls` prints them. Use labels to test a revision before it gets production traffic, or to give testers a fixed "next version" URL.

## "Latest revision" mode

Instead of naming revisions, a traffic entry can follow whatever revision is newest:

```hcl
traffic_weight {
  latest_revision = true
  percentage      = 100
}
```

Every apply that changes the template then goes live immediately (like `Single` mode, but old revisions stay active). This lab pins revisions by name instead, so releases are deliberate.

## Do not mix Terraform and portal/CLI changes

If you change traffic with `az containerapp ingress traffic set` or in the portal, Terraform sees **drift** and puts its own values back on the next apply. Use the CLI to *look*, Terraform to *change*:

```bash
az containerapp ingress traffic show -n website -g rg-acalab -o table
az containerapp revision list -n website -g rg-acalab -o table \
  --query "[].{name:name, active:properties.active, traffic:properties.trafficWeight, replicas:properties.replicas}"
```

## Old revisions

In `Multiple` mode, revisions that no longer get traffic stay **active** (they can still run replicas, and with `min_replicas = 0` they scale to zero). Deactivate ones you will not roll back to:

```bash
az containerapp revision deactivate -n website -g rg-acalab --revision website--v1
```

Revisions are not separate Terraform resources, so this does not cause drift. An inactive revision cannot receive traffic: run `az containerapp revision activate` before rolling back to it.
