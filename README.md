# HelloID-Conn-Prov-Target-Canvas

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Canvas](#helloid-conn-prov-target-Canvas)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
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

## Getting started

### Prerequisites

- An Access Token to connect to the API
- Obtain the AccountId of the customer. You can use the following code.

  ```Powershell
    $accessToken = ''
    $baseUrl =  '' # Example 'https://tools.test.instructure.com/'

    $headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
    $headers.Add('Authorization', "Bearer $accessToken")
    $response = Invoke-RestMethod "$baseUrl/api/v1/accounts" -Method 'GET' -Headers $headers
    $response | ConvertTo-Json
  ```

## Remarks

### Attribute for SSO

- sis_user_id is needed for SSO


### Connection settings

The following settings are required to connect to the API.

| Setting           | Description                                             |  Mandatory  |
| ------------      | -----------                                             | ----------- |
| Access Token      | The Access Token to connect to the API                  | Yes         |
| BaseUrl           | The URL to the API                                      | Yes         |
| AccountId         | The AccountId under which the user objects are created (Id of the company) | Yes         |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Canvas_ to a person in _HelloID_. 


| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `Accounts.MicrosoftActiveDirectory.mail` |
| Account correlation field | `email`                  |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Available lifecycle actions

The following lifecycle actions are available:

| Action                                  | Description                                                                                 |
| --------------------------------------- | ------------------------------------------------------------------------------------------- |
| create.ps1                              | Creates a new account.                                                                      |
| delete.ps1                              | Removes an existing user account or entity from the customer account.                       |
| disable.ps1                             | Disables an account, preventing access without permanent removal.                           |
| enable.ps1                              | Enables an account, granting access.                                                        |
| update.ps1                              | Updates the attributes of an account.                                                       |
| configuration.json                      | Contains the connection settings and general configuration for the connector.               |
| fieldMapping.json                       | Defines mappings between person fields and target system person account fields.             |

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

## Remarks

  - > The delete process might lead to some unexpected behavior.
  Please verify the delete process. So it matches the customer's requirements.  This because we create users to an Account (company), but the action Delete User, removes the user from that Account, but it is still accessible from the user endpoint. It behaves  like a Disable action.
 - The user object used in the update has fewer properties than the original user object that is created. Therefore, the account object in the `Create.ps1` differs from the one in `Update.ps1`.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint | Description               |
| -------- | ------------------------- |
| /api/v1/accounts[/<account_id>]/users[/<user_id>]   | The endpoints for all user related actions |
|

### API documentation

<!--
If publicly available, provide the link to the API documentation
-->

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
