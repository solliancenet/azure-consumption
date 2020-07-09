function ExportSubscriptions()
{
    $res = $(az account list --all);
    $subs = ConvertObjectToJson $res

    $subs | 
    ConvertTo-Csv -NoTypeInformation |
    Set-Content C:\temp\accounts.csv
}

function ConvertObject($data)
{
    $str = "";
    foreach($c in $data)
    {
        $str += $c;
    }

    return $str;
}

function ConvertObjectToJson($data)
{
    $json = ConvertObject $data;

    return ConvertFrom-json $json;
}

az login

$res = $(az account list --all)
$subscriptions = ConvertObjectToJson $res

foreach($sub in $subscriptions)
{
    write-host "Check Sub: $($sub.name) [$($sub.id)]";

    az account set --subscription $sub.id;

    $res = $(az group list);
    $resourceGroups = ConvertObjectToJson $res

    $res = $(az consumption usage list --subscription $sub.id --billing-period-name 20200601);
    $consumption = ConvertObjectToJson $res

    $ht = new-object System.Collections.Hashtable;
    foreach($c in $consumption)
    {
        $rgName = ParseValue $c.instanceid "resourcegroups/" "/";

        if (!$rgName)
        {
            $rgName = ParseValue $c.instanceid "resourceGroups/" "/";
        }

        if (!$rgName)
        {
            continue;
        }

        if($ht.ContainsKey($rgName))
        {
            [decimal]$cost = $ht[$rgName];
            
            try
            {
                if ($c.pretaxcost.length -gt 8)
                {
                    $c.pretaxCost = $c.pretaxCost.Substring(0, 10);
                }

                $cost += [Convert]::ToDecimal($c.pretaxCost);
            }
            catch
            {
                write-host $c.pretaxcost;
            }

            $ht[$rgName] = $cost;
        }
        else
        {
        try
            {
                if ($c.pretaxcost.length -gt 8)
                {
                    $c.pretaxCost = $c.pretaxCost.Substring(0, 10);
                }

                [decimal]$cost = [Convert]::ToDecimal($c.pretaxCost);
            }
            catch
            {
                $cost = 0;
                write-host $c.pretaxcost;
            }
            
            $ht.add($rgName, $cost);
        }
    }
    
    foreach($rg in $resourceGroups)
    {
        write-host "Check RG: $($rg.name)";

        <#
        if ($rg.tags.MonthlyCost)
        {
            continue;
        }
        #>

        if (!$rg.tags.Contact)
        {
            $res = $(az monitor activity-log list --resource-group $rg.name)
            $logs = ConvertObjectToJson $res

            $earliest = [datetime]::Parse("1/1/3000");

            foreach($c in $logs)
            {
                if ($c.submissionTimestamp -lt $earliest -and $c.caller -ne "chris@solliance.net")
                {
                    $createdBy = $c.caller;
                    $earliest = $c.submissionTimestamp;
                }   
            }
            
        }

        #deployments
        $res = $(az deployment group list --resource-group $rg.name)
        $deployments = ConvertObjectToJson $res

        $createDate = [DateTime]::Parse("1/1/3000");
        foreach($d in $deployments)
        {
            $cDate = [datetime]::Parse($deployments[0].properties.timestamp);

            if ($cdate -lt $createDate)
            {
                $createdate = $cdate;
            }
        }

        #tags
        write-host "Tags $($rg.tags)";

        $endDate = "8/1/2020";
        $project = $null;
        $cost = $null;
        $createdby = $null;

        #if you know for sure...
        switch($sub.id)
        {
            "YOUR GUID"
            {
                $createdBy = "blah@solliance.net"
                $project = "blah"
                $endDate = "8/1/2020"
            }
        }

        if ($createDate -eq [Datetime]::Parse("1/1/3000"))
        {
            $createdDate = $null;
        }

        #tag the resource group...

        $cost = $ht[$rg.name];
        
        if ($cost -or $cost -eq 0)
        {
            $(az group update --resource-group $rg.Name --set "tags.MonthlyCost=$cost")
        }

        if ($createdby)
        {
            $(az group update --resource-group $rg.Name --set "tags.Contact=$createdBy")
        }

        if ($project)
        {
            $(az group update --resource-group $rg.Name --set "tags.Project=$project")
        }

        if ($createDate)
        {
            $(az group update --resource-group $rg.Name --set "tags.CreateDate=$createDate")
        }

        if ($endDate)
        {
            $(az group update --resource-group $rg.Name --set "tags.EndDate=$endDate")
        }

        if ($false)
        {
            $(az group update --resource-group $rg.name --tags 'Contact=$createdBy' 'EndDate=$endDate' 'Project=$project' "MonthlyCost=$cost")
        }
    }
}