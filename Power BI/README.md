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

The following will get all Resource Groups across all your tenants and subscriptions.

```PowerShell
let
    iterations = 10,
    Subscriptions = Table.SelectColumns(Accounts,{"id"}),

    FnGetTenants = 
    (Id as text) =>
    let
        clientId = Table.SelectRows(Tokens, each ([TenantId] = Id))[ClientId]{0},
        refreshToken = Table.SelectRows(Tokens, each ([TenantId] = Id))[RefreshToken]{0},
        apiUrl = "https://login.microsoftonline.com/" & TenantId & "/oauth2/token",
        body = "client_id=" & clientId & "&grant_type=refresh_token&refresh_token=" & refreshToken,
        Auth = Json.Document(Web.Contents(apiUrl, [Content = Text.ToBinary(body), Headers = [Accept = "application/json", #"Content-Type" = "application/x-www-form-urlencoded"]])),
        accessToken = Auth[access_token],

        fullUrl = "https://management.azure.com/subscriptions?api-version=2020-01-01",
        SubList2 = Json.Document(Web.Contents(fullUrl, [Headers=[Authorization="Bearer " & accessToken], Query=[#"api-version"="2020-01-01"]])),
        
        value = SubList2[value],
        #"Converted to Table" = Table.FromList(value, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"id", "authorizationSource", "managedByTenants", "subscriptionId", "tenantId", "displayName", "state", "subscriptionPolicies"}, {"Column1.id", "Column1.authorizationSource", "Column1.managedByTenants", "Column1.subscriptionId", "Column1.tenantId", "Column1.displayName", "Column1.state", "Column1.subscriptionPolicies"}),
        #"Removed Duplicates" = Table.Distinct(#"Expanded Column1", {"Column1.id"}),
        #"Renamed Columns" = Table.RenameColumns(#"Removed Duplicates",{{"Column1.subscriptionId", "SubscriptionId"}}),
        
        SubList = List.Transform(#"Renamed Columns"[SubscriptionId], each FnGetUrl(_)),

        SubList3 = List.Transform(SubList, each FnGetAllPages(_, accessToken)),

        FinalTable = Table.FromList(SubList3, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        FinalList = Table.AddColumn(FinalTable, "TenantId", each Id)
        
    in
        FinalList,

    FnGetUrl = 
    (Id as text) =>
    let
        //Source = "https://management.azure.com/subscriptions/" & Id & "/providers/Microsoft.Billing/billingPeriods/20200601/providers/Microsoft.Consumption/usageDetails?$top=1000&api-version=2018-01-31"
        //Source = "/" & Id & "/resourcegroups?api-version=2020-06-01"
        Source = "https://management.azure.com/subscriptions/" & Id & "/resourcegroups?api-version=2020-06-01"
    in
        Source,

    FnGetOnePage =
     (url, accessToken) as record =>
      let
       //Source = Function.InvokeAfter(Json.Document(Web.Contents(url), #duration(0,0,0,5))),
       //Source = Json.Document(Web.Contents("https://management.azure.com/subscriptions", [RelativePath=url, Headers=[Authorization="Bearer " & accessToken]])),
       Source = Json.Document(Web.Contents(url, [Headers=[Authorization="Bearer " & accessToken]])),
       data = try Source[value] otherwise null,
       next = try Source[nextLink] otherwise null,
       res = [Data=data, Next=next]
      in
       res,

    FnGetAllPages = 
     (url,accessToken) as list =>
     let 
        All = List.Generate(
            ()=>[i=0, res = FnGetOnePage(url, accessToken)],
            each [i]<iterations and [res][Data]<>null,
            each [i=[i]+1, res = FnGetOnePage([res][Next], accessToken)],
            each [res][Data])
      in
    All,

    SubList3 = List.Transform(AzureTenants, each FnGetTenants(_)),
    #"Converted to Table" = Table.FromList(SubList3, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Expanded Column1" = Table.ExpandTableColumn(#"Converted to Table", "Column1", {"Column1", "TenantId"}, {"Column1.Column1", "Column1.TenantId"}),
    #"Expanded Column1.Column1" = Table.ExpandListColumn(#"Expanded Column1", "Column1.Column1"),
    #"Expanded Column1.Column2" = Table.ExpandListColumn(#"Expanded Column1.Column1", "Column1.Column1"),
    #"Expanded Column1.Column3" = Table.ExpandRecordColumn(#"Expanded Column1.Column2", "Column1.Column1", {"id", "name", "type", "location", "tags", "properties"}, {"Column1.Column1.id", "Column1.Column1.name", "Column1.Column1.type", "Column1.Column1.location", "Column1.Column1.tags", "Column1.Column1.properties"}),
    #"Expanded Column1.Column1.tags" = Table.ExpandRecordColumn(#"Expanded Column1.Column3", "Column1.Column1.tags", {"MonthlyCost", "Contact", "Project", "EndDate"}, {"Column1.Column1.tags.MonthlyCost", "Column1.Column1.tags.Contact", "Column1.Column1.tags.Project", "Column1.Column1.tags.EndDate"}),
    #"Expanded Column1.Column1.properties" = Table.ExpandRecordColumn(#"Expanded Column1.Column1.tags", "Column1.Column1.properties", {"provisioningState"}, {"Column1.Column1.properties.provisioningState"}),
    #"Filtered Rows" = Table.SelectRows(#"Expanded Column1.Column1.properties", each [Column1.Column1.id] <> null and [Column1.Column1.id] <> ""),
    #"Renamed Columns" = Table.RenameColumns(#"Filtered Rows",{{"Column1.Column1.id", "ResourceId"}, {"Column1.Column1.name", "Name"}, {"Column1.Column1.tags.MonthlyCost", "MonthlyCost"}, {"Column1.Column1.tags.Contact", "Contact"}, {"Column1.Column1.tags.Project", "Project"}}),
    #"Sorted Rows" = Table.Sort(#"Renamed Columns",{{"Name", Order.Ascending}}),
    #"Lowercased Text" = Table.TransformColumns(#"Sorted Rows",{{"ResourceId", Text.Lower, type text}})
in
    #"Lowercased Text"
```

## BillingPeriod

This is a parameter that will set itself if not set in the Power BI dataset. It will be set to the current month and then passed to the Billing API.

## AzureTenants

This will grab all your Azure Tenants.  This API call tends to return the same results no matter what context you pass in.

```PowerShell
let
    //AzureSubscriptions = Json.Document(Web.Contents("https://management.azure.com/tenants?api-version=2018-02-01")),
    clientId = Table.SelectRows(Tokens, each ([TenantId] = TenantId))[ClientId]{0},
    refreshToken = Table.SelectRows(Tokens, each ([TenantId] = TenantId))[RefreshToken]{0},
    apiUrl = "https://login.microsoftonline.com/" & TenantId & "/oauth2/token",
    body = "client_id=" & clientId & "&grant_type=refresh_token&refresh_token=" & refreshToken,
    Auth = Json.Document(Web.Contents(apiUrl, [Content = Text.ToBinary(body), Headers = [Accept = "application/json", #"Content-Type" = "application/x-www-form-urlencoded"]])),
    accessToken = Auth[access_token],
    
    url = "?api-version=2018-02-01",
    //AzureSubscriptions = Json.Document(Web.Contents("https://management.azure.com/tenants", [RelativePath=url])),
    AzureSubscriptions = Json.Document(Web.Contents("https://management.azure.com/tenants", [RelativePath=url, Headers=[Authorization="Bearer " & accessToken]])),
    value = AzureSubscriptions[value],
    #"Converted to Table" = Table.FromList(value, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"id", "tenantId", "countryCode", "displayName", "domains"}, {"Column1.id", "Column1.tenantId", "Column1.countryCode", "Column1.displayName", "Column1.domains"}),
    #"Filtered Rows" = Table.SelectRows(#"Expanded Column1", each ([Column1.tenantId] = "d280491c-b27a-41bf-9623-21b60cf430b3")),
    #"Removed Columns" = Table.RemoveColumns(#"Filtered Rows",{"Column1.domains"}),
    #"Column1 tenantId" = #"Removed Columns"[Column1.tenantId]
in
    #"Column1 tenantId"
```

## Budgets

We have setup budgets for our resources. We'd like to know if those budgets are going over or not.  We got de-sensitized to the budget emails so this report will show us if the spend is over the 30 day limits.

```PowerShell
let
    iterations = 10,
    Subscriptions = Table.SelectColumns(Accounts,{"id"}),

    FnGetTenants = 
    (Id as text) =>
    let
        clientId = Table.SelectRows(Tokens, each ([TenantId] = Id))[ClientId]{0},
        refreshToken = Table.SelectRows(Tokens, each ([TenantId] = Id))[RefreshToken]{0},
        apiUrl = "https://login.microsoftonline.com/" & TenantId & "/oauth2/token",
        body = "client_id=" & clientId & "&grant_type=refresh_token&refresh_token=" & refreshToken,
        Auth = Json.Document(Web.Contents(apiUrl, [Content = Text.ToBinary(body), Headers = [Accept = "application/json", #"Content-Type" = "application/x-www-form-urlencoded"]])),
        accessToken = Auth[access_token],

        fullUrl = "https://management.azure.com/subscriptions?api-version=2020-01-01",
        SubList2 = Json.Document(Web.Contents(fullUrl, [Headers=[Authorization="Bearer " & accessToken], Query=[#"api-version"="2020-01-01"]])),
        
        value = SubList2[value],
        #"Converted to Table" = Table.FromList(value, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"id", "authorizationSource", "managedByTenants", "subscriptionId", "tenantId", "displayName", "state", "subscriptionPolicies"}, {"Column1.id", "Column1.authorizationSource", "Column1.managedByTenants", "Column1.subscriptionId", "Column1.tenantId", "Column1.displayName", "Column1.state", "Column1.subscriptionPolicies"}),
        #"Removed Duplicates" = Table.Distinct(#"Expanded Column1", {"Column1.id"}),
        #"Renamed Columns" = Table.RenameColumns(#"Removed Duplicates",{{"Column1.subscriptionId", "SubscriptionId"}}),
        
        SubList = List.Transform(#"Renamed Columns"[SubscriptionId], each FnGetUrl(_)),

        SubList3 = List.Transform(SubList, each FnGetAllPages(_, accessToken)),

        FinalTable = Table.FromList(SubList3, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        FinalList = Table.AddColumn(FinalTable, "TenantId", each Id)
        
    in
        FinalList,

    FnGetUrl = 
    (Id as text) =>
    let
        //Source =  "/" & Id & "/providers/Microsoft.Consumption/budgets?api-version=2018-01-31"
        Source =  "https://management.azure.com/subscriptions/" & Id & "/providers/Microsoft.Consumption/budgets?api-version=2018-01-31"
        
    in
        Source,

    FnGetOnePage =
     (url, accessToken) as record =>
      try(
      let
       //Source = Function.InvokeAfter(Json.Document(Web.Contents(url), #duration(0,0,0,5))),
       Source = Json.Document(Web.Contents(url, [Headers=[Authorization="Bearer " & accessToken]])),
       data = try Source[value] otherwise null,
       next = try Source[nextLink] otherwise null,
       res = [Data=data, Next=next]
      in
       res
       )
       otherwise
       (
        let 
         res = null
         in 
         res
       )
       ,

    FnGetAllPages = 
     (url, accessToken) as list =>
     let 
        All = List.Generate(
            ()=>[i=0, res = FnGetOnePage(url, accessToken)],
            each [i]<iterations and [res][Data]<>null,
            each [i=[i]+1, res = FnGetOnePage([res][Next], accessToken)],
            each [res][Data])
      in
    All,

    SubList = List.Transform(AzureTenants, each FnGetTenants(_)),
    
    //SubList = List.Transform(Subscriptions[id], each FnGetUrl(_)),
    //SubList2 = List.Transform(SubList, each FnGetAllPages(_)),

    #"Converted to Table" = Table.FromList(SubList, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Expanded Column1" = Table.ExpandListColumn(#"Converted to Table", "Column1"),
    #"Expanded Column4" = Table.ExpandRecordColumn(#"Expanded Column1", "Column1", {"Column1", "TenantId"}, {"Column1.Column1", "Column1.TenantId"}),
    #"Expanded Column2" = Table.ExpandListColumn(#"Expanded Column4", "Column1.Column1"),
    #"Expanded Column1.Column1" = Table.ExpandListColumn(#"Expanded Column2", "Column1.Column1"),
    #"Expanded Column3" = Table.ExpandRecordColumn(#"Expanded Column1.Column1", "Column1.Column1", {"id", "name", "type", "eTag", "properties"}, {"Column1.Column1.id", "Column1.Column1.name", "Column1.Column1.type", "Column1.Column1.eTag", "Column1.Column1.properties"}),
    #"Expanded Column1.properties" = Table.ExpandRecordColumn(#"Expanded Column3", "Column1.Column1.properties", {"timePeriod", "timeGrain", "amount", "currentSpend", "category", "notifications", "filter", "currencySetting"}, {"Column1.properties.timePeriod", "Column1.properties.timeGrain", "Column1.properties.amount", "Column1.properties.currentSpend", "Column1.properties.category", "Column1.properties.notifications", "Column1.properties.filter", "Column1.properties.currencySetting"}),
    #"Expanded Column1.properties.currentSpend" = Table.ExpandRecordColumn(#"Expanded Column1.properties", "Column1.properties.currentSpend", {"amount", "unit"}, {"Column1.properties.currentSpend.amount", "Column1.properties.currentSpend.unit"}),
    #"Renamed Columns" = Table.RenameColumns(#"Expanded Column1.properties.currentSpend",{{"Column1.properties.amount", "Limit"}, {"Column1.properties.currentSpend.amount", "CurrentSpend"}, {"Column1.properties.currentSpend.unit", "Currency"}, {"Column1.properties.category", "Category"}}),
    #"Filtered Rows" = Table.SelectRows(#"Renamed Columns", each [Column1.Column1.id] <> null and [Column1.Column1.id] <> ""),
    #"Renamed Columns1" = Table.RenameColumns(#"Filtered Rows",{{"Column1.Column1.name", "Subscription"}}),
    #"Changed Type" = Table.TransformColumnTypes(#"Renamed Columns1",{{"CurrentSpend", type number}, {"Limit", type number}}),
    #"Added Custom1" = Table.AddColumn(#"Changed Type", "30DayLimit", each [Limit] / 30),
    #"Added Custom2" = Table.AddColumn(#"Added Custom1", "30DayRate", each [CurrentSpend] / (Date.Day(Date.FromText(DateTime.ToText(DateTime.LocalNow(), "MM/dd/yyyy"))))),
    #"Added Custom" = Table.AddColumn(#"Added Custom2", "OverDaily", each ([Limit] / 30) < [CurrentSpend] / (Date.Day(Date.FromText(DateTime.ToText(DateTime.LocalNow(), "MM/dd/yyyy"))))),
    #"Changed Type1" = Table.TransformColumnTypes(#"Added Custom",{{"OverDaily", type logical}, {"30DayLimit", type number}, {"30DayRate", type number}}),
    #"Added Conditional Column" = Table.AddColumn(#"Changed Type1", "Custom", each if [OverDaily] = true then "Red" else if [OverDaily] = false then "Green" else null),
    #"Removed Duplicates" = Table.Distinct(#"Added Conditional Column", {"Column1.Column1.id"})
in
    #"Removed Duplicates"
```

## Accounts

TODO

## TenantId

You should make this the default/main tenantId from which all of your subscriptions derive. It is the one that tends to be falled back on when an api call is generic in nature and returns everything in which you have access (despite your context).

## Tokens

TODO