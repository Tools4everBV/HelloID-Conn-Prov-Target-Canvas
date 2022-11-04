
# HelloID-Conn-Prov-Target-Canvas


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

| Setting           | Description                                             |  Mandatory  |
| ------------      | -----------                                             | ----------- |
| Access Token      | The Access Token to connect to the API                  | Yes         |
| BaseUrl           | The URL to the API                                      | Yes         |
| AccountId         | The AccountId under which the user objects are created (Id of the company) | Yes         |
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

### Remarks
  - > The delete process might lead to some unexpected behavior.
  Please verify the delete process. So it matches the customer's requirements.  This because we create users to an Account (company), but the action Delete User, deletes the user from that Account, but it is still accessible from the user endpoint. It looks like a Disable action.
 - The updated user object has different properties than the original user object that in created. Therefore, in the `Create.ps1` two account objects are defined. The first one is the original account object to create the object and the second one is the updated account object.


#### Creation / correlation process
A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior in the ` create.ps1` by setting the boolean `$updatePerson` to the value of `$true`.

> Be aware that this might have unexpected implications.

## Setup the connector

> No special actions are required to setup the connector in HelloID.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
