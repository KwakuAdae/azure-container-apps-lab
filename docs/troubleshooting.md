# Troubleshooting

Start with these three commands. They answer most questions:

```bash
az containerapp revision list -n website -g rg-acalab -o table          # running state per revision
az containerapp logs show -n website -g rg-acalab --type system --tail 50 # image pulls, probes, scaling
az containerapp logs show -n website -g rg-acalab --tail 50               # your container's output
```

## Image pull failures

**Symptom:** the revision stays in `Provisioning` or shows `Failed`. The system log mentions `unauthorized`, `401`, or `manifest unknown`.

| Cause | Check | Fix |
|-------|-------|-----|
| AcrPull missing | `terraform -chdir=terraform/1-registry state list \| grep role_assignment` | `terraform -chdir=terraform/1-registry apply` recreates it |
| Role still propagating | The assignment exists but was created seconds ago | Wait 1 to 2 minutes, then `az containerapp revision restart` |
| Identity not attached to the app | `az containerapp show -n website -g rg-acalab --query identity` | Check the `identity` block in `terraform/2-app/main.tf` and apply |
| Registry not configured for the identity | `az containerapp registry list -n website -g rg-acalab` | Check the `registry` block in `terraform/2-app/main.tf` and apply |
| Tag does not exist | `az acr repository show-tags -n $(terraform -chdir=terraform/1-registry output -raw acr_name) --repository website` | Build it: `./scripts/02-build-image.sh <tag>` |
| Wrong CPU architecture (built on Apple Silicon) | `exec format error` in the logs | Build with `--platform linux/amd64`, or use `az acr build` |

## App is unreachable

| Symptom | Fix |
|---------|-----|
| 404 from the default domain | Ingress is off or internal: `az containerapp ingress show -n website -g rg-acalab` |
| Upstream connect error / 503 | Target port does not match the container. This image listens on **8080** (`target_port` in `main.tf`) |
| Request hangs ~10 seconds, then works | Cold start from zero replicas |
| Label URL fails | Use three dashes: `website---green.<domain>`. Check `terraform -chdir=terraform/2-app output label_urls` |

## Revision did not get traffic

- Traffic is pinned by revision name. New revisions start at 0%. Use `./scripts/05-shift-traffic.sh`.
- Someone changed traffic in the portal or CLI: Terraform puts its own `traffic` values back on the next apply.
- The revision is inactive: `az containerapp revision activate --revision <name>`.
- `--revision-weight` values must add up to 100.

## CLI and subscription errors

| Error | Fix |
|-------|-----|
| `MissingSubscriptionRegistration` | `az provider register -n Microsoft.App --wait` (and the others in `scripts/01-create-registry.sh`) |
| `'containerapp' is misspelled or not recognized` | `az upgrade` or `az extension add -n containerapp --upgrade` |
| `AuthorizationFailed` on role assignment | Your account needs Owner or User Access Administrator |
| `RevisionSuffixAlreadyExists` / suffix in use | You changed the template (e.g. `min_replicas`) without a new `image_tag`. Suffixes are single-use: build and deploy a new tag |
| `The subscription has reached its quota` for environments | Delete unused environments or pick another region |
| ACR name `AlreadyInUse` | Names are global. `terraform -chdir=terraform/1-registry apply -replace=random_string.suffix` |
| `Unable to find remote state` in layer 2 | Apply layer 1 first, and run both layers from the same checkout (layer 2 reads `../1-registry/terraform.tfstate`) |
| `Error acquiring the state lock` | A previous run was interrupted. Make sure no other terraform is running, then `terraform force-unlock <id>` |

## Logs not showing in Log Analytics

Log Analytics ingestion has a delay of 2 to 5 minutes. For live output use `az containerapp logs show --follow`. Tables:

- `ContainerAppConsoleLogs_CL`: your container's stdout/stderr
- `ContainerAppSystemLogs_CL`: platform events (pulls, scaling, probe failures)
