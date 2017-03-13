module.exports = {
    getSubnet: (id)->
        {
            id:'123456',
            cidr:'172.30.4.0/24',
            gateway:'172.30.4.1',
            maskLen:24
        }

    getSubnetOfIface: (ifaceId) -> @getSubnet ifaceId
    allocateAddress: (ifaceId) -> '172.30.4.9'
    releaseAddress: ->
    initSubnet: ->
    recycleAddress: ->
    flushIface: ->
}
