// オリジン VM: Nginx を入れ、どのパス・どのクエリでも 200 を返す。
// レスポンスに URI と Front Door が付ける X-Forwarded-For を含めることで、
// 「エッジ経由で届いたか」「どのクライアント IP として見えているか」を判定しやすくする。
// このステップでブロック(429)を返すのは手前の Front Door WAF であり、オリジン自身は常に 200 を返す。

@description('Location for all resources.')
param location string

@description('Subnet id to place the origin NIC')
param subnetId string

@description('Public IP resource id to attach to the origin NIC')
param publicIpId string

@description('Admin username for the VM')
param adminUsername string

@description('Admin password for the VM')
@secure()
param adminPassword string

@description('Static private IP for the origin VM')
param privateIp string = '10.0.1.4'

var originCustomData = '''
#!/bin/bash
apt-get update
apt-get install -y nginx
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    location / {
        default_type text/plain;
        return 200 "Reached ORIGIN (vm-origin) uri=$request_uri xff=$http_x_forwarded_for\n";
    }
}
EOF
systemctl enable nginx
systemctl restart nginx
'''

resource nic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-vm-origin'
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
          publicIPAddress: {
            id: publicIpId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-origin'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-origin'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(originCustomData)
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
