# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Development repo for adding Azure Virtual Desktop (AVD) reporting to the [AsBuiltReport.Microsoft.Azure](https://github.com/AsBuiltReport/AsBuiltReport.Microsoft.Azure) module. This is **not** a standalone module — code here will be contributed upstream via PR to `AsBuiltReport/AsBuiltReport.Microsoft.Azure` (dev branch).

| Item | Detail |
|------|--------|
| GitHub repo | `https://github.com/cse-gh/Get-AbrAzDesktopVirtualization` |
| Upstream | `https://github.com/AsBuiltReport/AsBuiltReport.Microsoft.Azure` |
| PR target | `dev` branch |
| Current version | **0.3.0** |
| PowerShell | 7+ required (`pwsh`, not `powershell.exe`) |

## Commands

```powershell
# Lint
Invoke-ScriptAnalyzer -Path .\Src\ -Recurse -ReportSummary

# Test module loads (after copying files to installed module path)
Import-Module AsBuiltReport.Microsoft.Azure -Force

# Generate test report (requires Azure auth + MFA)
$cred = Get-Credential
New-AsBuiltReport -Report Microsoft.Azure -Target '<subscription-id>' -Credential $cred -MFA -Format HTML -OutputFolderPath .\TestOutput

# Install modules (use AllUsers to avoid OneDrive sync issues on this machine)
Install-Module <name> -Scope AllUsers
```

## Architecture

### Single Consolidated Function

The repo contains one function — `Get-AbrAzDesktopVirtualization` (`Src/Private/Get-AbrAzDesktopVirtualization.ps1`, ~587 lines) — that covers all five AVD resource types: Host Pools, Session Hosts, Application Groups, Workspaces, and Scaling Plans. This is a deliberate design choice; the function will be added to the upstream module's `Src/Private/` directory.

### Internationalization

All user-facing strings are externalized in `Language/<culture>/MicrosoftAzure.psd1` files (en-US, en-GB, es-ES, fr-FR, de-DE). Each file contains a `GetAbrAzDesktopVirtualization` key with ~91 localized strings accessed via:

```powershell
$LocalizedData = $reportTranslate.GetAbrAzDesktopVirtualization
Section -Style Heading4 $LocalizedData.Heading { ... }
```

**Never hardcode user-facing text.** All labels, headings, status values, and warning messages must use `$LocalizedData.*` lookups. When adding new strings, add them to all five language files.

### InfoLevel Tiered Rendering

Content is gated by `$InfoLevel.DesktopVirtualization` (0=off, 1-4 = increasing detail):

| Level | Rendering |
|-------|-----------|
| 1 | Summary tables (`List = $false`) for each resource type |
| 2 | Per-resource vertical detail sections (`List = $true`), session host tables with health checks, RDP properties, agent update config |
| 3 | Registration token info, per-app-group published applications, per-scaling-plan schedule breakdowns |
| 4 | Per-session-host vertical detail sections, active user sessions per host pool |

### Health Checks (all implemented)

| Check | Condition | Style | Config key |
|-------|-----------|-------|------------|
| Session Host Unavailable | Status != "Available" | Warning | `SessionHostHealth` |
| Session Host Drain Mode | AllowNewSession = false | Info | `DrainMode` |
| Registration Token Expired | Token past expiration | Warning | `RegistrationExpiry` |
| No Session Hosts | Host pool has 0 session hosts | Bold paragraph | `NoSessionHosts` |
| Host Pool at Capacity | Sessions >= MaxSessionLimit × host count | Bold paragraph | `HostPoolCapacity` |

All gated by `$Healthcheck.DesktopVirtualization.<key>`.

## Get-AbrAz* Function Pattern

Every resource function in the upstream module follows this structure — **new code must conform**:

```powershell
function Get-AbrAzResourceType {
    [CmdletBinding()]
    param ()
    begin {
        Write-PScriboMessage "ResourceType InfoLevel set at $($InfoLevel.ResourceType)."
    }
    process {
        Try {
            if ($InfoLevel.ResourceType -gt 0) {
                $resources = Get-AzSomeResource | Sort-Object Name
                if ($resources) {
                    Write-PscriboMessage "Collecting Azure ResourceType information."
                    Section -Style Heading4 'Resource Type' {
                        # Build [Ordered]@{} PSCustomObject array
                        # Render via Table @TableParams
                    }
                }
            }
        } Catch {
            Write-PScriboMessage -IsWarning $($_.Exception.Message)
        }
    }
    end {}
}
```

**Critical rules:**
- Check `$InfoLevel` before executing (0 = disabled)
- No parameters — all context from global variables set by the orchestrator
- Never return values — render directly via PScribo (`Section`, `Paragraph`, `Table`, `BlankLine`)
- Wrap in Try/Catch with `Write-PScriboMessage -IsWarning`
- Use `[Ordered]@{}` for predictable column order
- Cache API calls when iterating (avoid Azure throttling)

## Global Variables (set by orchestrator)

| Variable | Type | Purpose |
|----------|------|---------|
| `$InfoLevel` | Hashtable | Detail level per resource (0=off, 1-4) |
| `$Options` | Hashtable | `ShowSectionInfo`, `ShowTags` |
| `$Report` | Hashtable | `ShowTableCaptions` |
| `$Healthcheck` | Hashtable | Boolean flags per resource type |
| `$AzSubscription` | Object | Current subscription being processed |
| `$AzLocationLookup` | Hashtable | Location code → display name |
| `$AzSubscriptionLookup` | Hashtable | Subscription ID → name |
| `$reportTranslate` | Hashtable | Localized string data per function |

## PScribo Quick Reference

```powershell
Section -Style Heading4 'Title' { ... }                    # TOC section
Section -Style NOTOCHeading5 -ExcludeFromTOC 'Title' { }   # Detail section (no TOC)
Paragraph "text"                                            # Text block
BlankLine                                                   # Spacing
$data | Table @TableParams                                  # Render table
$data | Set-Style -Style Warning -Property 'Status'         # Health check highlighting
Write-PScriboMessage "msg"                                  # Console logging (not in report)
```

Table config: `List = $false` for horizontal summary, `List = $true` for vertical key-value (use `ColumnWidths = 40, 60`). `ColumnWidths` must sum to 100.

## AVD-Specific Gotchas

- **Tag handling**: AVD resources use `TrackedResourceTags` type, not standard hashtables. Access via `.Tag.Keys` and `.Tag.AdditionalProperties[$key]` (not `.Tag[$key]`).
- **Session host names**: Must extract hostname from compound name format — use `($SH.Name.Split('/')[-1] -split '\.')[0]`.
- **Resource group from ID**: Many AVD cmdlets don't return ResourceGroupName directly — extract via `$Resource.Id.Split('/')[4]`.
- **Personal vs Pooled host pools**: Session host tables show different columns based on `$AzHostPool.HostPoolType` (Personal adds Assigned User column).

## Integration Checklist (for upstream PR)

1. Copy `Src/Private/Get-AbrAzDesktopVirtualization.ps1` to module's `Src/Private/`
2. Merge `GetAbrAzDesktopVirtualization` string block from each `Language/<culture>/MicrosoftAzure.psd1` into parent module's language files
3. Add `"DesktopVirtualization" = "Get-AbrAzDesktopVirtualization"` to `$SectionFunctionMap` in orchestrator
4. Add `"DesktopVirtualization"` to `$DefaultSectionOrder` in orchestrator
5. Add `DesktopVirtualization` entries to module JSON: `SectionOrder`, `InfoLevel`, `HealthCheck`

## Parent Module Reference

Installed at `C:\Program Files\WindowsPowerShell\Modules\AsBuiltReport.Microsoft.Azure\0.2.0\`. Key reference files:
- `Src/Public/Invoke-AsBuiltReport.Microsoft.Azure.ps1` — orchestrator
- `Src/Private/Get-AbrAzAvailabilitySet.ps1` — simplest function (InfoLevel 1 only)
- `Src/Private/Get-AbrAzVirtualMachine.ps1` — complex example (nested resources, InfoLevel 2+, health checks)
- `Src/Private/Get-AbrAzKeyVault.ps1` — good multi-level InfoLevel example
