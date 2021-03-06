mocha_sprinkles = require "mocha-sprinkles"
toolkit = require "stream-toolkit"
util = require "util"

bottle_stream = require "../lib/4q/lib4q/bottle_stream"
file_bottle = require "../lib/4q/lib4q/file_bottle"
compressed_bottle = require "../lib/4q/lib4q/compressed_bottle"

future = mocha_sprinkles.future

writeTinyFile = (filename, data) ->
  toolkit.sourceStream(data).pipe(new file_bottle.FileBottleWriter(filename: filename, size: data.length))

validateTinyFile = (fileBottle, filename) ->
  fileBottle.type.should.eql bottle_stream.TYPE_FILE
  fileBottle.header.filename.should.eql filename
  fileBottle.readPromise().then (dataStream) ->
    toolkit.pipeToBuffer(dataStream).then (buffer) ->
      { header: fileBottle.header, data: buffer }


describe "CompressedBottleWriter", ->
  it "compresses a file stream with lzma2", future ->
    file = writeTinyFile("file.txt", new Buffer("the new pornographers"))
    toolkit.pipeToBuffer(file).then (fileBuffer) ->
      # quick verification that we're hashing what we think we are.
      fileBuffer.toString("hex").should.eql "f09f8dbc0000000d000866696c652e74787480011515746865206e657720706f726e6f677261706865727300ff"
      x = new compressed_bottle.CompressedBottleWriter(compressed_bottle.COMPRESSION_LZMA2)
      toolkit.sourceStream(fileBuffer).pipe(x)
      toolkit.pipeToBuffer(x).then (buffer) ->
        # now decode it.
        bottle_stream.readBottleFromStream(toolkit.sourceStream(buffer))
    .then (zbottle) ->
      zbottle.type.should.eql bottle_stream.TYPE_COMPRESSED
      zbottle.header.compressionType.should.eql compressed_bottle.COMPRESSION_LZMA2
      zbottle.decompress().then (bottle) ->
        validateTinyFile(bottle, "file.txt").then ({ header, data }) ->
          data.toString().should.eql "the new pornographers"

  # FIXME refactor
  it "compresses a file stream with snappy", future ->
    fileBottle = writeTinyFile("file.txt", new Buffer("the new pornographers"))
    x = new compressed_bottle.CompressedBottleWriter(compressed_bottle.COMPRESSION_SNAPPY)
    fileBottle.pipe(x)
    toolkit.pipeToBuffer(x).then (buffer) ->
      # now decode it.
      bottle_stream.readBottleFromStream(toolkit.sourceStream(buffer))
    .then (zbottle) ->
      zbottle.type.should.eql bottle_stream.TYPE_COMPRESSED
      zbottle.header.compressionType.should.eql compressed_bottle.COMPRESSION_SNAPPY
      zbottle.decompress().then (bottle) ->
        validateTinyFile(bottle, "file.txt").then ({ header, data }) ->
          data.toString().should.eql "the new pornographers"
