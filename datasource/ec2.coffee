config = require '../config'
mysql = require 'mysql2/promise'
aws = require 'aws-sdk'
IP = require 'ip'

aws.config.update config.aws
ec2 = new aws.EC2()

cpool = mysql.createPool config.mysql

withConnection = (cb) ->
    conn = await cpool.getConnection()
    try
        await cb(conn)
    finally
        conn.release()

withTransaction = (cb) ->
    withConnection (conn) ->
        await conn.query 'START TRANSACTION'
        try
            ret = await cb(conn)
            await conn.query 'COMMIT'
            return ret
        catch e
            await conn.query 'ROLLBACK'
            throw e

class EC2Datasource
    getSubnet: (id) ->
        res = await ec2.describeSubnets(SubnetIds:[id]).promise()
        raw = res.Subnets[0]
        cidr = raw.CidrBlock
        block = IP.cidrSubnet cidr
        gateway = block.firstAddress
        maskLen = block.subnetMaskLength
        return {id,raw,cidr,block,gateway,maskLen}

    getSubnetOfIface: (id) ->
        res = await ec2.describeNetworkInterfaces(NetworkInterfaceIds:[id]).promise()
        subnetId = res.NetworkInterfaces[0].SubnetId
        await @getSubnet subnetId

    allocateAddress: (ifaceId) ->
        subnet = await @getSubnetOfIface ifaceId
        withTransaction (conn) ->
            # Select a free address from pool, order by least used
            [rows,cols] = await conn.query """
                SELECT `ip` FROM `allocation`
                WHERE `status`='free' and `subnet`=?
                ORDER BY `ts` LIMIT 1 FOR UPDATE
            """, [subnet.id]
            throw new Exception "no address available" if rows.length is 0
            ip = rows[0].ip

            # Asks aws to bind ip to ENI
            await ec2.assignPrivateIpAddresses(
                NetworkInterfaceId: ifaceId
                PrivateIpAddresses: [ip]
            ).promise()

            #Mark it is used
            await conn.execute """
                UPDATE `allocation`
                SET `status`='allocated',
                    `owner`=?
                WHERE `ip`=?
            """,[ifaceId,ip]
            return ip

    releaseAddress: (ifaceId,ip) ->
        # Unassign it
        await ec2.unassignPrivateIpAddresses(
            NetworkInterfaceId: ifaceId
            PrivateIpAddresses: [ip]
        ).promise()

        # Mark ip as free
        await withConnection (conn) ->
            await conn.execute """
                UPDATE `allocation`
                SET `status`='free',
                    `owner`=NULL
                WHERE `ip`=?
            """,[ip]

module.exports = new EC2Datasource
