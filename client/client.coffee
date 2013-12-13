fs = require 'fs'
path = require 'path'
url = require 'url'
os = require 'os'
readdirp = require 'readdirp'
http = require 'http'
https = require 'https'
request = require 'request'
crypto = require 'crypto'
_ = require 'underscore'
mkdirp = require 'mkdirp'
manifest = require '../manifest'
async = require 'async'
zlib = require 'zlib'

# Number of files to read and digest at the same time
DEFAULT_THREADS = 4

# Get the server's manifest
getServerManifest = (url, cb) ->
  request url, (err, res, body) ->
    if err
      cb err
    else
      try
        cb null, JSON.parse(body)
      catch ex
        cb ex

downloadFile = (hostUrl, localPath, file, cb) ->
  filePath = path.join(localPath, file)
  # Recusively build directory if it doesn't exist
  mkdirp path.dirname(filePath), (err) ->
    if err?
      cb err
    else
      fullUrl = url.resolve(hostUrl+'/', './'+file)
      opts =
        url: fullUrl
        headers:
          'accept-encoding':'gzip'
      console.log "Downloading #{opts.url} to #{filePath}"
      request(opts).pipe(zlib.createGunzip()).pipe(fs.createWriteStream(filePath))
        .on('close', cb)
        .on('error', cb)

# Process a manifest difference object to make the local directory match the source
processManifestDiff = (diff, localPath, hostUrl, numThreads, cb) ->
  applyDownload = (file, cb) -> downloadFile hostUrl, localPath, file, cb
  async.series [
    (cb) ->
      # Delete all removed files
      async.mapLimit (diff.removed.map (file) -> path.join(localPath, file)), numThreads, fs.unlink, cb
    (cb) ->
      # Delete all changed files (note we may want to use deltas here)
      async.mapLimit (diff.changed.map (file) -> path.join(localPath, file)), numThreads, fs.unlink, cb
    (cb) ->
      # Download all added files
      async.mapLimit diff.added, numThreads, applyDownload, cb
    (cb) ->
      # Download all changed files (note: we may want to download deltas and apply them)
      async.mapLimit diff.changed, numThreads, applyDownload, cb
  ], cb

module.exports = (localPath, url, opts, callback) ->
  opts = opts || {}
  if not opts.threads?
    opts.threads = DEFAULT_THREADS
  getServerManifest url, (err, serverManifest) ->
    if err?
      callback err
    else
      # Verify root directory exists and create it if it doesn't
      fs.exists localPath, (exists) ->
        if not exists
          mkdirp.sync localPath
        manifest.get localPath, (err, localManifest) ->
          if err?
            callback err
          else
            manifestDiff = manifest.diff serverManifest, localManifest
            # Process the diff to make our local directory match
            processManifestDiff manifestDiff, localPath, url, opts.threads, callback

