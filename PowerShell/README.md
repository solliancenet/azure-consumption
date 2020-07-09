# PowerShell Files

There are two files here.  One that will pre-tag all your resources for the lazy people in your organization, and another that will enumerate your subscriptions and built out an accounts file and a token file with your refresh tokens.

## Tagging Resource Groups

[TagResources.ps1](TagResourceGroups.ps1)

This script will run through all your resource groups and tag them with the MonthlyCost based on last months billing costs.  It will also try to attempt to find who created the resource group, but as we all know, Azure isn't great about telling us how created stuff (a huge downfall for the platform IMHO).

## Getting Refresh Tokens

[GenerateFiles.ps1](GenerateFiles.ps1)

This will utilize and piggyback off of the Azure Powershell to export all the refresh tokens for all tenants you have access too.
