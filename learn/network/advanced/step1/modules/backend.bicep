// バックエンド VM: Nginx を入れ、どのパス・どのクエリでも 200 を返す。
// レスポンスにアクセスされた URI を含めることで、「リクエストがバックエンドまで届いたか」を判定しやすくする。
// （Detection モードなら悪性リクエストもここまで届き 200 が返る／Prevention モードなら手前の WAF が 403 で弾く、の対比に使う）

@description('Location for all resources.')
param location string

@description('Subnet id to place the backend NIC')
param subnetId string

@description('Admin username for the VM')
param adminUsername string

@description('Admin password for the VM')
@secure()
param adminPassword string

@description('Static private IP for the backend VM')
param privateIp string = '10.0.2.4'

var backendCustomData = '''
#!/bin/bash
apt-get update
apt-get install -y nginx
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    location / {
        default_type text/plain;
        return 200 "Reached BACKEND (vm-backend) uri=$request_uri\n";
    }
}
EOF
systemctl enable nginx
systemctl restart nginx
'''

resource nic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-vm-backend'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIp
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-backend'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-backend'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(backendCustomData)
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

output privateIp string = privateIp
