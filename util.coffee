ip = require 'ip'
module.exports =
    ipRange: (start,count)->
        first = ip.toLong start
        last  = first+count-1
        ip.fromLong x for x in [first..last]


