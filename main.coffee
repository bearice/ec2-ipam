Koa = require 'koa'
KError = require 'koa-json-error'
KBodyParser = require 'koa-bodyparser'
KJson = require 'koa-json'
KRouter = require 'koa-trie-router'
KLogger = require 'koa-logger'

ds = require './backend/ec2'
app = new Koa()
router = new KRouter()

app.use KError(format:(err)->{Error:err.stack})
app.use KLogger()
app.use KJson pretty: false, param: 'pretty'
app.use KBodyParser detectJSON: (ctx)->ctx.request.method is 'POST'

router.get "/",(ctx)->
    ctx.body = "Daikon IPAM Module"

# API Doc: https://github.com/docker/libnetwork/blob/master/docs/ipam.md
#
router.post "/Plugin.Activate", (ctx)->
    ctx.body =  "Implements": ["IpamDriver"]

router.post "/IpamDriver.GetCapabilities", (ctx)->
    ctx.body =
        "RequiresMACAddress": false
        "RequiresRequestReplay": true

router.post "/IpamDriver.GetDefaultAddressSpaces", (ctx)->
    ctx.body =
        "LocalDefaultAddressSpace":"172.30.0.0/16"
        "GlobalDefaultAddressSpace":"172.30.0.0/16"

router.post "/IpamDriver.RequestPool", (ctx)->
    req = ctx.request.body
    ifaceId = req.Options['eni-id']
    subnet = await ds.getSubnetOfIface ifaceId

    # We should flush interface here since we had 'RequiresRequestReplay' flag set
    # and RequestAddress will be call every time docker boots up, even in case of
    # unclean shutdown.
    await ds.initIface ifaceId
    ctx.body = {
        "PoolID": ifaceId
        "Pool": subnet.cidr
    }

router.post "/IpamDriver.ReleasePool", (ctx)->
    ctx.body = {}

router.post "/IpamDriver.RequestAddress", (ctx)->
    req = ctx.request.body
    ifaceId = req.PoolID
    subnet = await ds.getSubnetOfIface ifaceId
    if req.Options?.RequestAddressType is 'com.docker.network.gateway'
        address = subnet.gateway
    else
        address = await ds.allocateAddress ifaceId

    ctx.body = {"Address": address + "/" + subnet.maskLen}

router.post "/IpamDriver.ReleaseAddress", (ctx)->
    req = ctx.request.body
    ifaceId = req.PoolID
    ip = req.Address
    await ds.releaseAddress ifaceId,ip
    ctx.body = {}

app.use (ctx,next)->
    if ctx.request.method is 'POST'
        console.info ">>", ctx.request.body
        await next()
        console.info "<<", ctx.body
    else
        await next()

app.use router.middleware()

app.use (ctx)->
    ctx.status = 404
    ctx.body = {"Error":"Not Found"}

app.listen 8031
