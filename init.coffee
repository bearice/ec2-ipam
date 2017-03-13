ds = require './datasource/ec2'

main = (id)->
    ret = await ds.initSubnet id
    console.info ret

if process.argv.length == 2
    console.info "init.js <subnet_id>"
else
    main(process.argv[2]).then(console.info).catch(console.error)
