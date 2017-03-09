Koa = require 'koa'
KError = require 'koa-json-error'
KBodyParser = require 'koa-bodyparser'
KJson = require 'koa-json'
KRouter = require 'koa-trie-router'
KLogger = require 'koa-logger'
app = new Koa()
router = new KRouter()

app.use KLogger()
app.use KJson pretty: false, param: 'pretty'
app.use KBodyParser detectJSON: (ctx)->true

router.post "/Plugin.Activate", (ctx)->
    ctx.body =  "Implements": ["IpamDriver"]

router.post "/IpamDriver.GetCapabilities", (ctx)->
    ctx.body = {
        "RequiresMACAddress": false
        "RequiresRequestReplay": true
    }

router.post "/IpamDriver.GetDefaultAddressSpaces", (ctx)->
    ctx.body = {
        "LocalDefaultAddressSpace":"172.30.0.0/16"
        "GlobalDefaultAddressSpace":"172.30.0.0/16"
    }

router.post "/IpamDriver.RequestPool", (ctx)->
    ctx.body = {
        "PoolID":"112233"
        "Pool":"172.30.4.0/24"
        "Data":{
            "Allahu":"Akbar"
        }
    }

router.post "/IpamDriver.ReleasePool", (ctx)->
    ctx.body = {}

router.post "/IpamDriver.RequestAddress", (ctx)->
    req = ctx.request.body
    if req.Options?.RequestAddressType is 'com.docker.network.gateway'
        address = "172.30.4.1/24"
    else
        address = "172.30.4.9/24"
    ctx.body = {
        "Address":address
        "Data": {}
    }

router.post "/IpamDriver.ReleaseAddress", (ctx)->
    ctx.body = {}

app.use (ctx,next)->
    console.info "\n===REQUEST==="
    console.info ctx.request
    console.info "\n===BODY==="
    console.info ctx.request.body
    await next()
    console.info "\n===RESPONSE==="
    console.info ctx.body
    console.info "\n===END==="

app.use router.middleware()

app.use (ctx)->
    ctx.status = 404
    ctx.body = {"Error":"Not Found"}

app.listen 3000
