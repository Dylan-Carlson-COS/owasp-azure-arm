// az deployment group create --confirm-with-what-if -f azuredeploy.bicep --resource-group rg-zap-001 --parameters azuredeploy.parameters.json

@description('The name of the website to scan, starting with HTTP/HTTPS')
param target string = ''

@description('How long to spend spidering the site, in minutes')
@minValue(1)
@maxValue(15)
param spiderTime int = 1

var reportName = 'owasp-report.xml'
var blobContainerName = 'reports'
var image = 'owasp/zap2docker-stable'
var storageAccountName_var = uniqueString(resourceGroup().id)
var cpuCores = 1
var memoryInGb = 2
var containerGroupName_var = 'zapcontainer'
var containerName = 'zap'
var singleQuote = '\''
var cmdZapStart = 'zap.sh -daemon -host 0.0.0.0 -port 8080 -config api.key=abcd -config api.addrs.addr.name=.* -config api.addrs.addr.regex=true'
var cmdDirMakeOutput = 'mkdir output'
var cmdDirSymlinkWrk = 'ln -s output wrk'
var cmdZapScan = '/zap/zap-baseline.py -t ${target} -d -m ${spiderTime} -x ${reportName}'
var cmdWgetPutReport = 'wget --method=PUT --header="x-ms-blob-type: BlockBlob" --body-file=output/${reportName} "https://${storageAccountName_var}.blob.core.windows.net/${blobContainerName}/${reportName}?'
var accountSasProperties = {
  signedServices: 'b'
  signedPermission: 'rw'
  signedProtocol: 'https'
  signedStart: '2021-09-03T11:11:11Z'
  signedExpiry: '2029-01-01T11:00:00Z'
  signedResourceTypes: 'o'
  keyToSign: 'key1'
}

resource storageAccountName 'Microsoft.Storage/storageAccounts@2018-02-01' = {
  name: storageAccountName_var
  location: resourceGroup().location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {}
}

resource storageAccountName_default_blobContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2018-03-01-preview' = {
  name: '${storageAccountName_var}/default/${blobContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName
  ]
}

resource containerGroupName 'Microsoft.ContainerInstance/containerGroups@2018-10-01' = {
  name: containerGroupName_var
  location: resourceGroup().location
  properties: {
    containers: [
      {
        name: containerName
        properties: {
          image: image
          command: [
            '/bin/bash'
            '-c'
            '($ZAPCOMMAND) & $MKDIROUTPUT && $SYMLINKWRK && sleep 30 && $SCAN ; sleep 10 ; ${cmdWgetPutReport}${listAccountSas(storageAccountName_var, '2018-02-01', accountSasProperties).accountSasToken}"'
          ]
          environmentVariables: [
            {
              name: 'ZAPCOMMAND'
              value: cmdZapStart
            }
            {
              name: 'MKDIROUTPUT'
              value: cmdDirMakeOutput
            }
            {
              name: 'SYMLINKWRK'
              value: cmdDirSymlinkWrk
            }
            {
              name: 'SCAN'
              value: cmdZapScan
            }
            {
              name: 'PUTREPORT'
              value: cmdWgetPutReport
            }
          ]
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryInGb
            }
          }
        }
      }
    ]
    restartPolicy: 'Never'
    osType: 'Linux'
  }
  dependsOn: [
    storageAccountName
  ]
}

output reportStorageAccount string = storageAccountName_var
output reportBlobContainer string = blobContainerName
output reportFilename string = reportName
output reportSasToken string = listAccountSas(storageAccountName_var, '2018-02-01', accountSasProperties).accountSasToken
