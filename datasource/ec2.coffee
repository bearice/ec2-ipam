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

    # Find any address ready to use on iface, if no ready ips available,
    # allocate and assign new one. Will throw exception if no free ip available.
    allocateAddress: (ifaceId) ->
        subnet = await @getSubnetOfIface ifaceId
        withTransaction (conn) ->
            # Select a ready to use address from pool
            [rows,cols] = await conn.query """
                SELECT `ip` FROM `allocation`
                WHERE `status`='ready' and `iface`=?
                ORDER BY `ts` LIMIT 1 FOR UPDATE
            """, [ifaceId]
            if rows.length > 0
                ip = rows[0].ip
            else
                # Select a free address from pool, and assign it.
                [rows,cols] = await conn.query """
                    SELECT `ip` FROM `allocation`
                    WHERE `status`='free' and `subnet`=?
                    ORDER BY `ts` LIMIT 1 FOR UPDATE
                """, [subnet.id]

                throw new Exception "no address available" if rows.length is 0
                ip = rows[0].ip

                # Assign ip to ENI
                await ec2.assignPrivateIpAddresses(
                    NetworkInterfaceId: ifaceId
                    PrivateIpAddresses: [ip]
                ).promise()

            #Mark it is used
            await conn.execute """
                UPDATE `allocation`
                SET `status`='occupied',
                    `iface`=?
                WHERE `ip`=?
            """,[ifaceId,ip]
            return ip

    # Mark ip as ready, for later use
    releaseAddress: (ifaceId,ip) ->
        # Mark ip as ready
        await withConnection (conn) ->
            await conn.execute """
                UPDATE `allocation`
                SET `status`='ready'
                WHERE `ip`=?
            """,[ip]

module.exports = new EC2Datasource
