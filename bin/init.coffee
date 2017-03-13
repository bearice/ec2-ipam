#!/usr/bin/env coffee
ds = require '../backend/ec2'
main = (id)->
    ret = await ds.initSubnet id
    console.info """
        Result: #{ret.total} addresses in total
                #{ret.occupied} addresses in occupied
                #{ret.free} addresses in free
    """

if process.argv.length == 2
    console.info "#{process.argv[1]} <subnet-id>"
else
    main(process.argv[2])
        .catch(console.error)
        .then(process.exit)
