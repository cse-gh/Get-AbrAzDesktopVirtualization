function Get-AbrAzDesktopVirtualization {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Azure Virtual Desktop information
    .DESCRIPTION
        Documents the configuration of Azure Virtual Desktop including Host Pools,
        Session Hosts, Application Groups, Workspaces, and Scaling Plans.
    .NOTES
        Version:        0.2.0
        Author:         Scott Eno
        Github:         cse-gh
    .EXAMPLE

    .LINK

    #>
    [CmdletBinding()]
    param (
    )

    begin {
        Write-PScriboMessage "DesktopVirtualization InfoLevel set at $($InfoLevel.DesktopVirtualization)."
    }

    process {
        Try {
            if ($InfoLevel.DesktopVirtualization -gt 0) {
                $AzWvdHostPools = Get-AzWvdHostPool | Sort-Object Name
                if ($AzWvdHostPools) {
                    Write-PScriboMessage "Collecting Azure Virtual Desktop information."
                    Section -Style Heading4 'Azure Virtual Desktop' {
                        if ($Options.ShowSectionInfo) {
                            Paragraph "Azure Virtual Desktop is a desktop and app virtualization service that runs on Azure. It enables users to connect to a full desktop or published applications from virtually anywhere."
                            BlankLine
                        }

                        #region Host Pools
                        Section -Style Heading5 'Host Pools' {
                            Paragraph "The following table summarizes the host pools within the $($AzSubscription.Name) subscription."
                            BlankLine

                            $AzHostPoolInfo = @()
                            foreach ($AzHostPool in $AzWvdHostPools) {
                                $InObj = [Ordered]@{
                                    'Name' = $AzHostPool.Name
                                    'Friendly Name' = if ($AzHostPool.FriendlyName) { $AzHostPool.FriendlyName } else { '--' }
                                    'Resource Group' = $AzHostPool.Id.Split('/')[4]
                                    'Location' = $AzLocationLookup."$($AzHostPool.Location)"
                                    'Type' = $AzHostPool.HostPoolType
                                    'Load Balancer' = $AzHostPool.LoadBalancerType
                                    'Max Session Limit' = $AzHostPool.MaxSessionLimit
                                    'Start VM on Connect' = $AzHostPool.StartVMOnConnect
                                    'Validation Environment' = $AzHostPool.ValidationEnvironment
                                }

                                if ($Options.ShowTags) {
                                    $InObj['Tags'] = if ($null -eq $AzHostPool.Tag -or $AzHostPool.Tag.Count -eq 0) {
                                        'None'
                                    } else {
                                        ($AzHostPool.Tag.Keys | ForEach-Object { "$_`:`t$($AzHostPool.Tag.AdditionalProperties[$_])" }) -join [Environment]::NewLine
                                    }
                                }

                                $AzHostPoolInfo += [PSCustomObject]$InObj
                            }

                            if ($InfoLevel.DesktopVirtualization -ge 2) {
                                # Detailed: one section per host pool with session hosts
                                foreach ($AzHostPool in $AzWvdHostPools) {
                                    $HostPoolDetail = $AzHostPoolInfo | Where-Object { $_.'Name' -eq $AzHostPool.Name }
                                    Section -Style NOTOCHeading5 -ExcludeFromTOC "$($AzHostPool.Name)" {
                                        $TableParams = @{
                                            Name = "Host Pool - $($AzHostPool.Name)"
                                            List = $true
                                            ColumnWidths = 40, 60
                                        }
                                        if ($Report.ShowTableCaptions) {
                                            $TableParams['Caption'] = "- $($TableParams.Name)"
                                        }
                                        $HostPoolDetail | Table @TableParams

                                        # RDP Properties
                                        if ($AzHostPool.CustomRdpProperty) {
                                            Section -Style NOTOCHeading6 -ExcludeFromTOC 'Custom RDP Properties' {
                                                $RdpProps = $AzHostPool.CustomRdpProperty -split ';' | Where-Object { $_ -ne '' } | Sort-Object
                                                $RdpInfo = @()
                                                foreach ($prop in $RdpProps) {
                                                    $parts = $prop -split ':', 2
                                                    $RdpInfo += [PSCustomObject][Ordered]@{
                                                        'Property' = $parts[0].Trim()
                                                        'Value' = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
                                                    }
                                                }
                                                $TableParams = @{
                                                    Name = "RDP Properties - $($AzHostPool.Name)"
                                                    List = $false
                                                    ColumnWidths = 50, 50
                                                }
                                                if ($Report.ShowTableCaptions) {
                                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                                }
                                                $RdpInfo | Table @TableParams
                                            }
                                        }

                                        # Agent Update Configuration
                                        if ($AzHostPool.AgentUpdateType) {
                                            Section -Style NOTOCHeading6 -ExcludeFromTOC 'Agent Update Configuration' {
                                                $AgentInfo = [PSCustomObject][Ordered]@{
                                                    'Update Type' = $AzHostPool.AgentUpdateType
                                                    'Maintenance Window' = if ($AzHostPool.AgentUpdateMaintenanceWindow) {
                                                        ($AzHostPool.AgentUpdateMaintenanceWindow | ConvertFrom-Json | ForEach-Object { "$($_.dayOfWeek) at $($_.hour):00" }) -join ', '
                                                    } else { '--' }
                                                    'Time Zone' = if ($AzHostPool.AgentUpdateMaintenanceWindowTimeZone) { $AzHostPool.AgentUpdateMaintenanceWindowTimeZone } else { '--' }
                                                    'Use Local Time' = $AzHostPool.AgentUpdateUseSessionHostLocalTime
                                                }
                                                $TableParams = @{
                                                    Name = "Agent Update - $($AzHostPool.Name)"
                                                    List = $true
                                                    ColumnWidths = 40, 60
                                                }
                                                if ($Report.ShowTableCaptions) {
                                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                                }
                                                $AgentInfo | Table @TableParams
                                            }
                                        }

                                        # Session Hosts for this Host Pool
                                        $RG = $AzHostPool.Id.Split('/')[4]
                                        $AzSessionHosts = Get-AzWvdSessionHost -ResourceGroupName $RG -HostPoolName $AzHostPool.Name | Sort-Object Name
                                        if ($AzSessionHosts) {
                                            Section -Style NOTOCHeading6 -ExcludeFromTOC 'Session Hosts' {
                                                $SessionHostInfo = @()
                                                foreach ($SH in $AzSessionHosts) {
                                                    $ShName = $SH.Name.Split('/')[-1] -replace '\.ad\.ennead\.com$', ''
                                                    $InObj = [Ordered]@{
                                                        'Name' = $ShName
                                                        'Status' = $SH.Status
                                                        'Health Check' = if ($SH.HealthCheckResult) {
                                                            $checks = $SH.HealthCheckResult | ConvertFrom-Json -ErrorAction SilentlyContinue
                                                            if ($checks) {
                                                                $failed = $checks | Where-Object { $_.healthCheckResult -ne 'HealthCheckSucceeded' }
                                                                if ($failed) {
                                                                    ($failed | ForEach-Object { $_.healthCheckName }) -join ', '
                                                                } else {
                                                                    'Healthy'
                                                                }
                                                            } else { '--' }
                                                        } else { '--' }
                                                        'Sessions' = $SH.Session
                                                        'Allow New Sessions' = $SH.AllowNewSession
                                                        'OS Version' = if ($SH.OSVersion) { $SH.OSVersion } else { '--' }
                                                        'Agent Version' = if ($SH.AgentVersion) { $SH.AgentVersion } else { '--' }
                                                        'Last Heartbeat' = if ($SH.LastHeartBeat) { $SH.LastHeartBeat.ToString('yyyy-MM-dd HH:mm') } else { '--' }
                                                        'Update State' = if ($SH.UpdateState) { $SH.UpdateState } else { '--' }
                                                    }

                                                    # Add assigned user for personal host pools
                                                    if ($AzHostPool.HostPoolType -eq 'Personal') {
                                                        $InObj['Assigned User'] = if ($SH.AssignedUser) { $SH.AssignedUser } else { 'Unassigned' }
                                                    }

                                                    $SessionHostInfo += [PSCustomObject]$InObj
                                                }

                                                # Apply health check styling
                                                if ($Healthcheck.DesktopVirtualization.SessionHostHealth) {
                                                    $SessionHostInfo | Where-Object { $_.'Status' -ne 'Available' } | Set-Style -Style Warning -Property 'Status'
                                                    $SessionHostInfo | Where-Object { $_.'Health Check' -ne 'Healthy' -and $_.'Health Check' -ne '--' } | Set-Style -Style Warning -Property 'Health Check'
                                                }
                                                if ($Healthcheck.DesktopVirtualization.DrainMode) {
                                                    $SessionHostInfo | Where-Object { $_.'Allow New Sessions' -eq $false } | Set-Style -Style Info -Property 'Allow New Sessions'
                                                }

                                                $TableParams = @{
                                                    Name = "Session Hosts - $($AzHostPool.Name)"
                                                    List = $false
                                                    Columns = 'Name', 'Status', 'Health Check', 'Sessions', 'Allow New Sessions', 'Agent Version', 'Last Heartbeat'
                                                    ColumnWidths = 18, 11, 13, 10, 13, 14, 21
                                                }
                                                if ($AzHostPool.HostPoolType -eq 'Personal') {
                                                    $TableParams.Columns = 'Name', 'Status', 'Sessions', 'Assigned User', 'Agent Version', 'Last Heartbeat'
                                                    $TableParams.ColumnWidths = 16, 12, 10, 24, 16, 22
                                                }
                                                if ($Report.ShowTableCaptions) {
                                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                                }
                                                $SessionHostInfo | Table @TableParams
                                            }
                                        }
                                    }
                                }
                            } else {
                                # Summary table (InfoLevel 1)
                                $TableParams = @{
                                    Name = "Host Pools - $($AzSubscription.Name)"
                                    List = $false
                                    Columns = 'Name', 'Friendly Name', 'Type', 'Load Balancer', 'Max Session Limit', 'Start VM on Connect'
                                    ColumnWidths = 18, 20, 12, 15, 15, 20
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $AzHostPoolInfo | Table @TableParams
                            }
                        }
                        #endregion Host Pools

                        #region Application Groups
                        $AzAppGroups = Get-AzWvdApplicationGroup | Sort-Object Name
                        if ($AzAppGroups) {
                            Section -Style Heading5 'Application Groups' {
                                Paragraph "The following table summarizes the application groups within the $($AzSubscription.Name) subscription."
                                BlankLine

                                $AzAppGroupInfo = @()
                                foreach ($AG in $AzAppGroups) {
                                    $HostPoolName = if ($AG.HostPoolArmPath) { $AG.HostPoolArmPath.Split('/')[-1] } else { '--' }
                                    $WorkspaceName = if ($AG.WorkspaceArmPath) { $AG.WorkspaceArmPath.Split('/')[-1] } else { '--' }
                                    $InObj = [Ordered]@{
                                        'Name' = $AG.Name
                                        'Friendly Name' = if ($AG.FriendlyName) { $AG.FriendlyName } else { '--' }
                                        'Type' = $AG.ApplicationGroupType
                                        'Host Pool' = $HostPoolName
                                        'Workspace' = $WorkspaceName
                                        'Resource Group' = $AG.ResourceGroupName
                                        'Location' = $AzLocationLookup."$($AG.Location)"
                                    }

                                    if ($Options.ShowTags) {
                                        $InObj['Tags'] = if ($null -eq $AG.Tag -or $AG.Tag.Count -eq 0) {
                                            'None'
                                        } else {
                                            ($AG.Tag.Keys | ForEach-Object { "$_`:`t$($AG.Tag.AdditionalProperties[$_])" }) -join [Environment]::NewLine
                                        }
                                    }

                                    $AzAppGroupInfo += [PSCustomObject]$InObj
                                }

                                $TableParams = @{
                                    Name = "Application Groups - $($AzSubscription.Name)"
                                    List = $false
                                    Columns = 'Name', 'Friendly Name', 'Type', 'Host Pool', 'Workspace'
                                    ColumnWidths = 25, 20, 15, 20, 20
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $AzAppGroupInfo | Table @TableParams
                            }
                        }
                        #endregion Application Groups

                        #region Workspaces
                        $AzWorkspaces = Get-AzWvdWorkspace | Sort-Object Name
                        if ($AzWorkspaces) {
                            Section -Style Heading5 'Workspaces' {
                                Paragraph "The following table summarizes the AVD workspaces within the $($AzSubscription.Name) subscription."
                                BlankLine

                                $AzWorkspaceInfo = @()
                                foreach ($WS in $AzWorkspaces) {
                                    $AppGroupNames = if ($WS.ApplicationGroupReference) {
                                        ($WS.ApplicationGroupReference | ForEach-Object { $_.Split('/')[-1] }) -join ', '
                                    } else { 'None' }

                                    $InObj = [Ordered]@{
                                        'Name' = $WS.Name
                                        'Friendly Name' = if ($WS.FriendlyName) { $WS.FriendlyName } else { '--' }
                                        'Description' = if ($WS.Description) { $WS.Description } else { '--' }
                                        'Resource Group' = $WS.ResourceGroupName
                                        'Location' = $AzLocationLookup."$($WS.Location)"
                                        'Application Groups' = $AppGroupNames
                                        'Public Network Access' = if ($WS.PublicNetworkAccess) { $WS.PublicNetworkAccess } else { '--' }
                                    }

                                    $AzWorkspaceInfo += [PSCustomObject]$InObj
                                }

                                if ($InfoLevel.DesktopVirtualization -ge 2) {
                                    foreach ($WS in $AzWorkspaceInfo) {
                                        Section -Style NOTOCHeading5 -ExcludeFromTOC "$($WS.Name)" {
                                            $TableParams = @{
                                                Name = "Workspace - $($WS.Name)"
                                                List = $true
                                                ColumnWidths = 40, 60
                                            }
                                            if ($Report.ShowTableCaptions) {
                                                $TableParams['Caption'] = "- $($TableParams.Name)"
                                            }
                                            $WS | Table @TableParams
                                        }
                                    }
                                } else {
                                    $TableParams = @{
                                        Name = "Workspaces - $($AzSubscription.Name)"
                                        List = $false
                                        Columns = 'Name', 'Friendly Name', 'Application Groups', 'Public Network Access'
                                        ColumnWidths = 20, 25, 35, 20
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $AzWorkspaceInfo | Table @TableParams
                                }
                            }
                        }
                        #endregion Workspaces

                        #region Scaling Plans
                        $AzScalingPlans = Get-AzWvdScalingPlan -ErrorAction SilentlyContinue | Sort-Object Name
                        if ($AzScalingPlans) {
                            Section -Style Heading5 'Scaling Plans' {
                                Paragraph "The following table summarizes the scaling plans within the $($AzSubscription.Name) subscription."
                                BlankLine

                                $AzScalingPlanInfo = @()
                                foreach ($SP in $AzScalingPlans) {
                                    $InObj = [Ordered]@{
                                        'Name' = $SP.Name
                                        'Friendly Name' = if ($SP.FriendlyName) { $SP.FriendlyName } else { '--' }
                                        'Resource Group' = $SP.ResourceGroupName
                                        'Location' = $AzLocationLookup."$($SP.Location)"
                                        'Time Zone' = if ($SP.TimeZone) { $SP.TimeZone } else { '--' }
                                        'Exclusion Tag' = if ($SP.ExclusionTag) { $SP.ExclusionTag } else { '--' }
                                        'Host Pool Type' = if ($SP.HostPoolType) { $SP.HostPoolType } else { '--' }
                                    }
                                    $AzScalingPlanInfo += [PSCustomObject]$InObj
                                }

                                $TableParams = @{
                                    Name = "Scaling Plans - $($AzSubscription.Name)"
                                    List = $false
                                    Columns = 'Name', 'Friendly Name', 'Resource Group', 'Location', 'Time Zone'
                                    ColumnWidths = 20, 20, 20, 20, 20
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $AzScalingPlanInfo | Table @TableParams
                            }
                        }
                        #endregion Scaling Plans
                    }
                }
            }
        } Catch {
            Write-PScriboMessage -IsWarning $($_.Exception.Message)
        }
    }

    end {}
}
