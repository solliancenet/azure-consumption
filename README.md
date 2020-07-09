# Azure Consumption Power BI

This set of docs shows you how to setup Power BI reports to dynamically pull your subscription usage details and then show you costs for each resource group. It is Power BI refresh friendly, which is hard to do.

This repo contains the PowerShell scripts to setup your initial inputs and the Power BI M queries to get it all working.

You need to initially generate two files.  An accounts files and a tokens file. These will contain the data needed to do the access token refresh and other necessary look up details when the other queries run.

## Azure Billing API Issues

So, the billing API works, but within the context of a single subscription. Its not so happy when you try to use tokens from other tenants to access subscriptions in other tenants. That's where the whole Web.Contents fails.  It will continue to try to login using the detail you gave it originally...even though the context has changed. Power BI really wasn't designed to handle these types of scenarios where the same URL is used to return different results. That means you need to override it and pass in bearer tokens to each call that is specific to the tenant/subscription.

So, let's fix that.  We need to determine what tenants you have access too, then get refresh tokens for each and then use those refresh tokens to get access tokens that will work against all the subscriptions you have access too.

That's where the PowerShell script comes into play. The Azure PowerShell uses other SDKs that keep token caches available to you for future usage.  It's a great feature that speeds up your commands, but its also useful for our purposes!

Once you have the refresh tokens, its now up to the Power BI M query to do all the work.  That's where we need to do lots of looping.

## Artifacts

- PowerShell Script
- Power BI Queries
