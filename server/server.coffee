fs = require 'fs'
path = require 'path'
url = require 'url'
manifest = require '../manifest'
zlib = require 'zlib'

module.exports = (localPath, name) ->
  state =
    urlName: '/'+name
    manifest: null
    localPath:localPath
    urlNameLength: ('/'+name).length
  httpdir =
    # Update local manifest
    update: (cb) ->
      manifest.get localPath, (err, localManifest) ->
        state.manifest = localManifest
        cb err, localManifest

    # Middleware handler
    handler: (req, res, next) ->
      if req.method is 'GET'
        # A get on the root means return the manifest
        if req.url is state.urlName
          res.json state.manifest
        # A path with the name as root means a file request
        else if req.url.indexOf urlName == 0
          filePath = req.url.substring(state.urlNameLength)
          console.log "Request for file #{filePath}"
          fullPath = path.join(state.localPath, filePath)
          fs.exists fullPath, (exists) ->
            if not exists
              res.send 400
            else
              res.writeHead 200, {'content-encoding':'gzip'}
              fs.createReadStream(fullPath).pipe(zlib.createGzip()).pipe(response)
      else
        next()
