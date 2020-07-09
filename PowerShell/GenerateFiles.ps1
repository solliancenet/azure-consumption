function Get-RefreshTokens()
{
    Add-AzureRmAccount
    $context = Get-AzureRmContext
    $cache = $context.TokenCache

    $items = $context.TokenCache.readitems()

    $filePath = "c:\temp\tokens.csv";
    remove-item $filepath

    $line = "TenantId,ClientId,RefreshToken"
    add-content "C:\temp\tokens.csv" $line

    foreach($item in $items)
    {
        $line = "$($item.Tenantid),$($item.ClientId),$($item.RefreshToken)" 
        add-content "C:\temp\tokens.csv" $line
    }
}

function ExportSubscriptions()
{
    $res = $(az account list --all);
    $subs = ConvertObjectToJson $res

    $subs | 
    ConvertTo-Csv -NoTypeInformation |
    Set-Content "C:\temp\accounts.csv"
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

ExportSubscriptions

Get-RefreshTokens
