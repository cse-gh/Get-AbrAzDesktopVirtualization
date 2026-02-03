# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Development repo for adding Azure Virtual Desktop (AVD) reporting functions to the existing `AsBuiltReport.Microsoft.Azure` module. This is not a standalone module — the code developed here will be contributed upstream via PR to `AsBuiltReport/AsBuiltReport.Microsoft.Azure` (dev branch).

| Item | Detail |
|------|--------|
| GitHub repo | `https://github.com/cse-gh/Get-AbrAzDesktopVirtualization` |
| Upstream | `https://github.com/AsBuiltReport/AsBuiltReport.Microsoft.Azure` |
| PR target | `dev` branch |
| Current version | **0.1.1** — InfoLevel 3/4 expansion, validated against live environment |
| PowerShell | 7+ required (`pwsh`, not `powershell.exe`) |
| Related project brief | See `TODO-AVD-Module.md` in the companion Infrastructure repo (`storage/Reporting/AsBuiltReport/`) |

## Parent Module Reference

The installed module at `C:\Program Files\WindowsPowerShell\Modules\AsBuiltReport.Microsoft.Azure\0.2.0\` is the reference implementation. Key files:

- `Src/Public/Invoke-AsBuiltReport.Microsoft.Azure.ps1` — orchestrator that calls all `Get-AbrAz*` functions
- `Src/Private/Get-AbrAzAvailabilitySet.ps1` — simplest example (74 lines, InfoLevel 1 only)
- `Src/Private/Get-AbrAzVirtualMachine.ps1` — complex example (nested resources, InfoLevel 2+, health checks, SKU caching)
- `Src/Private/Get-AbrAzKeyVault.ps1` — good multi-level InfoLevel example
- `AsBuiltReport.Microsoft.Azure.json` — config schema (InfoLevel, HealthCheck, Options, Filter)
- `AsBuiltReport.Microsoft.Azure.Style.ps1` — PScribo styles (headings, health check colors, table formatting)

## Get-AbrAz* Function Pattern

Every resource function follows this structure:

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
                        # For InfoLevel 2+: nested Section per resource with List=$true
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
- No parameters — all context comes from global variables set by orchestrator
- Never return values — render directly via PScribo (`Section`, `Paragraph`, `Table`, `BlankLine`)
- Wrap in Try/Catch with `Write-PScriboMessage -IsWarning`
- Use `[Ordered]@{}` for predictable column order in tables
- Cache API calls when iterating (avoid throttling)

## Global Variables Available

Set by the orchestrator, accessible in all `Get-AbrAz*` functions:

| Variable | Type | Purpose |
|----------|------|---------|
| `$InfoLevel` | Hashtable | Detail level per resource (0=off, 1=summary, 2=detailed, 3+=comprehensive) |
| `$Options` | Hashtable | `ShowSectionInfo`, `ShowTags` |
| `$Report` | Hashtable | `ShowTableCaptions` |
| `$Healthcheck` | Hashtable | Boolean flags per resource type |
| `$AzSubscription` | Object | Current subscription being processed |
| `$AzLocationLookup` | Hashtable | Location code → display name |
| `$AzSubscriptionLookup` | Hashtable | Subscription ID → name |

## PScribo Framework Functions

```powershell
Section -Style Heading4 'Title' { ... }                    # Hierarchical sections
Section -Style NOTOCHeading5 -ExcludeFromTOC 'Title' { }   # Detail sections (no TOC entry)
Paragraph "text"                                            # Text block
BlankLine                                                   # Spacing
$data | Table @TableParams                                  # Render table
$data | Set-Style -Style Warning -Property 'Status'         # Health check highlighting
Write-PScriboMessage "msg"                                  # Console logging (not in report)
```

**Table configuration:**
- `List = $false` — horizontal summary table
- `List = $true` — vertical key-value detail table (use `ColumnWidths = 40, 60`)
- `Columns` — which properties to display
- `ColumnWidths` — percentage allocation (must sum to 100)

## Version History

### v0.1.1 (2026-02-02) — InfoLevel 3/4 expansion

Added meaningful content at every InfoLevel tier, validated against live AVD environment:

**InfoLevel 3 additions:**
- **Host Pools**: Registration token info (expiry date/status, always shows even when no active token)
- **Application Groups**: Per-app-group detail sections with published applications list (`Get-AzWvdApplication` for RemoteApp groups)
- **Scaling Plans**: Per-plan detail sections with schedule breakdowns (ramp-up/peak/ramp-down/off-peak hours, capacity thresholds)

**InfoLevel 4 additions:**
- **Session Hosts**: Per-session-host vertical detail sections with OS version, VM resource ID, update state/error, expanded health checks
- **Active Sessions**: Per-host-pool user session listing (`Get-AzWvdUserSession`) — session state, create time, application type

**New health checks:**
- No Session Hosts (bold WARNING paragraph when host pool has zero session hosts)
- Host Pool at Capacity (bold WARNING when total sessions >= max capacity)
- Registration Token Expired (Warning style on token status)

### v0.1.0 (2026-02-02) — Initial working version

Single consolidated function `Get-AbrAzDesktopVirtualization` covering all AVD resource types:
- **Host Pools**: Summary table (InfoLevel 1) + detailed per-pool sections with session hosts (InfoLevel 2+)
- **Application Groups**: Table with host pool and workspace associations
- **Workspaces**: Table with app group references
- **Scaling Plans**: Table with host pool associations (none in current environment)
- **Health checks**: Session host status (Warning if not Available), drain mode (Warning if disabled)
- **Tag handling**: Uses `.Keys` and `.AdditionalProperties[]` for AVD's `TrackedResourceTags` type (not standard hashtable)

## AVD Functions to Implement

| Function | Az Cmdlets | Purpose |
|----------|-----------|---------|
| `Get-AbrAzHostPool` | `Get-AzWvdHostPool` | Host pool config, type, load balancing, max sessions |
| `Get-AbrAzSessionHost` | `Get-AzWvdSessionHost` | Per-host status, health, drain mode, sessions |
| `Get-AbrAzApplicationGroup` | `Get-AzWvdApplicationGroup`, `Get-AzWvdApplication` | App groups, type, assignments |
| `Get-AbrAzWorkspace` | `Get-AzWvdWorkspace` | Workspace-to-app-group mappings |
| `Get-AbrAzScalingPlan` | `Get-AzWvdScalingPlan` | Autoscale schedules |

## Health Checks to Implement

| Check | Condition | Style |
|-------|-----------|-------|
| Session Host Unavailable | Status != "Available" | Warning |
| Session Host Drain Mode | AllowNewSession = false | Info |
| Registration Token Expired | RegistrationInfo expired | Warning |
| Host Pool at Capacity | Sessions >= MaxSessionLimit | Warning |
| No Session Hosts | Host pool has 0 session hosts | Critical |

## Test Environment

- **Subscription:** Ennead Architects (`6881dcf5-a226-446e-a97b-7295cc0d0fb8`)
- **AVD Resource Group:** `RG_US_AVDPOOL`
- **Session Hosts:** ~48 VMs (GPU: GPUPD-*, GPUDEVAVD-*; General: DEVAVD-*, GENAVD-*)
- **Management:** Nerdio Manager for Enterprise (RG_US_NME)
- **Auth:** `Connect-AzAccount -UseDeviceAuthentication` (headless) or interactive MFA

## Commands

```powershell
# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path .\Src\ -Recurse -ReportSummary

# Test module loads (after copying files to installed module path)
Import-Module AsBuiltReport.Microsoft.Azure -Force

# Generate test report
$cred = Get-Credential
New-AsBuiltReport -Report Microsoft.Azure -Target '8a6820ee-066e-4b8f-a6a5-67992142e92b' -Credential $cred -MFA -Format HTML -OutputFolderPath .\TestOutput

# Enumerate AVD resources for discovery
Get-AzWvdHostPool | Format-List *
Get-AzWvdHostPool | ForEach-Object { Get-AzWvdSessionHost -ResourceGroupName $_.Id.Split('/')[4] -HostPoolName $_.Name }
Get-AzWvdApplicationGroup | Format-List *
Get-AzWvdWorkspace | Format-List *
Get-AzWvdScalingPlan | Format-List *
```

## Module Installation Note

Always install PowerShell modules with `-Scope AllUsers` to avoid OneDrive sync issues on this environment. `-Scope CurrentUser` installs to the OneDrive-backed user profile, causing significant delays.
