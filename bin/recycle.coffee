#!/usr/bin/env coffee
ds = require '../backend/ec2'
main = (id)->
    ret = await ds.recycleAddress id
    console.info "Result: #{ret} address(es) recycled"

if process.argv.length == 2
    console.info "#{process.argv[1]} <subnet-id>"
else
    main(process.argv[2])
        .then(process.exit)
        .catch(console.error)
