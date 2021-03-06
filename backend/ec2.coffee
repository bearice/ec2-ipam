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
    catch e
        console.info e.stack
        throw new Error e
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

                throw new Error "No address available in subnet #{subnet.id}" if rows.length is 0
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
        withConnection (conn) ->
            await conn.execute """
                UPDATE `allocation`
                SET `status`='ready'
                WHERE `ip`=?
            """,[ip]

    # Scan for any `ready` state address, unassgin it and mark it free.
    recycleAddress: (subnetId, limit=100)->
        withTransaction (conn) ->
            [rows,cols] = await conn.query """
                SELECT `ip`,`iface` FROM `allocation`
                WHERE `status`='ready' and `subnet`=?
                ORDER BY `ts` LIMIT ? FOR UPDATE
            """, [subnetId, limit]
            for row in rows
                ip = row.ip
                ifaceId = row.iface
                console.info "Recycling address #{ip} on #{ifaceId}"
                # Unassign it
                await ec2.unassignPrivateIpAddresses(
                    NetworkInterfaceId: ifaceId
                    PrivateIpAddresses: [ip]
                ).promise()
                # Mark as free
                await conn.execute """
                    UPDATE `allocation`
                    SET `status`='free', `iface`=NULL
                    WHERE `ip`=?
                """,[ip]
            return rows.length

    # Read subnet data from AWS then insert records into mysql
    initSubnet: (subnetId)->
        subnet = {block} = await @getSubnet subnetId

        base = IP.toLong block.firstAddress
        last  = IP.toLong block.lastAddress
        rows = [base..last].map (i)->[IP.fromLong(i),subnetId,'free',null,false]

        #First 4 address are reversed for internal usage
        rows[i] = [IP.fromLong(i+base),subnetId,'reserved',null,false] for i in [0..3]
        occupied_count = 4
        #Query AWS for occupied address
        res = await ec2.describeNetworkInterfaces(Filters:[{Name:'subnet-id',Values:[subnetId]}]).promise()
        for intf in res.NetworkInterfaces
            for a in intf.PrivateIpAddresses
                i = IP.toLong(a.PrivateIpAddress) - base
                #console.info a.PrivateIpAddress
                #console.info rows[i]
                rows[i] = [a.PrivateIpAddress, subnetId, 'occupied', intf.NetworkInterfaceId, a.Primary]
                occupied_count+=1

        #console.info row for row in rows
        await withConnection (conn)->
            conn.query """
                INSERT INTO `allocation` (
                    `ip`, `subnet`, `status`, `iface`, `primary`
                ) VALUES ?
            """, [rows]

        return {
            total: rows.length
            occupied: occupied_count
            free: rows.length - occupied_count
        }

    # Clear all allocation records on interface
    initIface: (ifaceId) ->
        res = await ec2.describeNetworkInterfaces(NetworkInterfaceIds:[ifaceId]).promise()
        intf = res.NetworkInterfaces[0]
        throw new Error "Interface #{ifaceId} not found" unless intf
        ips = (a.PrivateIpAddress for a in intf.PrivateIpAddresses)
        withConnection (conn)->
            await conn.query """
                UPDATE `allocation`
                SET `primary`=1
                WHERE `ip`=?
            """, [a.PrivateIpAddress]
            await conn.query """
                UPDATE `allocation`
                SET `status`='ready',`iface`=?
                WHERE `ip` in (?)
            """, [ifaceId,ips]

module.exports = new EC2Datasource
