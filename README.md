# HelloID-Conn-Prov-Target-Canvas

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Canvas/refs/heads/main/Icon.png?raw=true" alt="Canvas logo"">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Canvas](#helloid-conn-prov-target-Canvas)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Available lifecycle actions](#available-lifecycle-actions)
    - [Field mapping](#field-mapping)
  - [Remarks](#remarks)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Canvas_ is a _target_ connector. _Canvas_ provides a set of REST API's that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks           |
| ----------------------------------------- | --------- | --------------------------------------- | ----------------- |
| **Account Lifecycle**                     | ✅        | Create, Update, Enable, Disable, Delete |                   |
| **Permissions**                           | ✅        | Retrieve, Grant, Revoke                 | Static or Dynamic |
| **Resources**                             | ✅        | Student Groups                          |                   |
| **Entitlement Import: Accounts**          | ✅        | -                                       |                   |
| **Entitlement Import: Permissions**       | ✅        | -                                       |                   |
| **Governance Reconciliation Resolutions** | ✅        | -                                       |                   |

<!--
Example
### ⚠️ Governance Reconciliation Resolutions
Governance reconciliation is supported for reporting purposes.
Resolutions are not possible because...
-->

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Canvas/refs/heads/main/Icon.png
```

### Requirements

#### HelloID agent

This connector is completly cloud based (Powershell v7 core). When for some reason this connector must run through the onpremise HelloID agent, pagination in the various scripts should be adjusted. An example script is provided for using pagination with Powershell v5.1.

#### Access Token

An Access Token to connect to the API. Obtain the AccountId of the customer. You can use the following code.

```Powershell
  $accessToken = ''
  $baseUrl =  '' # Example 'https://tools.test.instructure.com/'

  $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
  $headers.Add('Authorization', "Bearer $accessToken")
  $response = Invoke-RestMethod "$baseUrl/api/v1/accounts" -Method 'GET' -Headers $headers
  $response | ConvertTo-Json
```

#### Attribute for SSO

_sis_user_id_ is needed for SSO

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                                                                | Mandatory |
| ------------ | -------------------------------------------------------------------------- | --------- |
| Access Token | The Access Token to connect to the API                                     | Yes       |
| BaseUrl      | The URL to the API                                                         | Yes       |
| AccountId    | The AccountId under which the user objects are created (Id of the company) | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Canvas_ to a person in _HelloID_.

| Setting                   | Value                                                 |
| ------------------------- | ----------------------------------------------------- |
| Enable correlation        | `True`                                                |
| Person correlation field  | `Accounts.MicrosoftActiveDirectory.userPrincipalName` |
| Account correlation field | `login_id`                                            |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `id` property from _Canvas_

## Remarks

### Update account

The user object used in the update has fewer properties than the original user object that is created. Therefore, the account object in the `Create.ps1` differs from the one in `Update.ps1`.

### Delete account

The delete process might lead to some unexpected behavior.
Please verify the delete process. So it matches the customer's requirements. This because we create users to an Account (company), but the action Delete User, removes the user from that Account, but it is still accessible from the user endpoint. A deleted account can't be restored by HelloID and the account cannot be recreated due to an existing _`\_sis_user_id_`\_

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                                                        | Description                                                             |
| --------------------------------------------------------------- | ----------------------------------------------------------------------- |
| /api/v1/accounts[/<account_id>]/users[/<user_id>]               | The endpoints for all user related actions                              |
| /api/v1/users[/<user_id>]                                       | The endpoints for all user related actions within the account (company) |
| /api/v1/accounts[/<account_id>]/groups[/<group_id>]             | The endpoints for all group related actions                             |
| /api/v1/accounts[/<account_id>]/groups[/<group_id>]/memberships | For assigning group memberships                                         |
| /api/v1/accounts[/<account_id>]/groups[/<group_id>]/users       | For revoking group memberships and importing permissions                |
| /api/v1/accounts[/<account_id>]/sis_imports]                    | The endpoint for creating resources                                     |

### API documentation

The offical Canvas API documentation can be found at: https://developerdocs.instructure.com/services/canvas/resources

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
