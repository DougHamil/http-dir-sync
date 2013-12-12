fs = require 'fs'
path = require 'path'
url = require 'url'
os = require 'os'
readdirp = require 'readdirp'
crypto = require 'crypto'
_ = require 'underscore'
mkdirp = require 'mkdirp'
async = require 'async'

DEFAULT_THREADS = 4

# Build a manifest object using the provided directory as the root
findAllFiles = (localPath, cb) ->
  fs.exists localPath, (exists) ->
    if exists
      streamErr = null
      paths = []
      fileStream = readdirp {root: path.resolve(localPath)}
      fileStream.on 'data', (entry) ->
        if entry.stat.isFile()
          paths.push {path:entry.path, fullPath:path.join(localPath,entry.path)}
      fileStream.on 'error', (err) ->
        streamErr = err
        fileStream.destroy()
      fileStream.on 'close', ->
        cb streamErr, paths
      fileStream.on 'end', ->
        cb streamErr, paths
    else
      cb null, []

# Given a list of file paths, return a mapping of each path to the checksum of the file
buildManifestForFiles = (paths, numThreads, cb) ->
  # Track progress
  totalToDigest = paths.length
  numDigested = 0
  # Digest a single file and return the filepath and the hex digest
  digestFile = (file, cb) ->
    stream = fs.createReadStream file.fullPath
    digest = crypto.createHash 'sha1'
    stream.on 'data', (data) ->
      digest.update data
    stream.on 'error', (err) ->
      return cb err
    stream.on 'end', ->
      numDigested++
      cb null, {path:file.path, hex:digest.digest('hex')}
  # Digest all files, numThreads at a time
  async.mapLimit paths, numThreads, digestFile, (err, results) ->
    if err?
      cb err
    else
      manifest = {}
      for result in results
        manifest[result.path] = result.hex
      cb null, manifest

# Given a goal manifest and a current manifest, determine the operations that need to
# happen to make the current match the goal
diffManifests = (goal, cur) ->
  curPaths = (key for key of cur)
  goalPaths = (key for key of goal)

  # Find files added/removed
  removed = _.difference curPaths, goalPaths
  added = _.difference goalPaths, curPaths

  changed = []
  # Find changed files
  for filePath, checksum of goal
    if checksum != cur[filePath]
      changed.push filePath
  return {changed:changed, added:added, removed:removed}

# Get a manifest for the specified path
exports.get = (localPath, opts, cb) ->
  if cb?
    opts = opts || {}
  else
    cb = opts
    opts = {}
  opts.threads = opts.threads || DEFAULT_THREADS
  findAllFiles localPath, (err, files) ->
    if err?
      cb err
    else
      buildManifestForFiles files, opts.threads, cb

# Diff two manifests and return operations to get to the first from the second
exports.diff = diffManifests
