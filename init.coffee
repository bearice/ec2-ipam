config = require './config'
mysql = require 'mysql2/promise'
aws = require 'aws-sdk'
ip = require 'ip'

aws.config.update config.aws
ec2 = new aws.EC2()

ipRange = (start,count)->
    first = ip.toLong start
    last  = first+count-1
    ip.fromLong x for x in [first..last]

main = (subnet_id)->
    res = await ec2.describeSubnets({SubnetIds:[subnet_id]}).promise()
    cidr = res.Subnets[0].CidrBlock
    console.info "CIDR=#{cidr}"

    subnet = ip.cidrSubnet cidr
    console.info subnet
    ips = ipRange subnet.firstAddress, subnet.numHosts

    #First 4 address are reversed for internal usage
    reserved=ip.subnet ips[0],'255.255.255.250'

    #Query AWS for occupied address
    res = await ec2.describeNetworkInterfaces(Filters:[{Name:'subnet-id',Values:[subnet_id]}]).promise()
    occupied={}
    for i in res.NetworkInterfaces
        for a in i.PrivateIpAddresses
            occupied[a.PrivateIpAddress] = i.NetworkInterfaceId

    conn = await mysql.createConnection config.mysql

    rows = ips.map (ip)->
        if occupied[ip]
            [ip,subnet_id,'occupied',occupied[ip]]
        else if reserved.contains ip
            [ip,subnet_id,'occupied','reserved']
        else
            [ip,subnet_id,'free',null]

    res = await conn.query "insert into allocation(ip,subnet,status,owner) values ?", [rows]
    console.info res

    await conn.end()


if process.argv.length == 2
    console.info "init.js <subnet_id>"
else
    main(process.argv[2]).then(console.info).catch(console.error)
