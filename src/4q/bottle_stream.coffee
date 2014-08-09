Q = require "q"
metadata = require "./metadata"
push_stream = require "./push_stream"
stream = require "stream"
util = require "util"
zint = require "./zint"

MAGIC = new Buffer(8)
MAGIC.writeUInt32BE(0xf09f8dbc, 0)
MAGIC.writeUInt32BE(0, 4)

TYPE_FILE = 0
TYPE_MAGIC = 15

class WritableBottleStream extends push_stream.PushStream
  constructor: ->
    super()

  writeMagic: ->
    @write MAGIC

  writeBottleHeader: (type, metadata) ->
    # bottle header: TTTTLLLL LLLLLLLL (T = type, L = metadata length)
    if type < 0 or type > 15 then throw new Error("Bottle type out of range: #{type}")
    buffers = metadata.pack()
    length = if buffers.length == 0 then 0 else buffers.map((b) -> b.length).reduce((a, b) -> a + b)
    if length > 4095 then throw new Error("Metadata too long: #{metadataBuffer.length} > 4095")
    buffers.unshift new Buffer([ (type << 4) | ((length >> 8) & 0xf), (length & 0xff) ])
    @write(Buffer.concat(buffers))

  # write a stream as data. if length == 0, we assume it's a bottle (which has indeterminate length).
  writeData: (inStream, length, final = true) ->
    header = (if length? then 0x40 else 0x80) | (if final then 0x20 else 0)
    @write(new Buffer([ header ])).then =>
      if length? then @write(zint.encodeZint(length)) else Q()
    .then =>
      @spliceFrom(inStream, length)

  writeEndData: -> @write(new Buffer([ 0 ]))


class ReadableBottleStream
  constructor: (@stream, magic = false) ->
    @buffered = null
    @active = true
    @savedError = null
    @waiting = null
    @state = if magic then "magic" else "header"
    @stream.on "readable", => @readable()
    @stream.once "end", => @active = false
    @stream.once "error", (err) => @throwError(err)

  throwError: (err) ->
    @active = false
    @savedError = err

  readable: ->
    switch @state
      when "magic" then @readMagic()
      when "header" then @readHeader()
      when "metadata" then @readMetadata()

  readMagic: ->
    @state = "magic"
    return unless @active
    buffer = @stream.read(MAGIC.length)
    return unless buffer?
    if buffer != MAGIC then @throwError(new Error("Invalid magic header"))
    @readHeader()

  readHeader: ->
    @state = "header"
    return unless @active and (not @buffered?)
    buffer = @stream.read(2)
    return unless buffer?
    type = (buffer[0] >> 4) & 0xf
    metadataLength = ((buffer[0] & 0xf) << 8) | (buffer[1] & 0xff)
    @buffered = { type, metadataLength }
    @readMetadata()

  readMetadata: ->
    @state = "metadata"
    return unless @active
    buffer = @stream.read(@buffered.metadataLength)
    return unless buffer?
    @buffered.metadata = metadata.unpack(buffer)
    

exports.MAGIC = MAGIC
exports.WritableBottleStream = WritableBottleStream
