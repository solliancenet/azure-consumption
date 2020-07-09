## M Queries

So how does it work? Well first you have to generate the two files (`accounts.csv` and `tokens.csv`) using the PowerShell provided. Once you have that, you can build out the Power BI reports.

You need to call the Azure Consumption APIs (currently preview). But you also need to be able to gather all the information across your tenants and subscription in order to do that. You could certainly statically do it, but that's boring, so let's do it dynamically! You are going to create several data source queries:

- AzureSubscriptions
- AllConsumption
- ResourceGroups
- BillingPeriod
- AzureTenants
- Budgets
- Accounts
- TenantId
- Tokens

## Getting Tokens

If you have a refresh token, you are good for 90 days. As long as it is used and isn't specifically `destroyed` by an admin a daily refresh should keep it alive. You can use the following to get a new access token using the refresh token:

```PowerShell
clientId = Table.SelectRows(Tokens, each ([TenantId] = Id))[ClientId]{0},
refreshToken = Table.SelectRows(Tokens, each ([TenantId] = Id))[RefreshToken]{0},
apiUrl = "https://login.microsoftonline.com/" & TenantId & "/oauth2/token",
body = "client_id=" & clientId & "&grant_type=refresh_token&refresh_token=" & refreshToken,
Auth = Json.Document(Web.Contents(apiUrl, [Content = Text.ToBinary(body), Headers = [Accept = "application/json", #"Content-Type" = "application/x-www-form-urlencoded"]])),
accessToken = Auth[access_token],
```

> **NOTE** The client id is the Azure PowerShell client id `1950a258-227b-4e31-a9cf-717495945fc2`

Once you have the access token, you can make calls to the Azure Billing endpoints in context of that tenant.

## Azure Subscriptions

```PowerShell
let

    CleanAList = 
    (ListWithErrors as list)=>
    let
        CleanList = Table.RemoveRowsWithErrors(Table.FromColumns({ListWithErrors}))[Column1]
    in
        CleanList,

    FnGetSubscriptions = 
    (Id as text) =>
    let
        clientId = Table.SelectRows(Tokens, each ([TenantId] = Id))[ClientId]{0},
        refreshToken = Table.SelectRows(Tokens, each ([TenantId] = Id))[RefreshToken]{0},
        apiUrl = "https://login.microsoftonline.com/" & TenantId & "/oauth2/token",
        body = "client_id=" & clientId & "&grant_type=refresh_token&refresh_token=" & refreshToken,
        Auth = Json.Document(Web.Contents(apiUrl, [Content = Text.ToBinary(body), Headers = [Accept = "application/json", #"Content-Type" = "application/x-www-form-urlencoded"]])),
        accessToken = Auth[access_token],
        fullUrl = "https://management.azure.com/subscriptions?api-version=2020-01-01",
        url = "?api-version=2020-01-01",
        //Source = Json.Document(Web.Contents("https://management.azure.com/subscriptions", [RelativePath=url, Headers=[Authorization="Bearer " & accessToken]]))
        Source = Json.Document(Web.Contents(fullUrl, [Headers=[Authorization="Bearer " & accessToken], Query=[#"api-version"="2020-01-01"]]))
    in
        Source,

    SubList = List.Transform(AzureTenants, each FnGetSubscriptions(_)),
    NewSubList = CleanAList(SubList),
    #"Converted to Table" = Table.FromList(NewSubList, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"value"}, {"Column1.value"}),
    #"Expanded Column1.value" = Table.ExpandListColumn(#"Expanded Column1", "Column1.value"),
    #"Expanded Column1.value2" = Table.ExpandRecordColumn(#"Expanded Column1.value", "Column1.value", {"id", "authorizationSource", "managedByTenants", "subscriptionId", "tenantId", "displayName", "state", "subscriptionPolicies"}, {"Column1.value.id", "Column1.value.authorizationSource", "Column1.value.managedByTenants", "Column1.value.subscriptionId", "Column1.value.tenantId", "Column1.value.displayName", "Column1.value.state", "Column1.value.subscriptionPolicies"}),
    #"Removed Duplicates" = Table.Distinct(#"Expanded Column1.value2", {"Column1.value.id"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Duplicates",{{"Column1.value.subscriptionId", "SubscriptionId"}})
in
    #"Renamed Columns"
```

This M Query should get all the subscriptions in the context of the access token provided. The API VERSION is important as you will see different behavior across all of them. In some cases the call will return **every** subscription you have access to even though you received an access token from a specific tenant.

> **NOTE** ApiVersion is `extremely` important when dealing with Azure endpoints.

## AllConsumption

TODO

## ResourceGroups

TODO

## BillingPeriod

TODO

## AzureTenants

TODO

## Budgets

TODO

## Accounts

TODO

## TenantId

You should make this the default/main tenantId from which all of your subscriptions derive. It is the one that tends to be falled back on when an api call is generic in nature and returns everything in which you have access (despite your context).

## Tokens

TODO