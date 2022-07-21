
# HelloID-Conn-Prov-Target-Canvas

| :warning: Warning |
|:---------------------------|
| Note that this connector is "a work in progress" and therefore not ready to use in your production environment. |

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://catalog-prod-s3-gallerys3-skf57zr7pimb.s3.amazonaws.com/production/header_images/2f52457da63a9444ebda5c69a57e9de6300d9120.svg">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-Canvas_ is a _target_ connector. Canvas provides a set of REST API's that allow you to programmatically interact with it's data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint                           | Description                               |
| ------------                       | -----------                               |
| /api/v1/accounts/:account_id/users | The endpoint for all user related actions |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting           | Description                                  | Mandatory   |
| ------------      | -----------                                  | ----------- |
| ClientId          | The ClientId to connect to the API           | Yes         |
| ClientSecret      | The ClientSecret to connect to the API       | Yes         |
| BaseUrl           | The URL to the API                           | Yes         |
| RedirectUri       | The redirect uri used in the initial request | No          |
| Code              | This code will be provided by Canvas         | Yes         |
| AccountId         | The AccountId under which the user objects are created | Yes         |
### Prerequisites

### Remarks

#### User object properties

The user object created in Canvas has a lot of properties that can be set. One of them being the `TimeZone`. According to the documentation the `TimeZone` must be a IANA TimeZone. For example, the IANA zone for `America/Denver` is `MDT`. (Mountain Daylight Time). So, the value of `TimeZone` must be `MDT`.

However; the returned user object returns `America/Denver` instead of `MDT`. This might be a inconsistency in the documentation. But at this point that's unclear.

```powershell
$account = [PSCustomObject]@{
    # User [user]
    # The 'name' is the full name of the person
    'user[name]' = "$($p.Name.GivenName) $($p.Name.FamilyName)"

    # The 'short_name' is the user's name as it will be displayed in the UI
    'user[short_name]'    = $p.DisplayName
    'user[sortable_name]' = ""

    # Timezones myst be IANA time zones like: CE, CEST, CEMT
    'user[time_zone]'         = 'CEST'
    'user[terms_of_use]'      = $true
    'user[skip_registration]' = $true

    # The 'locale' is the user's preferred language like: en, de, nl, nl_BE, en_US, etc..
    'user[locale]' = 'nl'

    # User [communication_channel]
    'communication_channel[type]'              = 'email'
    'communication_channel[address]'           = $p.Accounts.MicrosoftActiveDirectory.mail
    'communication_channel[skip_confirmation]' = $true

    # User [pseudnonym]
    # the 'unique_id' for self registration must be set to the emailAddress
    'pseudnonym[unique_i]'          = $p.ExternalId
    'pseudnonym[password]'          = 'Work'
    'pseudnonym[send_confirmation]' = $true
}
```

Another thing to note is that the updated user object has different properties than the original user object that was created. Therefore, in the `Create.ps1` two account objects are defined. The first one is the original account object to create the object and the second one is the updated account object.

#### Service account

All API related actions are executed on behalf of the service account. Another implication is that; the users objects created in Canvas are linked to the service account.

#### Creation / correlation process
A new functionality is the possibility to update the account in the target system during the correlation process. By default this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behaviour in the ` create.ps1` by setting the boolean `$updatePerson` to the value of `$true`.

> Be aware that this might have unexpected implications.

## Setup the connector

> No special actions are required to setup the connector in HelloID.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
